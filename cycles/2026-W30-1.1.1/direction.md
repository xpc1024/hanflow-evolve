# Direction: DOCKER Sandbox 隔离(生产安全边界)

- cycle_id: 2026-W30-1.1.1
- target_version: 1.2.0
- theme: docker-sandbox(human_override,用户 2026-07-17 明确指定下次优先)
- 日期: 2026-07-20
- 关联 spec: `§13.6`(子 agent 隔离)、`§5.3`(工具沙箱)、CHARTER §2.5(per-run sandbox 不变量)

## 动机

hanflow 当前的 `SandboxMode` 枚举声明了 `LOCAL / DOCKER / K8S / NONE` 四档,但**只有 LOCAL 与 NONE 真正实现**。DOCKER/K8S 在 `hanflow/isolation/sandbox.py:70-72` 与 `:147-148` 是占位:只分配了一个 uuid 形式的 `container_id` 字符串,**没有任何真实容器 provisioning**;`tools/builtin/code_exec.py:48` 的 docker 分支直接抛 `HanflowError("...Phase 7")`。

后果:`SandboxMode.DOCKER` 在生产部署中**形同虚设**——子 agent 仍跑在 host 上,`code_exec` 工具无法在隔离容器内执行用户代码。这是 hanflow 作为"高可控 agent 框架"的核心安全缺口:执行不可信代码 / 多租户 run 隔离 / 资源限额这三条生产要求都无法满足。

本 cycle 目标:**把 DOCKER 这档从"占位契约"做成"真实可用"**,作为后续 K8S 档(Phase 10)与多 worker scheduler 的前置基础。K8S 不在本 cycle 范围。

经源码探查,缺口边界清晰:
- `RunSandbox.create()`(`isolation/sandbox.py:59-80`)对 DOCKER 只生成假 `container_id`,无 provisioning。
- `spawn_agent()`(`isolation/sandbox.py:104-153`)对 `dedicated_sandbox=True + DOCKER` 分支是 `pass`(占位)。
- `CodeExecServer._exec_local()`(`tools/builtin/code_exec.py:50-69`)只支持 host 执行;docker 分支硬编码抛错。
- `pyproject.toml` 无任何 docker SDK 依赖。
- 现有 isolation 测试(`tests/isolation/test_sandbox.py`)只覆盖 LOCAL/NONE 与上下文隔离,无 DOCKER 路径。

## 目标(in scope)

1. **Provisioner 抽象**:新增 `SandboxProvisioner` Protocol(async-first,§2.2),定义 `provision(run_sandbox) -> ProvisionedSandbox` + `destroy(...)` 契约;提供 `LocalProvisioner`(host,包装现有 LOCAL 行为)+ `DockerProvisioner`(真实容器)两个实现。**契约是 L0,实现在 L4**(§3 依赖矩阵:isolation 可依赖 core,组合根 runtime 注入具体 provisioner)。
2. **RunSandbox 接入 provisioner**:`RunSandbox.create()` 不再硬编码 provisioning;新增组合根(runtime 层)的 `build_sandbox(...)` 把 provisioner 注入 `RunSandbox`,DOCKER 档调用 `DockerProvisioner.provision()` 生成真实 `container_id` + 挂载 workspace。**`RunSandbox` 模型字段保持向后兼容**(provisioner 是可选注入,缺省走原 LOCAL 逻辑)。
3. **资源限额落地**:`SandboxResources` 的 `cpu_limit / memory_limit_mb / timeout_seconds / disk_limit_mb / network_egress` 在 `DockerProvisioner` 中真实生效(Docker `--cpus / --memory / --network=none|custom / --storage-opt` + 进程 timeout)。
4. **code_exec DOCKER 路径**:`CodeExecServer` 在 `mode="docker"` 时把代码投递到 provisioned container 内执行(经 `docker exec` 或挂载 workspace + `python snippet.py`),产出与 `_exec_local` 同构的 `{stdout, stderr, returncode}`。
5. **依赖声明**:新增 optional-extra `docker = ["aiodocker>=0.23"]` 到 `pyproject.toml`;`DockerProvisioner` lazy import,无 docker extra 时给出明确错误(`HanflowError(code="SANDBOX_DEP_MISSING")`,非静默)。
6. **错误层级**:新增 `SandboxError(HanflowError)` 子类,带稳定 code(`SANDBOX_PROVISION_FAILED / SANDBOX_TIMEOUT / SANDBOX_DEP_MISSING / SANDBOX_DESTROY_FAILED`)+ `retryable` 标志。
7. **测试**:contract 测试用 fake provisioner(不开真实 docker);`DockerProvisioner` 的契约测试用 `pytest.mark.skipif(no docker daemon)` 守护,默认 CI 跳过(本机无 docker 时仍绿)。

## 非目标(out of scope)

- **K8S 档**——K8S provisioning 是 Phase 10,本 cycle 只产 `K8sProvisioner` 的 `NotImplementedError` 占位 stub(对齐 §4 编码规范),不实现。
- **Firecracker microVM**——`code_exec.py:19` 提到的 firecracker 选项保持占位,不在本 cycle 落地。
- **per-agent 容器**——CHARTER §2.5 明确 sandbox 是 **per-run**,子 agent 只共享 run sandbox 或分得 subdir。本 cycle 不引入 per-agent 容器(违反不变量)。
- **容器镜像构建流水线**——使用**预构建的基准镜像**(如 `python:3.11-slim`),不做 `docker build` 集成。镜像可配置(`config.yaml` 新增 `isolation.docker.base_image`),但镜像构建/推送不在范围。
- **多 worker scheduler 真实入队**——LEARNINGS 列的 scheduler 占位是独立技术债,本 cycle 不触碰 `runtime/scheduler.py`。
- **API/CLI 层的 sandbox 配置端点**——只做 SDK + config.yaml 层的接入,API/CLI 暴露留给下个 cycle。
- **网络 egress 策略引擎**——`network_egress` 字段只做到 `--network=none`(默认,完全禁网)与 `--network=host`(显式 opt-in)两档;细粒度 egress ACL 不在范围。

## 实现路径(3 选项 + 推荐)

### 路径 A:Provisioner Protocol + 组合根注入(推荐)

引入 `SandboxProvisioner` Protocol(core 层契约),`LocalProvisioner` / `DockerProvisioner` 在 isolation 层实现;`runtime/build_sandbox.py`(组合根)根据 `config.yaml.isolation.mode` 选择 provisioner 并注入 `RunSandbox`。`RunSandbox` 不再自己 provisioning。

- **优**:
  - **依赖倒置合规**(§3):契约在 core,实现在 isolation,组合根注入——完全符合矩阵。
  - **可测**:fake provisioner 即可测全链路,真实 docker 只在契约测试。
  - **K8S 可扩展**:Phase 10 只需加 `K8sProvisioner`,不动 core 契约与组合根。
  - **`RunSandbox` 保持纯数据模型**(Pydantic,§2.3):provisioner 不进模型字段,由组合根持有引用。
- **劣**:
  - 新增一个 Protocol + 组合根模块,改动面比 B/C 大。
  - 需要小心 `RunSandbox.create()` 现有 4 个调用点(`tests/isolation/test_sandbox.py` × 4)的迁移——保留 `create()` 为 LOCAL 默认快捷方式,DOCKER 走新组合根入口。

### 路径 B:直接在 `RunSandbox.create()` 里加 DOCKER 分支

在 `isolation/sandbox.py` 的 `create()` 内 `if mode == DOCKER:` 分支调 `aiodocker` 起 container,直接写 `container_id`。

- **优**:改动面最小,单文件。
- **劣**:
  - **违反依赖倒置**:isolation 直接依赖 `aiodocker`(L4→外部 SDK),core 契约没有抽象;K8S 来了又要改 `create()`。
  - **不可测**:不 mock `aiodocker` 就跑不了 DOCKER 单测,mock 污染面大。
  - **`RunSandbox` 模型既存数据又干活**:违反 §2.3 的"模型纯数据"约定。
  - **`create()` 签名膨胀**:要加 image/network/resources 等参数,污染 LOCAL/NONE 调用点。

### 路径 C:DockerSandbox 独立子类(继承 RunSandbox)

新增 `class DockerSandbox(RunSandbox)` 持有 container 与 provision 方法;`create()` 按 mode 分派到子类。

- **优**:面向对象封装,DOCKER 逻辑独立。
- **劣**:
  - **破坏 `RunSandbox` 的 BaseModel 契约**:Pydantic 模型做继承层次会触发 `ConfigDict` 与序列化复杂度,违反 §2.3 的"配置/数据模型"边界(模型应是扁平结构)。
  - 与路径 A 比,没解决"组合根注入"的核心问题,反而把行为塞进模型。
  - LEARNINGS #1 提到 StreamChunk 上个 cycle 就是因类似问题被 charter-check 抓回(行为混进数据模型)。

### 推荐:路径 A

理由:
1. **CHARTER 合规性最高**:依赖倒置(§3)+ 模型纯数据(§2.3)+ 异步优先(§2.2)三不变量同时满足,预计 `charter-check --diff` 全绿(像上个 cycle 一样验证守护不误报)。
2. **K8S 可扩展性**:Phase 10 加 `K8sProvisioner` 不动 core,符合"契约稳定、实现可换"。
3. **可测性**:fake provisioner 让 DOCKER 全链路单测免依赖真实 daemon,CI 稳定。
4. **最小惊讶**:`RunSandbox` 保持纯数据,provisioner 是显式注入的组合根关注点,而非隐式魔法。

## 影响模块

| 模块 | 改动 | 触发的 charter-check |
|---|---|---|
| `core/errors.py` | 新增 `SandboxError(HanflowError)` + 稳定 code 常量 | errors 层级(继承 HanflowError) |
| `core/sandbox_contract.py`(新) | `SandboxProvisioner` Protocol + `ProvisionedSandbox` 模型 | pydantic-data(模型)+ async-api(provision/destroy 是 IO 动词) |
| `isolation/local_provisioner.py`(新) | `LocalProvisioner` 包装现有 LOCAL 行为 | async-api |
| `isolation/docker_provisioner.py`(新) | `DockerProvisioner` 真实容器 provisioning + 资源限额 | async-api |
| `isolation/k8s_provisioner.py`(新) | `K8sProvisioner` NotImplementedError 占位 | async-api(占位也 async def) |
| `isolation/sandbox.py` | `RunSandbox.create()` 保留为 LOCAL 快捷方式;移除 DOCKER 假 container_id 逻辑(迁移到 provisioner);`spawn_agent` 的 dedicated_sandbox 分支调 provisioner | — |
| `runtime/build_sandbox.py`(新) | 组合根:读 config → 选 provisioner → 注入 RunSandbox | layering(runtime 可依赖 isolation,合规) |
| `tools/builtin/code_exec.py` | docker 分支调 provisioned container 的执行接口 | — |
| `pyproject.toml` | 新增 optional-extra `docker = ["aiodocker>=0.23"]` | — |
| `config.yaml`(hanflow-evolve) | 新增 `isolation` 段:`{mode, docker: {base_image, network, pull_policy}}` | — |
| `tests/isolation/` | 新增 fake provisioner + DOCKER contract 浴 + LocalProvisioner 浴 | — |

**关键:本 cycle 预期 charter-check 全绿**——所有改动都在合规范围内(异步 IO、Pydantic 模型、core 契约 + isolation 实现 + runtime 组合根、无跨层违规)。K8sProvisioner 占位用 `NotImplementedError("...lands in Phase 10")` 显式标记,遵循 §4。

## 风险评估

- **风险中**(effort large / risk medium,与 BACKLOG 标注一致):
  - **DOCKER daemon 可用性**:本机开发环境是否有 docker daemon?需在 design 阶段确认。若无,fake provisioner 仍可全链路单测,真实 docker 契约测试用 `skipif` 守护。**这是本 cycle 最大的环境依赖风险。**
  - **aiodocker 异步 API 边界**:`aiodocker` 的 container create/exec/stream 接口需仔细对齐;`docker exec` 的 stdout/stderr 流式读取与现有 `_exec_local` 的 `communicate()` 模型不同,design 阶段细化。
  - **资源限额语义**:`cpu_limit="2.0"` 映射到 `--cpus=2.0`;`memory_limit_mb=2048` 映射到 `--memory=2048m`;`disk_limit_mb` 需 `--storage-opt size=...`(仅 overlay2 支持)或降级到 quota;`network_egress` 默认 `none`。映射不全的平台行为差异需 design 阶段列清。
  - **workspace 挂载**:run workspace 是 host 路径,容器内需 bind mount;Windows 路径(本机)与 Linux 容器路径的转换是已知痛点(MSYS/native python 差异,LEARNINGS 已多次提及)。design 阶段需明确:本 cycle 的 DOCKER 路径**只在 Linux 部署环境验证**,Windows 开发机走 fake provisioner + LOCAL。
- **契约风险**:`SandboxProvisioner` Protocol 的 `provision()` 返回类型 `ProvisionedSandbox` 需含 `container_id / exec_interface / teardown_hook`,design 阶段定字段。
- **charter-check 风险**:新增 `core/sandbox_contract.py` 会让 core 多一个文件——但 core 不 import 任何 L4,合规;`SandboxProvisioner` 是 Protocol,与现有 `TraceExporter` Protocol 模式一致,precedent 充分。

## 验收标准

1. `SandboxProvisioner` Protocol 在 `core/sandbox_contract.py` 定义,含 `async def provision(...)` + `async def destroy(...)`;`ProvisionedSandbox` 为 Pydantic BaseModel。
2. `LocalProvisioner` 实现,包装现有 LOCAL 行为;`tests/isolation/` 现有 4 个 `RunSandbox.create()` 测试改为经组合根或保留 create() 快捷方式,全绿。
3. `DockerProvisioner` 实现,真实调用 aiodocker:container create + workspace bind mount + 资源限额 + destroy。
4. `K8sProvisioner` 占位 `NotImplementedError("...lands in Phase 10")`,async def。
5. `runtime/build_sandbox.py` 组合根:读 `config.yaml.isolation.mode` → 选 provisioner → 返回 provisioned RunSandbox。
6. `CodeExecServer` 在 `mode="docker"` 时经 provisioned container 执行代码,返回 `{stdout, stderr, returncode}`;LOCAL/NONE 行为不变。
7. 新增 `SandboxError(HanflowError)` + 至少 4 个稳定 code;`retryable` 标志合理(timeout retryable,dep_missing 非 retryable)。
8. fake provisioner 覆盖全链路单测;`DockerProvisioner` 契约测试用 `skipif` 守护无 daemon 时跳过。
9. `pyproject.toml` 新增 `docker` optional-extra;`DockerProvisioner` lazy import,无 extra 时抛 `SANDBOX_DEP_MISSING`。
10. `config.yaml` 新增 `isolation` 段(默认 mode=local,向后兼容)。
11. `make ci` 全绿(ruff + mypy --strict + pytest),DOCKER 契约测试在无 daemon 环境 skip 不报错。
12. **`charter-check --diff` 在 P9 全绿**(本 cycle 改动全部合规)。
