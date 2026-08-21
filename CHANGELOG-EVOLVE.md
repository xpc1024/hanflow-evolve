# CHANGELOG-EVOLVE.md — hanflow-evolve 自身变更日志

本文件记录 **hanflow-evolve (LOOP 系统) 自身** 的演进, 而非 hanflow 框架的变更。

- hanflow 框架的发布变更请见 hanflow 仓库的 CHANGELOG (由 LOOP 的 release 阶段在
  `versioning.changelog_auto: true` 时自动追加)。
- 此处条目由人工或 LOOP 工具链维护, 按时间倒序, 遵循 Keep a Changelog 风格 +
  conventional commits 前缀 (`feat:` / `fix:` / `chore:` / `docs:` 等)。

## [Unreleased]

### Added
- 初始脚手架: 目录结构、config.yaml、state.yaml、LEARNINGS/BACKLOG/CHANGELOG 模板
  (Phase E0)。

## cycle 2026-W34-1.2.4 (2026-08-20) — loop-toolchain-state-sync-and-signal-filter

**evolve-only 周期** (hanflow 零改动, 不发空 tag, v1.2.3 保持)。修复 W32 发现的
LOOP 工具链两问题 + 顺带核实销账:

### Fixed
- `signal-gather.sh` `collect_learnings()` 行首 `~~` 过滤: 已完成 LEARNINGS 条目
  不再采集 (TDD 红→绿; learnings 19→11, 下周期起队首成员净化)。
- LEARNINGS「下次优先」#1 (version-bump state 同步) 核实**早已修复** (d18e9b9),
  销账; #2 (本条) 完成。

### Added
- `tests/test-signal-gather.bats`: 过滤用例 (3 类断言, 含"正文提及已修但行首无
  划线"边界不误杀)。

### 发现的新工具链问题 (待后续 cycle)
- `update-backlog.sh` 重跑会**清空 BACKLOG Done 段** (Done 记录仅活在 learn 手动
  维护后、下次重跑前的窗口; 本次已从会话上下文恢复 W30-W34 四条记录)。
- `score-signals` member_score 与条数解耦, 过滤僵尸条目后主题分数不降。

### LOOP 工件
- `cycles/2026-W34-1.2.4/`: signals.json / scored.json / direction.md /
  audit-direction.md / design.md / audit-design.md / execution-plan.md /
  test-report.md / retro.md; specs/plans 副本。

## cycle 2026-W32-1.2.2 (2026-08-04) — docker-provisioner-real-contract-tests

完整跑通一个 evolve cycle, 产物全部落盘。本周期是 **hanflow 框架** 的 patch release
(v1.2.3), 不含 LOOP 系统自身的代码改动, 但产出如下 LOOP 工件:

### LOOP 工件
- `cycles/2026-W32-1.2.2/`: signals.json / scored.json / direction.md / audit-direction.md /
  design.md / audit-design.md / execution-plan.md / test-report.md / retro.md
- `docs/superpowers/specs/`: direction + design 副本
- `docs/superpowers/plans/`: execution-plan 副本

### 发现的 LOOP 工具链问题 (待后续 cycle 修)
- `version-bump.sh` 不同步 `state.yaml.current_version` → site-sync 读到滞后版本 (本周期
  手动修正)。详见 retro.md "下次优先 #1"。
- `signal-gather.sh` 不过滤已完成 LEARNINGS 条目 → BACKLOG 队首 learnings-priority 混入
  已完成项。详见 retro.md "下次优先 #2"。
- `charter-check --doc` 的"影响模块"正则误报 ADR WARN (本周期 direction/design 各 1 次
  假阳性)。详见 retro.md "下次优先 #15"。

## 版本历史

### hanflow v1.2.1 (cycle 2026-W31-1.2.1, 2026-07-29) — 清零 S0 技术债门

**主题**: clear-preexisting-tech-debt-s0-gates(human_override)。用户指出 CI 的 S0 门失败全在
无关的 api/routes 等预存技术债,要求优先修复。

**修复内容**(纯 fix,零运行时行为变更):
- `models/providers/base.py`: 加 `__all__` 修复 `StreamChunk`/`TokenUsage` 重导出 → 消除 16 个
  mypy attr-defined(影响 13 个 provider/router 文件,真实契约 bug)。
- `isolation/docker_provisioner.py`: `_import_aiodocker` 返回注解 + `type[Any]`(原 TYPE_CHECKING
  stub 的 `DockerError(Exception)` 触发 charter §2 不变量 1,已弃用)。
- `pyproject.toml`: `[[tool.mypy.overrides]]` 为无 stub 的 aiodocker 设 ignore_missing_imports。
- `api/routes/{workflows,webhooks}.py`: `dict`→`dict[str,Any]`,补 `dry_run`/`_mock_output`/
  `generate` 返回注解。
- `api/routes/{observe,schema,workflows}.py`: 删未用 vars/imports,修 E501/E741/F841。
- `ruff format` 跨 25 文件(含上周期 isolation/runtime/core 漏 format 文件)。

**门结果**: ruff check 15→0 / ruff format 25→clean / mypy 28→0 / pytest 411→417 passed(+6 来自
PR #5,无回归) / charter-check GREEN / smoke 4/4。

**LOOP 工具链修复**:
- `scripts/version-bump.sh`: 修 `api_init` 路径 bug(`hanflow/api/__init__.py` 而非 `api/__init__.py`,
  2 个 cycle 手动绕过后清零)。现可一键对齐 4 处版本号。

**集成**: 拉取合并贡献者 PR #5(`iajie/evolve/contrib-2026-W31-001`: anthropic/ollama/deepseek/
vllm provider 实现 stream()),Fast-forward 无冲突。

### hanflow v1.2.0 (cycle 2026-W30-1.1.1, 2026-07-21) — DOCKER sandbox 隔离

**主题**: DOCKER sandbox provisioner 落地(生产安全边界)。用户 2026-07-17 明确指定下次优先(human_override)。

**新增能力**:
- `core/sandbox_contract.py`: `SandboxMode/SandboxResources/RunSandbox` 从 isolation 上移到 core;新增 `SandboxProvisioner` Protocol + `ProvisionedSandbox` + `ExecInterface`。
- `isolation/local_provisioner.py`: `LocalProvisioner` + `_LocalExec`(host subprocess)。
- `isolation/docker_provisioner.py`: `DockerProvisioner` + `_DockerExec`(aiodocker,资源限额 + bind mount + destroy)。
- `runtime/build_sandbox.py`: 组合根,按 mode 分派 provisioner。
- `tools/builtin/code_exec.py`: DOCKER 路径(exec_interface 注入)+ Phase 8 文案对齐(原 Phase 7)。
- `core/errors.py`: 6 个新错误子类(`SandboxError` + 4 + `ToolWhitelistError`)。
- `config.yaml.IsolationConfig`: mode 默认 local(向后兼容)+ docker.base_image。

**架构合规**:
- 依赖倒置(§3):Protocol 在 core,实现在 isolation,组合根注入。**无 core→isolation 反向 import**(charter-check layering GREEN)。
- per-run 不变量(§2.5):`dedicated_sandbox=True/False` 都复用 run container + 容器内 subdir。
- §5 禁止吞异常:`spawn_agent` 对 `SandboxError` 子类透传(保留 code/retryable)。

**测试**: 59 个新测试(8 文件),含 `dedicated_sandbox` 契约 + 错误透传 + DockerProvisioner 契约(skipif no daemon)。全量 pytest 408 passed,charter-check --diff 5/5 GREEN,ruff 本 cycle 文件全绿,smoke-test 4/4 PASS。

**向后兼容**:`isolation/sandbox.py` re-export 上移的类型;`RunSandbox.create()` 保留为 LOCAL/NONE 快捷方式;`config.isolation.mode` 默认 local,所有现有行为不变。

**顺手清理**:
- `enforce_tool_whitelist`: 用专用 `ToolWhitelistError` 替代基类 `HanflowError`。
- `spawn_agent`: 取 `trace.span()` yield 的 Span,emit span_id(原忽略)。
- `scripts/smoke-test.sh`: 修预存在的 `from_yaml(path)` bug(应传 YAML 文本)。

### hanflow v1.1.0 (cycle 2026-W29-1.0.2, 2026-07-17) — LLM 流式输出

详见 hanflow 仓库 CHANGELOG / `cycles/2026-W29-1.0.2/`。
