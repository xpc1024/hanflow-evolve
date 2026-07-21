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

## 版本历史

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
