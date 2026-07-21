# Design: DOCKER Sandbox 隔离(生产安全边界)

- cycle_id: 2026-W30-1.1.1
- target_version: 1.2.0
- 日期: 2026-07-21
- direction: `cycles/2026-W30-1.1.1/direction.md`(Gate 1 已确认)
- P3b AUDIT 结论: 通过(2 严重已清零 / 0 轻微剩余),无需 ADR(类型上移属于 §3 依赖矩阵内合规重构,不改公开 API;`SandboxMode` 仍是同一个 StrEnum,isolation re-export 维持向后兼容)

> **术语约定**:本 cycle(2026-W30-1.1.1) 即源码 docstring 中的 "Phase 8"(DOCKER sandbox 落地);K8S provisioning 是 "Phase 10"(未来 cycle)。Phase 编号是 hanflow 演进路线的历史标识,cycle_id 是 LOOP 系统的版本标识,两者关系:`Phase 8 == 2026-W30-1.1.1`、`Phase 10 == <未来 K8S cycle>`。

> 本设计采纳 P3b 审计的两条严重修订建议(类型上移 + dedicated_sandbox 澄清),并清理探查阶段发现的 3 处额外技术债(`CodeExecServer.mode` 词表不一致 / `enforce_tool_whitelist` 滥用基类错误 / `spawn_agent` 忽略 span_id)。

---

## 架构定位

本改动落 **L0 core 层**(契约 + 类型上移)+ **L4 isolation 层**(LocalProvisioner / DockerProvisioner / K8sProvisioner)+ **L4 runtime 层**(组合根 `build_sandbox`),是 direction 路径 A(Provisioner Protocol + 类型上移 + 组合根注入)的落地。

遵循 CHARTER §3 依赖倒置:`SandboxProvisioner` Protocol + `SandboxMode/SandboxResources/RunSandbox/ProvisionedSandbox` 全部在 core 内自洽引用(L0),isolation 改为 L4→L0 复用 + re-export(向后兼容),组合根 `runtime/build_sandbox.py` 注入具体 provisioner。**无 core→isolation 反向依赖**(矩阵 core 行 × isolation 列保持 ✗)。

**与现有 `RunSandbox.create()` 对称**:保留 `create()` 作 LOCAL/NONE 向后兼容快捷方式;新 DOCKER 路径经组合根 + provisioner,不污染 LOCAL/NONE 调用点(4 处测试 + `sdk.py:130-134`)。

**LL4 调用链(运行时视角)**:

```
sdk.py:Hanflow.run()
   └─> _ensure_components()                         # 已有组合点 (sdk.py:290-371)
         └─> [新] build_sandbox(config, ws_mgr)     # 组合根 (runtime/build_sandbox.py)
               └─> provisioner = _select_provisioner(config.mode)
               └─> provisioned = await provisioner.provision(run_sandbox)
                     ├─ LocalProvisioner   → ProvisionedSandbox(host exec)
                     ├─ DockerProvisioner  → ProvisionedSandbox(real container)
                     └─ K8sProvisioner     → NotImplementedError(Phase 10)
         └─> ctx = RuntimeContextImpl(..., sandbox=run_sandbox, provisioned=provisioned)
```

---

## 组件分解

### 1. 类型上移 + 新增契约(落 `core/sandbox_contract.py`,新文件)

把以下三个**纯 Pydantic 数据模型(无 IO)** 从 `isolation/sandbox.py:32-80` **上移到** `core/sandbox_contract.py`:

- `SandboxMode(StrEnum)` — `LOCAL/DOCKER/K8S/NONE` 四档(值不变,探查证实 `sandbox.py:32-36`)
- `SandboxResources(BaseModel)` — 5 字段不变(`cpu_limit/memory_limit_mb/timeout_seconds/disk_limit_mb/network_egress`,探查证实 `sandbox.py:39-44`)
- `RunSandbox(BaseModel)` — 6 字段不变(`run_id/mode/workspace_root/container_id/resources/bash_enabled`),`create()` 类方法**保留**(LOCAL/NONE 快捷方式,见迁移兼容章)

新增 Protocol + ProvisionedSandbox:

```python
# hanflow/core/sandbox_contract.py
from __future__ import annotations
from enum import StrEnum
from pathlib import Path
from typing import Any, Protocol, runtime_checkable
from pydantic import BaseModel, ConfigDict


class SandboxMode(StrEnum):
    LOCAL = "local"
    DOCKER = "docker"
    K8S = "k8s"
    NONE = "none"


class SandboxResources(BaseModel):
    cpu_limit: str = "2.0"                      # 映射 docker --cpus
    memory_limit_mb: int = 2048                 # 映射 docker --memory
    timeout_seconds: int = 3600                 # container 存活上限
    disk_limit_mb: int = 5120                   # 映射 docker --storage-opt size (overlay2)
    network_egress: list[str] | None = None     # None=禁网(--network=none); 非空=允许 host(本 cycle 不做 ACL)


class RunSandbox(BaseModel):
    """Per-run sandbox(纯数据模型, §2.5 per-run 不变量)。"""
    run_id: str
    mode: SandboxMode
    workspace_root: Path
    container_id: str | None = None
    resources: SandboxResources = SandboxResources()
    bash_enabled: bool = False
    model_config = ConfigDict(arbitrary_types_allowed=True)

    @classmethod
    def create(
        cls,
        run_id: str,
        mode: SandboxMode,
        workspace_mgr: Any,
        resources: SandboxResources | None = None,
    ) -> RunSandbox:
        """LOCAL/NONE 向后兼容快捷方式 (deprecated for DOCKER/K8S)。

        DOCKER/K8S 档请走 runtime.build_sandbox(), 由组合根注入 provisioner。
        此处保留仅为不破坏现有 5 处调用点 (tests/isolation × 4 + tests/conftest.py:118 + sdk.py:130)。
        """
        ws = workspace_mgr.workspace_for(run_id)
        return cls(
            run_id=run_id,
            mode=mode,
            workspace_root=ws,
            resources=resources or SandboxResources(),
            bash_enabled=False,  # LOCAL 默认禁 bash
        )
```

新增 Protocol + ProvisionedSandbox(**定义顺序: ExecInterface → ProvisionedSandbox → SandboxProvisioner,消除前向引用**):

```python
# 顺序约定(与 core/context.py 的 "Protocol 在前, 实现在后" 惯例一致)

class ExecInterface(Protocol):
    """容器/进程内执行代码的后端无关接口(供 code_exec 等工具复用)。

    返回与现有 _exec_local() 同构的 dict, 保证 call site 同构。
    timeout 超时由实现内部包成 SandboxTimeoutError 抛出(见错误处理章)。
    """
    async def run(
        self,
        *,
        command: list[str],
        stdin: str | None = None,
        timeout: int = 30,
        cwd: str | None = None,
    ) -> dict[str, Any]:
        """返回 {"stdout": str, "stderr": str, "returncode": int}。
        超时抛 SandboxTimeoutError; 其它失败抛 SandboxError 子类。"""
        ...


class ProvisionedSandbox(BaseModel):
    """provision 的产物: 容器/进程句柄 + 执行接口。

    exec_interface 是后端无关的执行抽象(见上文 ExecInterface Protocol);
    LocalProvisioner 用 host subprocess 实现, DockerProvisioner 用 docker exec。
    """
    run_id: str
    mode: SandboxMode
    container_id: str | None = None      # LOCAL/NONE 为 None; DOCKER/K8S 必填
    exec_interface: ExecInterface        # 引用已定义的 ExecInterface(无前向引用)
    workspace_root: Path                 # bind mount 或 host 路径; DOCKER 档为容器内视角(如 /workspace)
    model_config = ConfigDict(arbitrary_types_allowed=True)


@runtime_checkable
class SandboxProvisioner(Protocol):
    """L0 契约:把 RunSandbox(数据) provision 成可执行的 ProvisionedSandbox。

    实现在 L4 isolation/(Local/Docker/K8s), 组合根 runtime/build_sandbox.py 注入。
    §2.5 per-run 不变量: provision 只接受 run 级 RunSandbox, 不接受 per-agent spec。
    """
    name: str

    async def provision(self, run_sandbox: RunSandbox) -> ProvisionedSandbox: ...  # 引用已定义

    async def destroy(self, provisioned: ProvisionedSandbox) -> None: ...
```

**设计决策**:
- **为什么 Protocol 落 core 而非 isolation**:依赖倒置。Protocol 在 core 让组合根 + isolation 实现都依赖契约(L0),无 core→isolation 反向 import;同时 `RuntimeContextImpl` 可经 Protocol 引用 provisioned sandbox 而无需 import 具体类。
- **类型定义顺序(审计清理 #4)**:`ExecInterface` → `ProvisionedSandbox` → `SandboxProvisioner`,与 `core/context.py`(Protocol 在前,实现在后)惯例对齐,消除前向引用歧义。
- **为什么 `ProvisionedSandbox` 用 Pydantic 而非 dataclass**:CHARTER §2.3(配置/数据模型走 BaseModel);与现有 `RunSandbox/SandboxResources` 一致。
- **`ExecInterface` 抽象的代价**:多一层 Protocol,但收益是 code_exec / shell / 未来 firecracker 都能复用同一执行接口,避免每个工具各写一套 docker exec 调用。
- **`network_egress` 语义简化**:本 cycle 只做 `None`(默认,`--network=none` 完全禁网)与 `["*"]`(显式 opt-in `--network=host`);细粒度 ACL 引擎明确排除(非目标)。`list[str]` 字段保留是为未来扩展,本 cycle 实现只检查"是否为 None"。

### 2. `LocalProvisioner`(新,落 `isolation/local_provisioner.py`)

```python
# hanflow/isolation/local_provisioner.py
from __future__ import annotations
import asyncio
from pathlib import Path
from typing import Any
from hanflow.core.errors import SandboxTimeoutError
from hanflow.core.sandbox_contract import (
    ExecInterface, ProvisionedSandbox, RunSandbox, SandboxMode,
)


class _LocalExec(ExecInterface):
    """host subprocess 执行(包装现有 _exec_local 行为)。"""

    def __init__(self, workspace_root: Path, run_id: str) -> None:
        self._ws = workspace_root
        self._run_id = run_id

    async def run(self, *, command, stdin=None, timeout=30, cwd=None) -> dict[str, Any]:
        proc = await asyncio.create_subprocess_exec(
            *command,
            cwd=cwd or str(self._ws),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            stdin=asyncio.subprocess.PIPE if stdin else None,
        )
        try:
            data = await asyncio.wait_for(
                proc.communicate(stdin.encode() if stdin else None),
                timeout=timeout,
            )
        except TimeoutError:
            proc.kill()
            raise SandboxTimeoutError(   # 内部就包, 不让 TimeoutError 漏给调用方
                f"local exec timed out after {timeout}s",
                run_id=self._run_id,
                details={"command": command, "timeout": timeout},
            ) from None
        stdout, stderr = data
        return {
            "stdout": stdout.decode(errors="replace"),
            "stderr": stderr.decode(errors="replace"),
            "returncode": proc.returncode or 0,
        }


class LocalProvisioner:
    """host 执行 provisioner(LOCAL 档)。无容器,返回 host subprocess exec。"""
    name = "local"

    async def provision(self, run_sandbox: RunSandbox) -> ProvisionedSandbox:
        if run_sandbox.mode != SandboxMode.LOCAL:
            raise ValueError(f"LocalProvisioner got mode={run_sandbox.mode}")
        return ProvisionedSandbox(
            run_id=run_sandbox.run_id,
            mode=SandboxMode.LOCAL,
            container_id=None,
            exec_interface=_LocalExec(run_sandbox.workspace_root, run_sandbox.run_id),
            workspace_root=run_sandbox.workspace_root,
        )

    async def destroy(self, provisioned: ProvisionedSandbox) -> None:
        pass  # LOCAL 无资源回收
```

### 3. `DockerProvisioner`(新,落 `isolation/docker_provisioner.py`)

```python
# hanflow/isolation/docker_provisioner.py
from __future__ import annotations
from pathlib import Path
from typing import Any
from hanflow.core.errors import (
    SandboxDependencyMissingError, SandboxDestroyFailedError,
    SandboxProvisionFailedError, SandboxTimeoutError,
)
from hanflow.core.sandbox_contract import (
    ExecInterface, ProvisionedSandbox, RunSandbox, SandboxMode, SandboxResources,
)


class _DockerExec(ExecInterface):
    """docker exec 执行接口。container 已由 provision 创建。"""
    def __init__(self, container_id: str, workspace_in_container: str, run_id: str) -> None:
        self._cid = container_id
        self._ws = workspace_in_container
        self._run_id = run_id

    async def run(self, *, command, stdin=None, timeout=30, cwd=None) -> dict[str, Any]:
        # lazy import: aiodocker 在方法内, 触发 SANDBOX_DEP_MISSING 早
        try:
            from aiodocker import Docker, DockerError
        except ImportError as exc:
            raise SandboxDependencyMissingError(
                "aiodocker not installed; pip install 'hanflow[docker]'",
                run_id=self._run_id,
            ) from exc
        # 组装 docker exec 调用: exec_create + exec_start, 解码 stdout/stderr,
        # 提取 returncode, 用 asyncio.wait_for 守护 timeout → 抛 SandboxTimeoutError
        # (实现细节留 execute 阶段)
        ...


class DockerProvisioner:
    """真实容器 provisioner。资源限额 + workspace bind mount + destroy。"""
    name = "docker"

    def __init__(self, base_image: str = "python:3.11-slim") -> None:
        self._image = base_image

    async def provision(self, run_sandbox: RunSandbox) -> ProvisionedSandbox:
        if run_sandbox.mode != SandboxMode.DOCKER:
            raise ValueError(f"DockerProvisioner got mode={run_sandbox.mode}")
        try:
            from aiodocker import Docker, DockerError  # lazy: 触发 dep_missing 早
        except ImportError as exc:
            raise SandboxDependencyMissingError(
                "aiodocker not installed; pip install 'hanflow[docker]'",
                run_id=run_sandbox.run_id,
            ) from exc

        client = Docker()
        try:
            container = await client.containers.create_or_replace(
                name=f"hanflow-{run_sandbox.run_id}",
                config=self._build_config(run_sandbox),
            )
            await container.start()
            cid = container.id
        except DockerError as exc:
            # 用具体子类(不传 code= kwarg, 见错误处理章)
            raise SandboxProvisionFailedError(
                f"docker provision failed: {exc}",
                run_id=run_sandbox.run_id,
                details={"image": self._image, "docker_error": str(exc)},
            ) from exc
        finally:
            await client.close()

        return ProvisionedSandbox(
            run_id=run_sandbox.run_id,
            mode=SandboxMode.DOCKER,
            container_id=cid,
            exec_interface=_DockerExec(cid, "/workspace", run_sandbox.run_id),
            workspace_root=Path("/workspace"),  # 容器内视角
        )

    def _build_config(self, sb: RunSandbox) -> dict[str, Any]:
        r = sb.resources
        net = "none" if r.network_egress is None else "host"
        return {
            "Image": self._image,
            "Cmd": ["sleep", str(r.timeout_seconds)],   # container 自带存活上限
            "HostConfig": {
                "CpuQuota": int(float(r.cpu_limit) * 100000),
                "Memory": r.memory_limit_mb * 1024 * 1024,
                "NetworkMode": net,
                "Binds": [f"{sb.workspace_root.resolve()}:/workspace:rw"],
                "StorageOpt": {"size": f"{r.disk_limit_mb}m"} if r.disk_limit_mb else None,
            },
            "WorkingDir": "/workspace",
        }

    async def destroy(self, provisioned: ProvisionedSandbox) -> None:
        if provisioned.container_id is None:
            return
        from aiodocker import Docker, DockerError
        client = Docker()
        try:
            c = await client.containers.get(provisioned.container_id)
            await c.kill()
            await c.delete()
        except DockerError as exc:
            raise SandboxDestroyFailedError(   # 具体子类, retryable=True 由类属性定义
                f"docker destroy failed: {exc}",
                run_id=provisioned.run_id,
                details={"container_id": provisioned.container_id},
            ) from exc
        finally:
            await client.close()
```

**实现细节留 execute 阶段**:`_DockerExec.run()` 的 `aiodocker.exec_create/exec_start` 流式读取、`stdin` 编码、`returncode` 提取、`SandboxTimeoutError` 包装——这些是机械工作,本 design 只定形状。

### 4. `K8sProvisioner` 占位(落 `isolation/sandbox.py` 内,不开新文件)

**审计采纳 D 类建议**(避免 YAGNI):不新开 `k8s_provisioner.py` 文件,而是在 `isolation/sandbox.py` 模块底部加一个 stub 类,既满足"K8S 档有显式失败"的契约,又不增噪声文件。

```python
# 追加到 hanflow/isolation/sandbox.py 末尾(已瘦身)
class K8sProvisioner:
    """K8S 档占位。Phase 10 落地(见 §4 编码规范)。"""
    name = "k8s"

    async def provision(self, run_sandbox: RunSandbox) -> ProvisionedSandbox:
        raise NotImplementedError(
            f"K8S sandbox provisioning lands in Phase 10 (got run_id={run_sandbox.run_id})"
        )

    async def destroy(self, provisioned: ProvisionedSandbox) -> None:
        raise NotImplementedError("K8S sandbox destroy lands in Phase 10")
```

### 5. 组合根 `build_sandbox`(新,落 `runtime/build_sandbox.py`)

```python
# hanflow/runtime/build_sandbox.py
from __future__ import annotations
from typing import Any, Protocol
from hanflow.core.errors import SandboxError
from hanflow.core.sandbox_contract import (
    ProvisionedSandbox, RunSandbox, SandboxMode, SandboxProvisioner, SandboxResources,
)
from hanflow.core.errors import SandboxProvisionFailedError


async def build_sandbox(
    *,
    run_id: str,
    mode: SandboxMode,
    workspace_mgr: Any,
    resources: SandboxResources | None = None,
    docker_image: str = "python:3.11-slim",
) -> tuple[RunSandbox, ProvisionedSandbox]:
    """组合根: 按 mode 选 provisioner 并 provision。

    返回 (run_sandbox 纯数据, provisioned_sandbox 可执行句柄)。
    调用方(如 Hanflow._ensure_components) 把两者注入 RuntimeContextImpl。
    """
    sb = RunSandbox.create(run_id=run_id, mode=mode, workspace_mgr=workspace_mgr, resources=resources)

    if mode == SandboxMode.LOCAL:
        from hanflow.isolation.local_provisioner import LocalProvisioner
        provisioner: SandboxProvisioner = LocalProvisioner()
    elif mode == SandboxMode.DOCKER:
        from hanflow.isolation.docker_provisioner import DockerProvisioner
        provisioner = DockerProvisioner(base_image=docker_image)
    elif mode == SandboxMode.K8S:
        from hanflow.isolation.sandbox import K8sProvisioner
        provisioner = K8sProvisioner()
    elif mode == SandboxMode.NONE:
        from hanflow.isolation.local_provisioner import LocalProvisioner
        provisioner = LocalProvisioner()  # NONE 复用 host exec, 但 context isolation 仍在
    else:
        raise SandboxProvisionFailedError(   # 具体子类, 不传 code= kwarg
            f"unsupported sandbox mode: {mode!r}",
            run_id=run_id,
            details={"mode": str(mode)},
        )

    provisioned = await provisioner.provision(sb)
    return sb, provisioned
```

**调用方接入**(改 `sdk.py:130-134`):

```python
# hanflow/sdk.py (现有 _ensure_components 或 run 方法中)
from hanflow.core.sandbox_contract import SandboxMode
from hanflow.runtime.build_sandbox import build_sandbox

# 替代原 sandbox = RunSandbox.create(mode=SandboxMode.LOCAL, ...)
mode = SandboxMode(self._config.get("isolation", {}).get("mode", "local"))
self._sandbox, self._provisioned = await build_sandbox(
    run_id=run_id, mode=mode, workspace_mgr=self._workspace_mgr,
    docker_image=self._config.get("isolation", {}).get("docker", {}).get("base_image", "python:3.11-slim"),
)
# 后续 ctx 注入 self._sandbox + self._provisioned
```

### 6. `RuntimeContextImpl` 接入 provisioned(改 `orchestration/context_impl.py`)

```python
# hanflow/orchestration/context_impl.py
class RuntimeContextImpl:
    def __init__(
        self,
        state, router, bus, memory, skills, retrieval, trace, workspace_mgr,
        sandbox: RunSandbox,
        provisioned: ProvisionedSandbox | None = None,   # 新增, 可选(向后兼容)
        named_models=None, run_handle_queue=None,
    ) -> None:
        ...
        self._sandbox = sandbox
        self._provisioned = provisioned   # 新增持有

    def provisioned(self) -> ProvisionedSandbox | None:
        """供 code_exec 等工具按需取执行接口。"""
        return self._provisioned
```

**为什么不在 RuntimeContext Protocol 上加 provisioned()**:Protocol 是 nodes 的标准接口,nodes 不应直接碰 sandbox(经 ctx.tool_call 走工具);provisioned 只对 builtin 工具(code_exec/shell)有意义,经组合根在工具构造时注入更干净。

### 7. `code_exec` DOCKER 路径 + mode 词表对齐(改 `tools/builtin/code_exec.py`)

```python
# hanflow/tools/builtin/code_exec.py
from hanflow.core.sandbox_contract import ExecInterface, SandboxMode

class CodeExecServer(BuiltinMCPServer):
    name = "code_exec"

    def __init__(
        self,
        workspace: str | Path,
        mode: str = "none",
        exec_interface: ExecInterface | None = None,   # 新增: provisioner 注入
    ) -> None:
        self.workspace = Path(workspace)
        # mode 词表对齐 SandboxMode(none→NONE, docker→DOCKER, local→LOCAL)
        # 但接受字符串以保持向后兼容(现有调用点传 "none"/"docker")
        self.mode = mode
        self._exec = exec_interface

    async def call(self, tool: str, args: dict[str, Any]) -> Any:
        if tool != "run":
            raise HanflowError(f"unknown code_exec tool: {tool!r}")
        if args["language"] != "python":
            raise HanflowError(f"unsupported language: {args['language']!r}")
        timeout = args.get("timeout", 30)
        code = args["code"]

        if self._exec is not None:
            # 新路径: provisioner 注入的 ExecInterface(覆盖所有 mode)
            snippet = self.workspace / "snippet.py"
            snippet.write_text(code, encoding="utf-8")
            return await self._exec.run(
                command=[sys.executable if self.mode == "none" else "python3", str(snippet)],
                timeout=timeout,
            )

        if self.mode == "none":
            return await self._exec_local(code, timeout)
        # docker / firecracker / k8s 经 provisioner 注入才可达; 否则显式失败
        raise HanflowError(
            f"code_exec mode {self.mode!r} requires a provisioned sandbox "
            f"(Phase 8 DOCKER landed in cycle 2026-W30-1.1.1; wire via build_sandbox)",
        )
```

**词表对齐决策**:`CodeExecServer.mode` 保持字符串(向后兼容),但运行时按 `SandboxMode` 语义判断。新调用点优先传 `exec_interface`(由组合根根据 `config.isolation.mode` 注入),旧调用点(只传 mode 字符串)走 fallback。

### 8. `isolation/sandbox.py` 瘦身 + re-export

```python
# hanflow/isolation/sandbox.py (瘦身后)
"""Sub-agent isolation — DeerFlow-style (§13.6).

类型(SandboxMode/SandboxResources/RunSandbox) 已上移到 core/sandbox_contract.py,
此处 re-export 保持向后兼容。
"""
from __future__ import annotations
import uuid
from pathlib import Path
from typing import Any
from pydantic import BaseModel
from hanflow.core.context import FakeContext
from hanflow.core.errors import (
    HanflowError, SandboxError, SandboxProvisionFailedError, ToolWhitelistError,
)
from hanflow.core.sandbox_contract import (
    ProvisionedSandbox, RunSandbox, SandboxMode, SandboxResources,
    SandboxProvisioner,  # re-export
)
from hanflow.observability.trace import TraceExporter

# re-export (向后兼容: 任何 from hanflow.isolation.sandbox import RunSandbox 仍可用)
__all__ = [
    "SandboxMode", "SandboxResources", "RunSandbox", "SubAgentIsolation",
    "AgentSpec", "spawn_agent", "enforce_tool_whitelist", "SandboxProvisioner",
    "ProvisionedSandbox", "K8sProvisioner",
]


class SubAgentIsolation(BaseModel): ...   # 不变
class AgentSpec(BaseModel): ...           # 不变


async def spawn_agent(
    *,
    parent: Any,
    spec: AgentSpec,
    run_sandbox: RunSandbox,
    trace: TraceExporter,
    provisioned: ProvisionedSandbox | None = None,   # 新增: 可选注入
) -> Any:
    """§13.6 单一入口。所有子 agent 共享 run sandbox(per-run 不变量 §2.5)。

    dedicated_sandbox=True 与 False 都**复用 run container + 容器内 subdir**,
    不 provision per-agent 容器(见 direction 非目标 #3 + 目标 #7)。
    """
    async with trace.span(
        "agent.spawn", kind="workflow", sub_agent=spec.sub_agent, role=spec.role,
    ) as sp:  # 现在用上 span (审计清理 #3)
        parent_state = parent.state
        child_state = parent_state.model_copy(update={
            "messages": [], "node_states": [], "memory_ops": [], "pending_hitl": None,
        })

        subdir_name = f"agent-{uuid.uuid4().hex[:8]}"

        # 关键(round 1 修订): DOCKER 档下所有子 agent(dedicated 与否)的 subdir
        # 都落 provisioned.workspace_root(容器内视角, 经 bind mount 映射)。
        # 若落 run_sandbox.workspace_root(host 路径), 容器内只 bind 了 /workspace,
        # 子 agent 写到 host 路径容器内看不到 → 数据流断裂。
        if provisioned is not None and provisioned.mode == SandboxMode.DOCKER:
            # §2.5: 复用 run container, 只多一个容器内 subdir(dedicated 与否一致)
            subdir = str(provisioned.workspace_root / subdir_name)
            try:
                await provisioned.exec_interface.run(
                    command=["mkdir", "-p", subdir], timeout=5,
                )
            except SandboxError:
                # 专用子类(SandboxTimeoutError 等)透传, 保留 code + retryable(§5 禁止吞)
                raise
            except Exception as exc:
                # 非 Sandbox 异常才包成 provision_failed(避免吞专用子类)
                raise SandboxProvisionFailedError(
                    f"failed to allocate subdir in container: {exc}",
                    run_id=run_sandbox.run_id,
                    details={"subdir": subdir},
                ) from exc
        else:
            # LOCAL/NONE: 落 host workspace_root
            subdir = str(run_sandbox.workspace_root / subdir_name)
            Path(subdir).mkdir(parents=True, exist_ok=True)
        spec.workspace_subdir = subdir

        child = FakeContext(state=child_state)
        child._tool_whitelist = spec.tools_whitelist  # type: ignore[attr-defined]
        await trace.event("agent.spawned", sub_agent=spec.sub_agent, span_id=sp.span_id)
        return child


def enforce_tool_whitelist(tool_name: str, whitelist: list[str] | None) -> None:
    """Raise if a tool call is outside the whitelist."""
    if whitelist is None:
        return
    if tool_name not in whitelist:
        raise ToolWhitelistError(   # 审计清理 #2: 专用子类替代基类
            f"tool {tool_name!r} not in sub-agent whitelist",
            details={"whitelist": whitelist},
        )


class K8sProvisioner: ...   # 见组件 #4, 占位
```

---

## 接口契约

| 接口 | 签名 | 落点 | 调用方 |
|---|---|---|---|
| `SandboxMode` | `StrEnum: LOCAL/DOCKER/K8S/NONE` | `core/sandbox_contract.py` | 全栈(原 isolation) |
| `SandboxResources` | `BaseModel(5 字段)` | `core/sandbox_contract.py` | 全栈 |
| `RunSandbox` | `BaseModel(6 字段) + create()` | `core/sandbox_contract.py` | spawn_agent, build_sandbox, tests |
| `SandboxProvisioner` | `Protocol: provision/destroy` | `core/sandbox_contract.py` | build_sandbox |
| `ProvisionedSandbox` | `BaseModel(container_id/exec_interface/workspace_root)` | `core/sandbox_contract.py` | build_sandbox, ctx, code_exec |
| `ExecInterface` | `Protocol: run()` | `core/sandbox_contract.py` | code_exec, 未来 shell |
| `LocalProvisioner` | impl of `SandboxProvisioner` | `isolation/local_provisioner.py` | build_sandbox |
| `DockerProvisioner` | impl of `SandboxProvisioner` | `isolation/docker_provisioner.py` | build_sandbox |
| `K8sProvisioner` | impl of `SandboxProvisioner`(stub) | `isolation/sandbox.py` | build_sandbox |
| `build_sandbox()` | async fn | `runtime/build_sandbox.py` | sdk.py |
| `SandboxError` | `HanflowError` subclass | `core/errors.py` | DockerProvisioner 等 |
| `SandboxTimeoutError` | `SandboxError` subclass | `core/errors.py` | ExecInterface.run 包装 |
| `ToolWhitelistError` | `HanflowError` subclass | `core/errors.py` | enforce_tool_whitelist |

---

## 数据流

### DOCKER 全链路(code_exec 工具为例)

```
1. Hanflow.run() 调 _ensure_components
2. build_sandbox(mode=DOCKER, ws_mgr)
   ├─ RunSandbox.create() → 纯数据 sb (workspace_root = <scratch>/<run_id>/workspace)
   └─ DockerProvisioner.provision(sb)
        ├─ aiodocker.Docker().containers.create_or_replace(config)
        │    config.HostConfig:
        │      CpuQuota = 200000 (2.0 cpu)
        │      Memory  = 2147483648 (2048 MB)
        │      NetworkMode = "none" (network_egress is None)
        │      Binds = ["<host_ws>:/workspace:rw"]
        │      StorageOpt = {"size": "5120m"}
        ├─ container.start()
        └─ 返回 ProvisionedSandbox(container_id=cid, exec_interface=_DockerExec, workspace_root=Path("/workspace"))
3. RuntimeContextImpl(sandbox=sb, provisioned=provisioned, ...)
4. node 调 ctx.tool_call("code_exec.run", {"language":"python", "code":"print(1)"})
5. MCPBus 分派到 CodeExecServer.call
   ├─ snippet = workspace / "snippet.py"; write_text(code)
   ├─ self._exec.run(command=["python3", "/workspace/snippet.py"], timeout=30)
   │    ↓ _DockerExec.run
   │    aiodocker.exec_create(cid, cmd=["python3", "/workspace/snippet.py"])
   │    aiodocker.exec_start(...) → 流式 stdout/stderr
   │    asyncio.wait_for(..., timeout=30) 守护
   └─ 返回 {"stdout":"1\n", "stderr":"", "returncode":0}
6. run 结束: DockerProvisioner.destroy(provisioned) → container.kill() + delete()
```

### LOCAL 对照(向后兼容)

```
1. Hanflow.run() 调 _ensure_components
2. build_sandbox(mode=LOCAL, ws_mgr)
   ├─ RunSandbox.create() → sb (同前)
   └─ LocalProvisioner.provision(sb)
        └─ 返回 ProvisionedSandbox(container_id=None, exec_interface=_LocalExec, workspace_root=sb.workspace_root)
3-5. 同上, 但 _LocalExec.run 用 asyncio.create_subprocess_exec(sys.executable, ...)
6. LocalProvisioner.destroy() → no-op
```

---

## 错误处理 / HanflowError

新增 6 个错误子类(落 `core/errors.py`,**严格遵循现有 15 个子类的模式:`code` 与 `retryable` 是类属性,通过子类覆盖,不在 `__init__` 传 kwarg**):

```python
# hanflow/core/errors.py (追加)
class SandboxError(HanflowError):
    """Sandbox provisioning/destroy/exec 失败的基类。"""
    code = "SANDBOX_ERROR"


class SandboxProvisionFailedError(SandboxError):
    code = "SANDBOX_PROVISION_FAILED"   # 容器创建/启动失败 / 不支持的 mode (非 retryable)


class SandboxDestroyFailedError(SandboxError):
    code = "SANDBOX_DESTROY_FAILED"     # 容器销毁失败 (retryable, container 可能 leak)
    retryable = True


class SandboxTimeoutError(SandboxError):
    code = "SANDBOX_TIMEOUT"            # exec 或 provision 超时 (retryable)
    retryable = True


class SandboxDependencyMissingError(SandboxError):
    code = "SANDBOX_DEP_MISSING"        # aiodocker 未安装 (非 retryable, 需 pip install)


class ToolWhitelistError(HanflowError):
    """工具不在白名单(顺手清理: 原 enforce_tool_whitelist 滥用基类 HanflowError)。"""
    code = "TOOL_WHITELIST"
```

**实例化模式(关键,审计 round 1 修订)**:`HanflowError.__init__(self, message="", *, run_id=None, node_id=None, span_id=None, details=None)` **不接受 `code=` kwarg**——`code` 是类属性,通过子类覆盖。所有抛错必须用**具体子类**,不传 `code=`:

```python
# ✗ 错误(round 1 bug, 已修)
raise SandboxError("...", code="SANDBOX_PROVISION_FAILED", run_id=rid)  # TypeError

# ✓ 正确(round 2)
raise SandboxProvisionFailedError("...", run_id=rid, details={...})     # code 来自类属性
```

**错误映射**:

| 场景 | 异常 | retryable | 谁抛 |
|---|---|---|---|
| `aiodocker` 未装 | `SandboxDependencyMissingError` | False | `DockerProvisioner.provision` 顶部 + `_DockerExec.run` 顶部 lazy import |
| container create/start 失败 | `SandboxProvisionFailedError` | False | `DockerProvisioner.provision` |
| 不支持的 sandbox mode | `SandboxProvisionFailedError` | False | `build_sandbox` |
| exec 或 container 超时 | `SandboxTimeoutError` | True | `_LocalExec.run` / `_DockerExec.run`(**内部包**,不让 TimeoutError 漏给调用方) |
| container kill/delete 失败 | `SandboxDestroyFailedError` | True | `DockerProvisioner.destroy` |
| 工具不在白名单 | `ToolWhitelistError` | False | `enforce_tool_whitelist` |

**atoms 永不吞异常**(§2.1):所有 SandboxError 由 orchestration 包装层(`RuntimeContextImpl.tool_call`)捕获,记录 `NodeState.error` + trace error span,再按 `on_error` 策略推进。

**§5 禁止吞异常(round 1 修订)**:`spawn_agent` 与 provisioner 的 `except` 块**禁止用基类 `HanflowError` 重抛**——专用子类(`SandboxTimeoutError` 等)的 `code`/`retryable` 必须保留。正确写法:`except SandboxError: raise`(透传专用子类)+ `except Exception as exc: raise SandboxProvisionFailedError(...) from exc`(只包非 Sandbox 异常)。

**lazy import 早期失败原则**:`from aiodocker import Docker` 在 `DockerProvisioner.provision` / `_DockerExec.run` 方法内顶部而非模块顶部,让 `ImportError` 立即包成 `SandboxDependencyMissingError`,而非模块加载失败。

---

## 测试策略

### 测试金字塔

1. **fake provisioner 全链路单测**(默认 CI 跑,无外部依赖)
   - `_FakeProvisioner` 实现 `SandboxProvisioner`,记录 provision/destroy 调用,返回 `_FakeExec`(in-process exec,直接 `exec(code)`,不调系统 python)。
   - 覆盖:`build_sandbox(mode=LOCAL/DOCKER/NONE)`、`build_sandbox` 选 provisioner 分派、`DockerProvisioner` 的 `_build_config` 资源映射逻辑(用 fake `aiodocker` client 验证 config dict)、`code_exec` 经 exec_interface 执行。

2. **LocalProvisioner 真实测试**(本机跑,无需 docker daemon)
   - 覆盖:`LocalProvisioner.provision/destroy`、`_LocalExec.run` 真起 host subprocess(`python -c "print(1)"`)、timeout 抛 `SandboxTimeoutError`。

3. **DockerProvisioner 契约测试**(`pytest.mark.skipif(no docker daemon)`)
   - 守护:`@pytest.mark.skipif(not _docker_available(), reason="no docker daemon")`
   - `_docker_available()` 用 `shutil.which("docker")` + `docker info` 探测。
   - 覆盖:`DockerProvisioner.provision` 真起 `python:3.11-slim` container、资源限额生效(`docker inspect` 验证 `CpuQuota/Memory`)、workspace bind mount 可读写、`destroy` 后 container 消失。

4. **类型上移 + re-export 回归**
   - `from hanflow.isolation.sandbox import RunSandbox, SandboxMode` → 与 `from hanflow.core.sandbox_contract import RunSandbox` 是同一个类(`assert X is Y`)。
   - 现有 `tests/isolation/test_sandbox.py` 4 个 `RunSandbox.create()` 调用点**不改**,全绿(向后兼容验证)。

5. **charter-check 守护**
   - `core/sandbox_contract.py` 不 import `hanflow.isolation.*`(无 core→isolation 反向 import)。
   - `isolation/sandbox.py` 改为 `from hanflow.core.sandbox_contract import ...`(L4→L0 合规)。
   - `runtime/build_sandbox.py` 经组合根 import isolation(L4→L4 合规)。

6. **charter-check 矩阵新增条目**(若需)
   - `isolation → core` ✓(已有,合规)
   - `runtime → isolation` ✓(已有,合规)
   - **不新增** core→isolation(被守护脚本禁止)

7. **dedicated_sandbox 契约单测(direction 验收 #8 落实)**
   - `_FakeProvisioner` 记录 `provision()` 调用次数与参数。
   - `spawn_agent(spec.dedicated_sandbox=True, provisioned=<fake>)` 后断言:
     - `provisioner.provision.call_count == 0`(dedicated 不新 provision 容器,只复用 run container)
     - subdir 落在 `provisioned.workspace_root / "agent-xxx"` 下(容器内视角)
   - `spawn_agent(spec.dedicated_sandbox=False, provisioned=<fake>)` 后断言:
     - `provisioner.provision.call_count == 0`(同样不新 provision)
     - subdir 仍落 `provisioned.workspace_root / "agent-xxx"`(与 dedicated 一致,数据流不断裂)
   - 双向验证 dedicated=True/False 在 DOCKER 档下**共享同一个 run container**,差异只在 subdir 名字不同。

### 测试目录结构

```
tests/
├── core/
│   └── test_sandbox_contract.py      # 新: Protocol + ProvisionedSandbox 字段
├── isolation/
│   ├── conftest.py                   # 加 _FakeProvisioner / _FakeExec fixtures
│   ├── test_sandbox.py               # 现有(不改)
│   ├── test_local_provisioner.py     # 新
│   ├── test_docker_provisioner.py    # 新(skipif 守护)
│   └── test_build_sandbox.py         # 新(组合根分派)
└── tools/
    └── test_code_exec.py             # 新或改: docker 路径 + mode 词表
```

---

## 前端影响

**无前端改动**。本 cycle 只动 SDK + core + isolation + tools,API/CLI 暴露 sandbox 配置明确排除(非目标 #6)。`web/` 与 `hanflow-site/` 不受影响。

**CLI/API 影响证据(审计 round 1 采纳)**:经源码 grep 核实,`hanflow/cli/` 与 `hanflow/api/` 当前**不 import `SandboxMode` 或 `RunSandbox`**(生产路径只有 `sdk.py:130-134` 用 `RunSandbox.create`),本 cycle 对 CLI/API 无破坏。CLI/API 暴露 sandbox 配置是下个 cycle 的主题(非目标 #6)。

`config.yaml` 新增 `isolation` 段是配置而非前端:

```yaml
# config.yaml(hanflow-evolve 内的参考配置, 实际 hanflow 用 SDK 构造时传 config)
isolation:
  mode: local                        # local | docker | k8s | none (默认 local, 向后兼容)
  docker:
    base_image: "python:3.11-slim"
    pull_policy: "if_not_present"    # future; 本 cycle 不实现 pull 逻辑, 用本地已有 image
```

---

## 迁移兼容

### 调用点迁移矩阵

| 调用点 | 现状 | 迁移后 | 破坏性 |
|---|---|---|---|
| `tests/isolation/test_sandbox.py:39,46,65,98` (`RunSandbox.create` × 4) | LOCAL/NONE | **不改** | 无 |
| `tests/conftest.py:118` (`RunSandbox.create`) | LOCAL | **不改** | 无 |
| `sdk.py:130-134` (`RunSandbox.create(mode=LOCAL)`) | 硬编码 LOCAL | 改为 `build_sandbox(mode=config.isolation.mode)` | 无(默认 mode=local) |
| `from hanflow.isolation.sandbox import RunSandbox` (任何外部) | 直接 import | **re-export 保持** | 无 |
| `from hanflow.isolation.sandbox import SandboxMode` | 同上 | **re-export 保持** | 无 |
| `CodeExecServer.__init__(workspace, mode="none")` | mode 字符串 | **签名不变**, 新增可选 `exec_interface=None` | 无 |
| `RuntimeContextImpl.__init__(..., sandbox)` | 持 RunSandbox | 新增可选 `provisioned=None` | 无 |
| `spawn_agent(...)` | 无 provisioned 形参 | 新增可选 `provisioned=None` | 无 |

### 版本号

- `current_version: 1.1.0` → `target_version: 1.2.0`(minor bump,新增 DOCKER 能力 + 新 public-ish API `build_sandbox`,但向后兼容)
- conventional commits:`feat(isolation): DOCKER sandbox provisioner` → minor

### 配置向后兼容

- `config.yaml` 无 `isolation` 段时,默认 `mode=local`(sdk.py fallback),所有现有行为不变。
- 现有 `RunSandbox.create()` 调用点全保留(LOCAL/NONE 快捷方式)。

---

## 风险残留

- **DOCKER daemon 可用性**:`DockerProvisioner` 契约测试用 `skipif` 守护,无 daemon 时跳过(不阻塞 CI)。生产部署文档需说明"DOCKER 档需 docker daemon + aiodocker extra"。
- **aiodocker 异步 API 边界**:execute 阶段需仔细处理 `exec_start` 的流式 stdout/stderr 与 `wait_for` timeout 的协作——design 只定形状,实现细节留给 TDD。
- **Windows 路径**:DOCKER 路径**只 Linux 验证**;Windows 开发机走 fake provisioner + LOCAL(direction 已声明)。
- **`SandboxResources.network_egress` 未来扩展**:本 cycle 只识别 None vs 非 None;list 内的具体 host 留给未来 ACL engine(非目标 #7)。docstring 标注。

---

## 验收标准(design 层面)

承接 direction.md 的 14 条验收,design 层面增量:

1. `core/sandbox_contract.py` 定义全部类型 + Protocol + ProvisionedSandbox + ExecInterface,`isolation/sandbox.py` 仅 re-export + 子类逻辑(`SubAgentIsolation/AgentSpec/spawn_agent/enforce_tool_whitelist/K8sProvisioner`)。
2. **charter-check layering**: `grep "from hanflow.isolation" hanflow/core/sandbox_contract.py` 返回空(无反向 import)。
3. **`RuntimeContext` Protocol 不加 `provisioned()`**(避免污染 nodes 接口);provisioned 经 `RuntimeContextImpl` 私有持有 + 工具构造时注入。
4. fake provisioner 测试覆盖 build_sandbox 全 4 档分派;LocalProvisioner 真起 subprocess;DockerProvisioner skipif 守护。
5. 现有 `tests/isolation/test_sandbox.py` + `tests/conftest.py` 共 5 处 `RunSandbox.create()` 调用点 0 改动,全绿。
6. `SandboxError` 层级:基类 + 4 子类(provision/destroy/timeout/dep_missing)+ `ToolWhitelistError`,code 全 UPPER_SNAKE_CASE 带 SANDBOX_ 或 TOOL_ 前缀。**所有抛错用具体子类,不传 `code=` kwarg**(`code` 是类属性)。
7. `core/__init__.py.__all__` 追加导出新类型(遵循现有分组注释)。
8. **dedicated_sandbox 契约单测守护(direction 验收 #8 落实)**:`spawn_agent(spec.dedicated_sandbox=True)` 与 `dedicated_sandbox=False` 两种情况,`provisioner.provision` 调用次数都为 0(不新 provision per-agent 容器);DOCKER 档下两种情况 subdir 都落 `provisioned.workspace_root`(容器内视角,数据流不断裂)。
9. **spawn_agent 错误透传**:`spawn_agent` 的 `except` 块对 `SandboxError` 子类直接 `raise`(透传 code/retryable),只对非 Sandbox 异常包成 `SandboxProvisionFailedError`(单测验证 `SandboxTimeoutError` 不被降级成基类)。
