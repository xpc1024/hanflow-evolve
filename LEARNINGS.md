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

- **CLI stub 命令已补全 (v1.0.1)**: 17 个命令全部实现 (12 真实 + 5 降级)。不再阻塞。
- **DOCKER/K8S sandbox 占位符**: `hanflow/isolation/sandbox.py` docstring 明确
  "DOCKER/K8S provisioning is wired in Phase 8/10; Phase 7 ships LOCAL + NONE"。
  当前只有 LOCAL + NONE 可用, 容器/_pod 隔离未实现 → 生产部署安全边界缺失。
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

1. 补齐 LLM 流式输出 (高优先级技术债 + 用户体验直接改善)。
2. DOCKER sandbox 落地 (生产安全边界)。
3. ~~CLI stub 逐个接通 SDK~~ ✓ 已完成 (v1.0.1, 2026-W29)。
4. MCP remote transport 实现 (工具生态)。
5. [2026-W29] github PAT 配置 (github push 失败, 需配 Access Token)。
6. [2026-W29] score-signals.py Windows 路径 bug (affected_modules 显示 "E:")。
7. [2026-W29] github-sync.sh 适配 master 分支 (当前硬编码 main)。
8. [2026-W29] Group B 命令后端 (metrics/search/eval/datasets/worker)。
5. 引入 pytest-cov 建立覆盖率基线 (低成本, 为后续重构兜底)。

注意: prioritization 阶段会按 source_weights + theme_weights 重算, 此处仅作人读参考。
