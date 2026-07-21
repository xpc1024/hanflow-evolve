# LEARNINGS.md — hanflow-evolve 持久化学习库 (spec §7)

本文件是 LOOP 系统的长期记忆。每个 cycle 结束时由 retro 阶段更新；direction/
design/execute/audit 阶段读取此处以保持跨 cycle 一致性。

记录原则:
- 只写**已验证**的事实 (源码证据 / 测试结果 / 用户明确反馈), 不写猜测。
- 每条尽量给出文件路径或 spec 段落作为来源。
- 冲突时以最新条目为准, 旧条目标注 superseded。

---

## 框架架构模式

hanflow 是基于 LangGraph 的高控制力 agent 框架。核心分层:

- `core/` — DSL / context / state / expr / result / errors (纯逻辑, 无 IO)
- `atoms/` — 可复用执行单元 (base / execution / research)
- `orchestration/` — DSL→LangGraph 编译器、节点注册表、context 实现
- `models/` — LLM provider 抽象 + 路由 + 策略 (cost/fallback/role/static/task)
- `memory/` — 文件系统 + 技能记忆, 可插拔后端
- `runtime/` — scheduler / run loop / worker (部分占位)
- `isolation/` — 子 agent 隔离契约 (LOCAL/DOCKER/K8S/NONE)
- `persistence/` — checkpoint + resume
- `tools/` — 工具调用 + MCP transport
- `observability/` — trace 抽象 (LangSmith / OTel provider)
- `api/` — FastAPI HTTP + WebSocket
- `cli/` — typer 命令矩阵

### 设计不变量

> **权威定义见 `CHARTER.md §2`**；本节为速查摘要。守护脚本见 `scripts/charter-check/`。

以下模式在重构/演进时**不可破坏**, 否则破坏框架契约:

1. **统一错误层级**: 所有框架错误继承 `HanflowError` (hanflow/core/errors.py), 带
   稳定 `code` (机器可读) + `retryable` 标志 + `run_id`/`node_id`/`span_id` 关联坐标。
   atoms/primitives **永不吞异常**; 由 orchestration 包装层捕获, 记录 `NodeState.error`
   + trace error span, 再按 `on_error` 策略决定下一步。
2. **异步优先 (async-first)**: 全框架 ~278 处 `async def`; 同步入口仅 CLI/SDK 边界用
   `asyncio.run` 桥接。新增 IO/计算 API 默认 `async def`。
3. **Pydantic v2 配置/数据模型**: ~29 个文件使用 `BaseModel` 做配置与状态结构;
   `ConfigDict` 控制行为。新增结构化数据走 Pydantic, 不要裸 dataclass。
4. **DSL→编译→执行 三段式**: `WorkflowDSL.from_yaml` → `Compiler.compile` →
   `NodeExecutorRegistry` 分派。新增节点类型走 registry 注册, 不要在 compiler 里硬编码。
5. **per-run sandbox (非 per-agent)**: `RunSandbox` 是 run 级共享资源; 子 agent 只在
   其下分得 subdir。隔离级别 LOCAL/DOCKER/K8S/NONE 可选, 但契约固定。
6. **spec 段落引用**: 设计决策在 docstring 中以 `§N.N` 回链 spec, 便于追溯。

### 编码风格

- 文件头 docstring 说明本模块职责 + 回链 spec 段落 (如 `§12.10`, `§13.6`)。
- 普遍使用 `from __future__ import annotations` (85/109 文件) → 类型注解走 PEP 563,
  字符串形式, 优先 `X | None` 而非 `Optional[X]`。
- 枚举用 `StrEnum` (字符串值, JSON 友好)。
- 类型: `list[str]` / `dict[str, Any]` 内置泛型, 不用 `typing.List`。
- 错误信息带上下文 (run_id/node_id), 便于 trace 关联。
- 占位代码用明确标记: `NotImplementedError("...lands in Phase N (reason)")` 或
  docstring 注明 `wired in Phase N`, 不静默 no-op。

---

## 已知技术债

来源于 hanflow 源码扫描 (signal: source_stubs)。按修复成本/影响排序。

### 高优先级

- **[2026-W29-1.0.2] LLM 流式输出已落地 (v1.1.0)**: StreamChunk + Protocol.stream + Router.stream + emit_run_event + openai/glm 实现 + 4 占位。已完成。
- **[2026-W29-1.0.2] version-bump.sh 路径 bug**: 脚本找 `api/__init__.py`，实际在 `hanflow/api/__init__.py`（包内）。**本 cycle (2026-W30-1.1.1) 再次手动 bump 绕过，脚本待修**。
- **[2026-W29-1.0.2] hanflow 远程 master→main 迁移**: 用户决定废弃 master 只留 main。GitHub/Gitee 的 main 已含 v1.1.0，但远程 master 分支未删（待清理）。github-sync.sh 硬编码 main 现在反而对了。
- **[2026-W30-1.1.1] DOCKER sandbox 已落地 (v1.2.0)**: core/sandbox_contract.py(类型上移 + SandboxProvisioner Protocol)+ LocalProvisioner + DockerProvisioner (aiodocker) + K8sProvisioner 占位 + build_sandbox 组合根 + code_exec DOCKER 路径。**DOCKER 契约测试本地未实跑(Docker Desktop 未启)**,需在有 daemon 的环境验证 4 个 skipif 测试。
- **[2026-W30-1.1.1] Pydantic v2 不接受 typing.Protocol 作为字段类型**: 即使 `arbitrary_types_allowed=True` 也抛 `SchemaError: 'cls' must be valid as the first argument to 'isinstance'`。`ProvisionedSandbox.exec_interface` 改用 `Any` + docstring 说明运行时契约是 `ExecInterface`(@runtime_checkable 可用 isinstance 校验)。**设计文档凡是 Pydantic 模型持 Protocol 字段,都用 Any**。
- **[2026-W30-1.1.1] mypy 在 Python 3.13 + numpy stub 上无法运行**: mypy 2.3 不支持 `type` 语句,numpy stub 用了它。本 cycle mypy 完全跑不起来(P9 verify 标记为环境阻塞)。考虑 pin mypy 或用 standalone Python 3.12 container。
- **[2026-W30-1.1.1] smoke-test.sh from_yaml bug 已修**: 原脚本 `WorkflowDSL.from_yaml(path)` 传文件路径,实际 API 接受 YAML 文本。`yaml.safe_load(裸字符串)` 返回字符串本身 → pydantic 拒绝。commit `aa4763d` 已修。顺手修了内嵌 yaml 用 `list[WorkflowNode]` + NodeType 字面量(原是 dict-of-dicts + kind)。
- **[2026-W30-1.1.1] Windows 路径在容器/POSIX 上下文下必须手动 POSIX 化**: `Path("/workspace") / "agent-x"` 在 Windows host 上返回 `\workspace\agent-x`,Docker container 内无法识别。spawn_agent 用 `str(...).replace("\\", "/")` + 字符串拼接绕过。**新增规则:任何涉及容器内路径都用字符串拼接,不用 Path /**。
- **[2026-W30-1.1.1] score-signals.py Windows 路径 bug 仍未修** (LEARNINGS #6 旧账): 本 cycle 再次复现——所有 source_stub 信号被错聚成 `stub-E:` 主题(drive letter 当 module 名)。需修 `_signal_module()` 跳过 Windows 盘符。
- **CLI stub 命令已补全 (v1.0.1)**: 17 个命令全部实现 (12 真实 + 5 降级)。不再阻塞。
- **DOCKER/K8S sandbox → DOCKER 已落地**: Phase 8 = cycle 2026-W30-1.1.1 已实现 DOCKER 档(LOCAL/DOCKER/NONE 三档可用);K8S(Phase 10)仍占位。`hanflow/isolation/sandbox.py` docstring 已更新。
- **多 worker scheduler no-op**: `hanflow/runtime/scheduler.py` 的 `enqueue()`/
  `reclaim()` 是占位 ("real queue wiring lands in Phase 10"), `pick_node` 仅算哈希
  但不入队 → K8s 多副本水平扩展形同虚设。
- **~17-18 个 CLI stub**: `hanflow/cli/main.py` 用循环批量注册 18 个 stub 命令
  (resume/cancel/runs/status/approve/edit/reject/reroute/trace/logs/artifacts/
  metrics/tools/search/eval/datasets/worker/config), 每个只打印 "delegates to SDK"
  → CLI 几乎不可交互使用, 全靠程序化 SDK。

### 中优先级

- **LLM token 流式未实现**: 真实 provider (openai/anthropic/glm/ollama/deepseek)
  仅实现 `complete()`, 没有 `stream()`; 仅 `fake.py` 有流式。→ 用户体验差, 长生成
  无增量输出。
- **外部 MCP transport NotImplementedError**: `hanflow/tools/transport.py:75`
  `call_tool` 直接 `raise NotImplementedError("remote tool call requires a live MCP
  server (integration test)")` → 远程 MCP 工具调用在生产不可用。
- **Helm chart 空**: `deploy/helm/hanflow/` 及 `templates/` 目录存在但**完全为空**
  (无 Chart.yaml, 无 deployment.yaml) → 无法 `helm install` 部署。

### 低优先级

- **migrations 非 alembic**: `migrations/001_create_runs_and_hitl_records.py` 自述
  "standalone SQL migration (not alembic-managed yet)" → 无版本化迁移链, 升级易出错。
- **无 pytest-cov**: `pyproject.toml` dev 依赖只有 pytest/pytest-asyncio, 没有
  pytest-cov → 测试覆盖率不可测, 回归无量化基线。

---

## 有效实践（已验证）

### charter-check 守护体系（2026-W29-1.0.2 + 2026-W30-1.1.1 全 cycle 验证）

经 LLM streaming cycle + DOCKER sandbox cycle 完整跑通验证，架构守护体系**有效、可运行、自我改进**：

- **P4b 两阶段审核高价值**：2026-W29 第 1 轮 Layer-2 抓到 3 个实质 design 缺陷（错误包装致 fallback 不触发 / ctx.event 数据流断链 / glm async 误判）。**2026-W30 第 1 轮又抓到 3 个新 design 缺陷**（HanflowError `code=` kwarg 误用 → TypeError / ProvisionedSandbox 前向引用 / spawn_agent 吞 SandboxTimeoutError 降级基类）+ 2 个 direction 缺陷（core→isolation 反向依赖 / dedicated_sandbox 自相矛盾）。**全部实现前修复，不可跳过。**
- **charter-check --diff 阻止架构漂移**：2026-W29 P7 抓到 `core→models` 反向依赖（StreamChunk 定义位置），forcing 修复（移到 core/result.py）。2026-W30 类型上移（SandboxMode/Resources/RunSandbox → core/sandbox_contract.py）就是为了化解潜在的 core→isolation 反向依赖,提前在 design 阶段就避免。policy-as-code 核心价值。
- **实战驱动 charter-check 自身演进**：跑真实 cycle 暴露并修复多个缺陷（--doc 正则 ADR-0006 / --diff base ADR-0007 / core→models 抓到后修代码）。
- **设计文档先探查 fixture 再写计划**：execution-plan 的 NexusState/WorkflowNode 构造假设常与实际不符，subagent 要现读 conftest。计划阶段先跑 fixture 探查可省后续调整。**2026-W30 用 Explore agent 一次性探查 8 个文件,significantly 减少 P8 调整次数**。
- **commit 用 `git add <具体文件>` 不用 `-A`**：`-A` 会扫进运行时产物（workflows/*.yaml），跟着 merge 进 release。已 gitignore workflows/*.yaml + web/web-dev.log。
- **release 前校验 LICENSE 完整性**：master 的 LICENSE 曾是空文件（0 行），靠 github/main 恢复。

### DOCKER sandbox cycle 新增有效做法（2026-W30-1.1.1）

- **fake provisioner + skipif 守护让可选依赖测试无环境也绿**：DockerProvisioner 的 4 个生命周期测试用 `pytest.mark.skipif(not _docker_available())` 自动跳过无 daemon 环境,unit/dep_missing 测试仍跑。这是"可选 extra + 契约测试"的标准模式,未来 firecracker/K8S 同样适用。
- **类型上移化解反向依赖是真解**：当 L4 模块(`isolation`)的数据类型需要被 L0 契约引用时,优先评估类型本身是否符合 core 定位(纯数据、无 IO)。符合则上移 + re-export,而非在 core 用结构性 Protocol 绕。
- **`aiodocker` 这类 optional dep 用 lazy import + 早期失败**:`from aiodocker import Docker` 在方法顶部而非模块顶部,让 ImportError 立即包成 `SandboxDependencyMissingError`(非 retryable),而不是模块加载失败。`_import_aiodocker()` helper 复用。
- **Per-run 不变量的契约测试**:`spawn_agent(spec.dedicated_sandbox=True)` 与 `False` 都断言 `provisioner.provision.call_count == 0`,是 §2.5 不变量的可执行守护。
- **spec/Plan 文档用 checkbox `- [ ]` 步骤化**:`superpowers:writing-plans` 的格式,每 task 含写测试→跑失败→实现→跑通→commit 5 步,agent 直接执行无歧义。

### DOCKER sandbox cycle 失败教训（2026-W30-1.1.1）

- **设计文档 typing.Protocol 字段方案需要验证可行性**:design 初稿写 `ProvisionedSandbox.exec_interface: ExecInterface`(Protocol),P8 T2 第一次跑测试就 SchemaError。**audit round 1 报告说"勉强成立",实际跑不起来**。教训:audit subagent 对"Pydantic 字段类型"的判断不能只看类型签名,要在心里跑一遍 Pydantic 模型构建。
- **PIP install background 任务在本机经常卡住**:多次 `pip install -e ".[dev]"` 后台跑 stdout/stderr 都空,需要手动 `pip install <package>` 同步阻塞。教训:本机环境用同步 pip,不用 background。
- **smoke-test 的"自检测试"需要在每个 P9 都跑**:本 cycle catch 了 `from_yaml(path)` 这个预存在 bug(否则它会 FAIL,误判本 cycle 代码出问题)。建议加一个 smoke-test-of-smoke-test,或在 P1 SCAN 顺带跑 smoke-test。

---

## 用户偏好

记录用户/运维对 hanflow-evolve 流程的明确偏好, direction 阶段必须遵守。

### 版本策略

- **单主题版本 (single-theme release)**: 每个 cycle 只交付一个主题, 不混合多个 feature。
- **语义化版本 + conventional commits**: `feat→minor`, `fix→patch`, `breaking→major`。
- **v1.0.0 基线**: config.yaml `versioning.baseline: "1.0.0"`; 当前源码
  `hanflow/__init__.py` 实为 `0.1.0`, 由 `align_on_release: true` 在首次 release 对齐。
- **权威版本源**: `hanflow/__init__.py` 的 `__version__`, 其它地方 (`pyproject.toml`
  当前 `0.0.0` 等) 在 release 时对齐。

### 流程偏好

- **3 个硬门 (hard gates)**: direction / design / execute 后各设审计门, 不过不进下一阶段。
- **官网仅特性变化同步**: `release.site_sync.on_feature_change_only: true` — 纯 fix/refactor
  不触发 hanflow-site 重建, 减少噪声。
- **竞品权重最低**: `prioritization.source_weights.competitor: 15` (github/learnings=40,
  source_stub=35) — 竞品观察只作灵感, 不驱动路线。
- **retro 必做**: `learning.retro_required: true` — 每个 cycle 必须产出 retro 并更新本文件。

### 设计偏好

- 演进优先**填补现有占位/技术债** (高信号), 而非追新概念。
- 多 locale (en/zh) 官网同步, 特性变更需双语。
- 风险/工作量大的主题在 prioritization 阶段直接降分 (effort_penalty / risk_penalty)。

---

## 有效做法

(随 cycle 累积; 记录"做了且效果好"的具体做法。初始为空。)

<!-- 示例格式:
- [cycle 0001] 在 audit 阶段强制跑 `ruff` + `mypy` + pytest 全量, 0 警告才放行 →
  回归率下降。来源: retro-0001.md
-->

---

## 失败教训

(随 cycle 累积; 记录"做了但失败/被回退"的具体做法及根因。初始为空。)

<!-- 示例格式:
- [cycle 0002] 尝试用裸 dataclass 替换 Pydantic 配置模型 → 与 ConfigDict/序列化
  不兼容, audit 门回退。根因: 违反设计不变量 #3。
-->

---

## 下次优先

下一轮 cycle 选主题时的候选方向 (按当前已知信号排序; direction 阶段会重新计算):

1. **[高] 在有 docker daemon 的环境实跑 DockerProvisioner 契约测试** —— 本 cycle (2026-W30-1.1.1) 4 个生命周期测试 skipif 跳过,真实 container create/exec/destroy 路径**未在 CI 验证**。下次有 daemon 时必须手跑(或加 GitHub Actions docker service)。
2. **[高] LOOP 框架自身技术债批量修**(可选独立 cycle):
   - `version-bump.sh` 路径 bug(api/__init__.py 实际在 hanflow/api/__init__.py,2 个 cycle 都手动绕过)
   - `score-signals.py` Windows 路径 bug(LEARNINGS #6,2 个 cycle 都复现)
   - smoke-test.sh 更全面自检
3. **[高] site_sync 触发**:本周期 site_sync_needed=true(docker-sandbox 是 feature),但 release 阶段未实际触发 hanflow-site 重建。v1.1.0 + v1.2.0 都未同步,需要把 hanflow-site 同步跑一遍。
4. **[中] mypy 环境修复**:Python 3.13 + numpy stub 阻塞,考虑 pin mypy + Python 3.12 container。
5. **[中] DOCKER sandbox 的镜像构建流水线**:本 cycle 用预构建 `python:3.11-slim`,但用户需要带 hanflow runtime 的定制镜像(含 SDK/依赖)。下个 cycle 可以做。
6. **[中] K8S sandbox 落地 (Phase 10)**:本 cycle 只占位 NotImplementedError。
7. **[中] MCP remote transport 实现**(工具生态,2 个 cycle 都是 source_stub 高信号)。
8. **[中] Group B 命令后端**(metrics/search/eval/datasets/worker)。
9. ~~DOCKER sandbox 落地~~ ✓ 已完成 (v1.2.0, 2026-W30-1.1.1)。
10. ~~补齐 LLM 流式输出~~ ✓ 已完成 (v1.1.0, 2026-W29-1.0.2)。
11. ~~CLI stub 逐个接通 SDK~~ ✓ 已完成 (v1.0.1, 2026-W29)。
12. **[低] 引入 pytest-cov 建立覆盖率基线** (低成本, 为后续重构兜底)。

注意: prioritization 阶段会按 source_weights + theme_weights 重算, 此处仅作人读参考。
