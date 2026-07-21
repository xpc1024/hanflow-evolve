# DOCKER Sandbox Provisioner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 hanflow 的 DOCKER sandbox 档从占位做成真实可用,引入 `SandboxProvisioner` 抽象 + 类型上移到 core + 组合根注入。

**Architecture:** 类型(`SandboxMode/Resources/RunSandbox`)+ Protocol(`SandboxProvisioner/ExecInterface`)+ 数据模型(`ProvisionedSandbox`)落在 `core/sandbox_contract.py`(L0);LocalProvisioner/DockerProvisioner 在 isolation(L4);`build_sandbox` 在 runtime(组合根);无 core→isolation 反向依赖。

**Tech Stack:** Python 3.11+ / Pydantic v2 / asyncio / aiodocker(optional-extra)/ pytest + pytest-asyncio

**Reference docs:**
- direction: `E:/opensource/hanflow-evolve/cycles/2026-W30-1.1.1/direction.md`
- design: `E:/opensource/hanflow-evolve/cycles/2026-W30-1.1.1/design.md`
- CHARTER: `E:/opensource/hanflow-evolve/CHARTER.md`

---

## File Structure

| 文件 | 操作 | 责任 |
|---|---|---|
| `hanflow/core/errors.py` | 修改(追加 6 个子类) | `SandboxError` 基类 + 4 子类 + `ToolWhitelistError` |
| `hanflow/core/__init__.py` | 修改(`__all__` 追加) | 导出新错误子类 + 新 contract 类型 |
| `hanflow/core/sandbox_contract.py` | **创建** | 上移类型 + Protocol + ProvisionedSandbox |
| `hanflow/isolation/sandbox.py` | 修改(瘦身) | re-export + SubAgentIsolation/AgentSpec/spawn_agent/enforce_tool_whitelist/K8sProvisioner |
| `hanflow/isolation/local_provisioner.py` | **创建** | LocalProvisioner + _LocalExec |
| `hanflow/isolation/docker_provisioner.py` | **创建** | DockerProvisioner + _DockerExec |
| `hanflow/runtime/build_sandbox.py` | **创建** | 组合根 |
| `hanflow/orchestration/context_impl.py` | 修改(加 provisioned 字段) | RuntimeContextImpl 持有 provisioned |
| `hanflow/tools/builtin/code_exec.py` | 修改 | DOCKER 路径 + mode 词表对齐 + exec_interface 注入 |
| `hanflow/sdk.py` | 修改(单点) | `Hanflow._ensure_components` 接入 build_sandbox |
| `hanflow/config.py`(若有) | 修改 | 加 isolation 段 schema |
| `pyproject.toml` | 修改 | 新增 docker optional-extra |
| `tests/core/test_sandbox_contract.py` | **创建** | Protocol + 类型字段测试 |
| `tests/core/test_errors.py`(若不存在则创建) | 修改/创建 | 6 个新错误子类 |
| `tests/isolation/test_sandbox.py` | **不改**(回归) | 验证 re-export |
| `tests/isolation/conftest.py` | 修改 | 加 `_FakeProvisioner` / `_FakeExec` fixtures |
| `tests/isolation/test_local_provisioner.py` | **创建** | LocalProvisioner |
| `tests/isolation/test_docker_provisioner.py` | **创建** | DockerProvisioner(skipif 守护) |
| `tests/isolation/test_spawn_agent_dedicated.py` | **创建** | dedicated_sandbox 契约(direction 验收 #8) |
| `tests/isolation/test_build_sandbox.py` | **创建** | 组合根分派 |
| `tests/tools/test_code_exec.py` | 修改/创建 | DOCKER 路径 + mode 词表 |

---

## Task DAG

```
T1 (errors) ──> T2 (core/sandbox_contract) ──> T3 (isolation/sandbox 瘦身) ──┬──> T4 (LocalProvisioner)
                                                                              ├──> T6 (build_sandbox + ctx + sdk)
                                                                              └──> T7 (K8sProvisioner + config)
T4 ──> T5 (DockerProvisioner)
T6 ──> T8 (code_exec) ──> T9 (charter-check + 全量回归)
```

---

## Task 1: 新增 6 个错误子类到 `core/errors.py`

**Files:**
- Modify: `hanflow/core/errors.py`(末尾追加)
- Modify: `hanflow/core/__init__.py`(`__all__` + import)
- Test: `tests/core/test_errors.py`(若不存在则创建)

**Why first:** 所有后续任务抛错都用具体子类,必须先就位。零依赖,纯增量。

- [ ] **Step 1: 写失败测试**

```python
# tests/core/test_errors.py(若文件已存在, 追加到末尾; 否则新建)
import pytest
from hanflow.core.errors import (
    HanflowError,
    SandboxError,
    SandboxProvisionFailedError,
    SandboxDestroyFailedError,
    SandboxTimeoutError,
    SandboxDependencyMissingError,
    ToolWhitelistError,
)


def test_sandbox_error_is_hanflow_error():
    assert issubclass(SandboxError, HanflowError)


def test_sandbox_error_code_is_class_attr():
    # code 是类属性, 不是 __init__ kwarg(关键: 审计 round 1 修订)
    assert SandboxError.code == "SANDBOX_ERROR"
    assert SandboxProvisionFailedError.code == "SANDBOX_PROVISION_FAILED"
    assert SandboxDestroyFailedError.code == "SANDBOX_DESTROY_FAILED"
    assert SandboxTimeoutError.code == "SANDBOX_TIMEOUT"
    assert SandboxDependencyMissingError.code == "SANDBOX_DEP_MISSING"
    assert ToolWhitelistError.code == "TOOL_WHITELIST"


def test_sandbox_error_init_does_not_accept_code_kwarg():
    # 验证 __init__ 签名不含 code(回归审计 round 1 严重 #1)
    with pytest.raises(TypeError):
        SandboxError("msg", code="X")  # type: ignore[call-arg]


def test_sandbox_subclasses_inherit_init():
    # 子类继承基类 __init__, 只覆盖类属性
    err = SandboxProvisionFailedError("provision failed", run_id="r1", details={"k": "v"})
    assert err.code == "SANDBOX_PROVISION_FAILED"
    assert err.retryable is False  # 默认
    assert err.run_id == "r1"
    assert err.details == {"k": "v"}


def test_sandbox_retryable_semantics():
    assert SandboxProvisionFailedError.retryable is False
    assert SandboxDestroyFailedError.retryable is True
    assert SandboxTimeoutError.retryable is True
    assert SandboxDependencyMissingError.retryable is False


def test_sandbox_destroy_inherits_from_sandbox():
    assert issubclass(SandboxDestroyFailedError, SandboxError)
    assert issubclass(SandboxTimeoutError, SandboxError)


def test_tool_whitelist_error_is_hanflow_error():
    assert issubclass(ToolWhitelistError, HanflowError)
    assert ToolWhitelistError.code == "TOOL_WHITELIST"
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/core/test_errors.py -v`
Expected: FAIL with `ImportError: cannot import name 'SandboxError' from 'hanflow.core.errors'`

- [ ] **Step 3: 实现错误子类**

在 `hanflow/core/errors.py` 末尾追加(参考现有 14 个子类的模式,只覆盖类属性):

```python
# --- Sandbox 层级 (cycle 2026-W30-1.1.1: DOCKER sandbox provisioner) ---

class SandboxError(HanflowError):
    """Sandbox provisioning/destroy/exec 失败的基类。

    子类通过覆盖类属性 code/retryable 区分具体场景。
    §2.1 统一错误层级: atoms 永不吞异常, 由 orchestration 包装层捕获。
    """
    code = "SANDBOX_ERROR"


class SandboxProvisionFailedError(SandboxError):
    """容器创建/启动失败, 或不支持的 sandbox mode。非 retryable(通常配置错)。"""
    code = "SANDBOX_PROVISION_FAILED"


class SandboxDestroyFailedError(SandboxError):
    """容器销毁失败。retryable(container 可能 leak, 重试可能成功)。"""
    code = "SANDBOX_DESTROY_FAILED"
    retryable = True


class SandboxTimeoutError(SandboxError):
    """exec 或 provision 超时。retryable(换环境/换 daemon 可能成功)。"""
    code = "SANDBOX_TIMEOUT"
    retryable = True


class SandboxDependencyMissingError(SandboxError):
    """aiodocker 等依赖未安装。非 retryable(需 pip install)。"""
    code = "SANDBOX_DEP_MISSING"


class ToolWhitelistError(HanflowError):
    """工具调用不在 sub-agent 白名单内(顺手清理: 原 enforce_tool_whitelist 滥用基类 HanflowError)。"""
    code = "TOOL_WHITELIST"
```

- [ ] **Step 4: 更新 `hanflow/core/__init__.py` 的 `__all__` + import**

在现有 errors 分组的 import + `__all__` 中追加 6 个新名字(遵循现有分组注释)。位置参考现有 14 个子类的导出模式。

- [ ] **Step 5: 运行测试验证通过**

Run: `cd E:/opensource/hanflow && python -m pytest tests/core/test_errors.py -v`
Expected: 7 tests PASS

- [ ] **Step 6: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/core/errors.py hanflow/core/__init__.py tests/core/test_errors.py
git commit -m "feat(core): add SandboxError hierarchy + ToolWhitelistError

6 new HanflowError subclasses for cycle 2026-W30-1.1.1 DOCKER sandbox:
SandboxError (base) + Provision/Destroy/Timeout/DepMissing + ToolWhitelistError.
code/retryable are class attributes per existing 14-subclass pattern."
```

---

## Task 2: 创建 `core/sandbox_contract.py`(类型上移 + Protocol)

**Files:**
- Create: `hanflow/core/sandbox_contract.py`
- Modify: `hanflow/core/__init__.py`(`__all__` 追加新类型)
- Test: `tests/core/test_sandbox_contract.py`

**Why:** 契约中心,所有后续实现依赖它。先把类型从 isolation 上移(逻辑等价),并加新 Protocol。**此时 `isolation/sandbox.py` 仍持有原定义**(双份)——下一 Task 删除原定义 + re-export。这一步双份是临时的,确保中间状态可测。

- [ ] **Step 1: 写失败测试**

```python
# tests/core/test_sandbox_contract.py
from pathlib import Path
import pytest
from pydantic import BaseModel

from hanflow.core.sandbox_contract import (
    ExecInterface, ProvisionedSandbox, RunSandbox, SandboxMode,
    SandboxProvisioner, SandboxResources,
)


def test_sandbox_mode_values():
    assert SandboxMode.LOCAL == "local"
    assert SandboxMode.DOCKER == "docker"
    assert SandboxMode.K8S == "k8s"
    assert SandboxMode.NONE == "none"


def test_sandbox_resources_defaults():
    r = SandboxResources()
    assert r.cpu_limit == "2.0"
    assert r.memory_limit_mb == 2048
    assert r.timeout_seconds == 3600
    assert r.disk_limit_mb == 5120
    assert r.network_egress is None


def test_run_sandbox_fields():
    sb = RunSandbox(
        run_id="r1",
        mode=SandboxMode.LOCAL,
        workspace_root=Path("/tmp/ws"),
    )
    assert sb.run_id == "r1"
    assert sb.mode == SandboxMode.LOCAL
    assert sb.container_id is None
    assert sb.bash_enabled is False
    assert isinstance(sb.resources, SandboxResources)


def test_run_sandbox_create_local():
    class FakeMgr:
        def workspace_for(self, run_id): return Path(f"/tmp/{run_id}")
    sb = RunSandbox.create("r1", SandboxMode.LOCAL, FakeMgr())
    assert sb.workspace_root == Path("/tmp/r1")
    assert sb.bash_enabled is False


def test_exec_interface_is_protocol():
    # @runtime_checkable Protocol: isinstance 检查应工作
    assert hasattr(ExecInterface, "_is_protocol")
    assert ExecInterface._is_protocol is True


def test_provisioned_sandbox_fields():
    class FakeExec:
        async def run(self, *, command, stdin=None, timeout=30, cwd=None):
            return {"stdout": "", "stderr": "", "returncode": 0}

    ps = ProvisionedSandbox(
        run_id="r1",
        mode=SandboxMode.LOCAL,
        container_id=None,
        exec_interface=FakeExec(),
        workspace_root=Path("/tmp/ws"),
    )
    assert ps.run_id == "r1"
    assert ps.container_id is None


def test_provisioned_sandbox_requires_exec_interface():
    with pytest.raises(Exception):  # pydantic validation
        ProvisionedSandbox(
            run_id="r1", mode=SandboxMode.LOCAL, workspace_root=Path("/tmp"),
            exec_interface=None,  # type: ignore[arg-type]
        )


def test_sandbox_provisioner_is_protocol():
    assert hasattr(SandboxProvisioner, "_is_protocol")
    assert SandboxProvisioner._is_protocol is True


def test_sandbox_contract_does_not_import_isolation():
    """关键: core/sandbox_contract.py 不 import hanflow.isolation.*(charter-check 守护)"""
    import hanflow.core.sandbox_contract as mod
    import inspect
    src = inspect.getsource(mod)
    assert "hanflow.isolation" not in src, "core must not import isolation (reverse dep)"


def test_type_identity_with_isolation_reexport():
    """isolation/sandbox.py re-export 后, 同一个类"""
    from hanflow.isolation.sandbox import RunSandbox as IsoRunSandbox
    assert IsoRunSandbox is RunSandbox  # 同一个类(re-export 验证)
```

**注意**: `test_type_identity_with_isolation_reexport` 在 Task 2 会失败(isolation 仍持有自己的定义),这是预期的 —— **此 test 放在 Task 2 的 Step 1 但允许它失败,Task 3 完成后才 pass**。或者:**把这个 test 移到 Task 3 的 Step 1**,Task 2 只验证 contract 文件本身。**采用后者**(更干净):Task 2 不含此 test,Task 3 加。

- [ ] **Step 2: 运行测试验证失败(除 re-export test 外)**

Run: `cd E:/opensource/hanflow && python -m pytest tests/core/test_sandbox_contract.py -v`
Expected: FAIL with `ModuleNotFoundError: hanflow.core.sandbox_contract`

- [ ] **Step 3: 实现 `core/sandbox_contract.py`**

```python
# hanflow/core/sandbox_contract.py
"""Sandbox 契约层 (L0 core): 类型 + Protocol + 数据模型 (§13.6, §5.3).

cycle 2026-W30-1.1.1: 把 SandboxMode/SandboxResources/RunSandbox 从 isolation 上移到 core,
新增 SandboxProvisioner Protocol + ProvisionedSandbox + ExecInterface。
isolation/ 改为 re-export 这些类型保持向后兼容。

设计不变量 (CHARTER §2):
  - §2.3 Pydantic v2 数据模型 (BaseModel + ConfigDict)
  - §2.5 per-run sandbox (非 per-agent)
  - §3 依赖矩阵: core 只依赖自身, 此文件不 import hanflow.isolation.*

依赖倒置 (CHARTER §3): Protocol 在 core, 实现在 isolation (Local/Docker/K8s),
组合根 runtime/build_sandbox.py 注入具体 provisioner。
"""
from __future__ import annotations

from enum import StrEnum
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from pydantic import BaseModel, ConfigDict


class SandboxMode(StrEnum):
    """Sandbox 隔离级别 (per-run, 非 per-agent §2.5)。"""
    LOCAL = "local"      # host 执行 + per-run dir
    DOCKER = "docker"    # AioSandbox 隔离容器 (本 cycle 2026-W30-1.1.1 落地)
    K8S = "k8s"          # provisioner service → pod (Phase 10, 占位)
    NONE = "none"        # 仅上下文隔离 (纯 LLM sub-agents)


class SandboxResources(BaseModel):
    """Sandbox 资源限额。映射到 Docker --cpus/--memory/--storage-opt 等。"""
    cpu_limit: str = "2.0"                      # Docker --cpus (浮点 CPU 数)
    memory_limit_mb: int = 2048                 # Docker --memory (MB)
    timeout_seconds: int = 3600                 # container 存活上限 (Cmd: sleep N)
    disk_limit_mb: int = 5120                   # Docker --storage-opt size (overlay2, MB)
    network_egress: list[str] | None = None     # None=禁网(--network=none); 非空=host(本 cycle 不做 ACL)


class RunSandbox(BaseModel):
    """Per-run sandbox (纯数据模型, §2.5 per-run 不变量)。

    provisioner 行为不进此模型字段 (§2.3 模型纯数据);
    DOCKER/K8S provisioning 由组合根 runtime/build_sandbox.py 调 provisioner 完成。
    """
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
        保留此方法仅为不破坏现有 5 处调用点:
          - tests/isolation/test_sandbox.py × 4
          - tests/conftest.py:118
          - hanflow/sdk.py:130-134
        """
        ws = workspace_mgr.workspace_for(run_id)
        return cls(
            run_id=run_id,
            mode=mode,
            workspace_root=ws,
            resources=resources or SandboxResources(),
            bash_enabled=False,  # LOCAL 默认禁 bash
        )


# 顺序: ExecInterface → ProvisionedSandbox → SandboxProvisioner (消除前向引用)

class ExecInterface(Protocol):
    """容器/进程内执行代码的后端无关接口 (供 code_exec 等工具复用)。

    实现者:
      - LocalProvisioner 用 host subprocess (_LocalExec)
      - DockerProvisioner 用 docker exec (_DockerExec)

    返回与现有 _exec_local() 同构的 dict, 保证 call site 同构。
    timeout 超时由实现内部包成 SandboxTimeoutError 抛出 (见 design 错误处理章)。
    """
    async def run(
        self,
        *,
        command: list[str],
        stdin: str | None = None,
        timeout: int = 30,
        cwd: str | None = None,
    ) -> dict[str, Any]:
        """执行命令, 返回 {"stdout": str, "stderr": str, "returncode": int}。

        超时抛 SandboxTimeoutError (retryable=True);
        其它失败抛 SandboxError 子类。
        """
        ...


class ProvisionedSandbox(BaseModel):
    """provision 的产物: 容器/进程句柄 + 执行接口。

    exec_interface 是后端无关的执行抽象 (见 ExecInterface Protocol);
    workspace_root 是 bind mount 或 host 路径; DOCKER 档为容器内视角 (如 /workspace)。
    """
    run_id: str
    mode: SandboxMode
    container_id: str | None = None      # LOCAL/NONE 为 None; DOCKER/K8S 必填
    exec_interface: ExecInterface        # 引用已定义的 ExecInterface (无前向引用)
    workspace_root: Path                 # bind mount 或 host 路径
    model_config = ConfigDict(arbitrary_types_allowed=True)


@runtime_checkable
class SandboxProvisioner(Protocol):
    """L0 契约: 把 RunSandbox (数据) provision 成可执行的 ProvisionedSandbox。

    实现在 L4 isolation/ (Local/Docker/K8s), 组合根 runtime/build_sandbox.py 注入。
    §2.5 per-run 不变量: provision 只接受 run 级 RunSandbox, 不接受 per-agent spec。
    """
    name: str

    async def provision(self, run_sandbox: RunSandbox) -> ProvisionedSandbox: ...

    async def destroy(self, provisioned: ProvisionedSandbox) -> None: ...
```

- [ ] **Step 4: 更新 `core/__init__.py`**

在 `__all__` 加新分组 `# sandbox contract`,导出 `SandboxMode/SandboxResources/RunSandbox/ExecInterface/ProvisionedSandbox/SandboxProvisioner`。

- [ ] **Step 5: 运行测试验证通过(不含 re-export test)**

Run: `cd E:/opensource/hanflow && python -m pytest tests/core/test_sandbox_contract.py -v`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/core/sandbox_contract.py hanflow/core/__init__.py tests/core/test_sandbox_contract.py
git commit -m "feat(core): add sandbox_contract.py (types moved up + Protocol)

Move SandboxMode/Resources/RunSandbox from isolation to core, add
SandboxProvisioner Protocol + ProvisionedSandbox + ExecInterface.
No core->isolation reverse import (charter-check layering green).
isolation/sandbox.py still has duplicate definitions; re-export in next task."
```

---

## Task 3: `isolation/sandbox.py` 瘦身 + re-export + spawn_agent 修订

**Files:**
- Modify: `hanflow/isolation/sandbox.py`(大幅瘦身:删类型定义,加 re-export,改 spawn_agent,加 K8sProvisioner)
- Test: `tests/isolation/test_sandbox.py`(**不改**,验证回归)
- Test: `tests/isolation/test_spawn_agent_dedicated.py`(**创建**,验证 dedicated_sandbox 契约 + 错误透传)

**Why:** 删除 isolation 里的重复类型定义,改为 re-export core;修订 `spawn_agent` 错误透传 + DOCKER subdir;加 `K8sProvisioner` 占位。**这一步完成后,类型上移真正生效**(Task 2 的 `test_type_identity_with_isolation_reexport` 现在能加并 pass)。

- [ ] **Step 1: 在 `tests/core/test_sandbox_contract.py` 加 re-export test**

追加到 Task 2 的 test 文件末尾:

```python
def test_type_identity_with_isolation_reexport():
    """isolation/sandbox.py re-export 后, 同一个类"""
    from hanflow.isolation.sandbox import (
        RunSandbox as IsoRunSandbox,
        SandboxMode as IsoSandboxMode,
        SandboxResources as IsoSandboxResources,
    )
    assert IsoRunSandbox is RunSandbox
    assert IsoSandboxMode is SandboxMode
    assert IsoSandboxResources is SandboxResources
```

- [ ] **Step 2: 写 dedicated_sandbox 契约 test**

```python
# tests/isolation/test_spawn_agent_dedicated.py
"""dedicated_sandbox 契约 (direction 验收 #8):
  - dedicated=True/False 都不新 provision per-agent 容器 (per-run 不变量 §2.5)
  - DOCKER 档 subdir 落 provisioned.workspace_root (容器内视角)
  - SandboxError 子类透传, 不被基类降级 (§5 禁止吞异常)
"""
from datetime import UTC, datetime
from pathlib import Path
import pytest

from hanflow.core.context import FakeContext
from hanflow.core.errors import SandboxProvisionFailedError, SandboxTimeoutError
from hanflow.core.sandbox_contract import (
    ExecInterface, ProvisionedSandbox, RunSandbox, SandboxMode,
)
from hanflow.core.state import NexusState, RunMeta
from hanflow.isolation.sandbox import AgentSpec, spawn_agent


class _FakeExec:
    """记录 mkdir 调用, 可注入异常。"""
    def __init__(self, fail_with=None):
        self.calls = []
        self.fail_with = fail_with

    async def run(self, *, command, stdin=None, timeout=30, cwd=None):
        self.calls.append(command)
        if self.fail_with is not None:
            raise self.fail_with
        return {"stdout": "", "stderr": "", "returncode": 0}


def _state(run_id="r1"):
    return NexusState(
        meta=RunMeta(run_id=run_id, workflow_name="w", workflow_version="0.1.0",
                     started_at=datetime.now(UTC), mode="dynamic", trigger="api"),
        inputs={}, outputs={}, node_states={}, artifacts=[], memory_ops=[], variables={},
    )


def _make_provisioned(mode, fail_with=None):
    return ProvisionedSandbox(
        run_id="r1", mode=mode, container_id="c1" if mode == SandboxMode.DOCKER else None,
        exec_interface=_FakeExec(fail_with), workspace_root=Path("/workspace"),
    )


@pytest.mark.asyncio
async def test_dedicated_sandbox_true_does_not_provision_per_agent_container(workspace_mgr, trace):
    """direction 验收 #8: dedicated=True 不新 provision per-agent 容器。
    fake provisioner 的 provision() 从不被 spawn_agent 调用。
    """
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a", dedicated_sandbox=True, sandbox_mode=SandboxMode.DOCKER)
    run_sb = RunSandbox.create("r1", SandboxMode.DOCKER, workspace_mgr)
    provisioned = _make_provisioned(SandboxMode.DOCKER)
    fake_exec = provisioned.exec_interface  # _FakeExec

    await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=provisioned)

    # mkdir 被调用 (在 run container 内分 subdir), 但 provision 不是这里调的
    assert len(fake_exec.calls) == 1
    assert fake_exec.calls[0][:2] == ["mkdir", "-p"]


@pytest.mark.asyncio
async def test_dedicated_sandbox_false_docker_subdir_in_container(workspace_mgr, trace):
    """DOCKER 档下 dedicated=False 的 subdir 也落 provisioned.workspace_root(容器内视角)。
    direction 审计 round 1 严重 #2 修订: 防止数据流断裂。
    """
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a", dedicated_sandbox=False)
    run_sb = RunSandbox.create("r1", SandboxMode.DOCKER, workspace_mgr)
    provisioned = _make_provisioned(SandboxMode.DOCKER)
    fake_exec = provisioned.exec_interface

    await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=provisioned)

    # subdir 落 provisioned.workspace_root / agent-xxx (容器内)
    assert spec.workspace_subdir is not None
    assert spec.workspace_subdir.startswith("/workspace/agent-")
    assert len(fake_exec.calls) == 1


@pytest.mark.asyncio
async def test_dedicated_sandbox_true_docker_subdir_in_container(workspace_mgr, trace):
    """DOCKER 档下 dedicated=True 与 False 落点一致(共享 run container)。"""
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a", dedicated_sandbox=True, sandbox_mode=SandboxMode.DOCKER)
    run_sb = RunSandbox.create("r1", SandboxMode.DOCKER, workspace_mgr)
    provisioned = _make_provisioned(SandboxMode.DOCKER)

    await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=provisioned)

    assert spec.workspace_subdir is not None
    assert spec.workspace_subdir.startswith("/workspace/agent-")


@pytest.mark.asyncio
async def test_local_mode_subdir_in_host(workspace_mgr, trace):
    """LOCAL 档(provisioned=None 或 mode=LOCAL)subdir 落 host workspace_root。"""
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a")
    run_sb = RunSandbox.create("r1", SandboxMode.LOCAL, workspace_mgr)

    await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=None)

    assert spec.workspace_subdir is not None
    # host 路径, 不在 /workspace(容器路径)下
    assert "/workspace/agent-" not in spec.workspace_subdir
    assert "agent-" in spec.workspace_subdir


@pytest.mark.asyncio
async def test_sandbox_error_subclass_propagates(workspace_mgr, trace):
    """§5 禁止吞异常: SandboxTimeoutError 不被降级成基类 HanflowError。"""
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a", dedicated_sandbox=True, sandbox_mode=SandboxMode.DOCKER)
    run_sb = RunSandbox.create("r1", SandboxMode.DOCKER, workspace_mgr)
    provisioned = _make_provisioned(SandboxMode.DOCKER, fail_with=SandboxTimeoutError("timeout"))

    with pytest.raises(SandboxTimeoutError) as exc_info:
        await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=provisioned)
    # code/retryable 保留
    assert exc_info.value.code == "SANDBOX_TIMEOUT"
    assert exc_info.value.retryable is True


@pytest.mark.asyncio
async def test_non_sandbox_exception_wrapped_as_provision_failed(workspace_mgr, trace):
    """非 Sandbox 异常包成 SandboxProvisionFailedError(避免裸 Exception 漏出)。"""
    parent = FakeContext(state=_state())
    spec = AgentSpec(task="x", sub_agent="a", dedicated_sandbox=True, sandbox_mode=SandboxMode.DOCKER)
    run_sb = RunSandbox.create("r1", SandboxMode.DOCKER, workspace_mgr)
    provisioned = _make_provisioned(SandboxMode.DOCKER, fail_with=RuntimeError("docker daemon gone"))

    with pytest.raises(SandboxProvisionFailedError) as exc_info:
        await spawn_agent(parent=parent, spec=spec, run_sandbox=run_sb, trace=trace, provisioned=provisioned)
    assert exc_info.value.code == "SANDBOX_PROVISION_FAILED"
```

- [ ] **Step 3: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_spawn_agent_dedicated.py tests/core/test_sandbox_contract.py::test_type_identity_with_isolation_reexport -v`
Expected: FAIL(因为 isolation/sandbox.py 还持有自己的类型定义 + spawn_agent 还是旧的)

- [ ] **Step 4: 瘦身 `isolation/sandbox.py`**

完整替换 `hanflow/isolation/sandbox.py`(参考 design.md 组件 #8 的完整代码块)。关键变更:
- 顶部 import 从 `hanflow.core.sandbox_contract` re-export `SandboxMode/SandboxResources/RunSandbox/ProvisionedSandbox/SandboxProvisioner/ExecInterface`
- 删除原 32-80 行的类型定义
- `SubAgentIsolation` / `AgentSpec` 保留不变
- `spawn_agent` 修订:加 `provisioned` 形参,DOCKER 档 subdir 落 `provisioned.workspace_root`,`except SandboxError: raise` + `except Exception as exc: raise SandboxProvisionFailedError(...)`
- `enforce_tool_whitelist` 改用 `ToolWhitelistError`
- 末尾追加 `K8sProvisioner` 占位类(NotImplementedError Phase 10)
- `__all__` 更新

- [ ] **Step 5: 运行 isolation 全量回归**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/ -v`
Expected: 现有 5 个 test 全绿(类型 re-export 后 `RunSandbox.create` 行为不变)+ 新增 6 个 dedicated_sandbox test 绿

- [ ] **Step 6: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/isolation/sandbox.py tests/isolation/test_spawn_agent_dedicated.py tests/core/test_sandbox_contract.py
git commit -m "refactor(isolation): slim sandbox.py + re-export from core

- Remove SandboxMode/Resources/RunSandbox definitions (moved to core), re-export
- spawn_agent: add provisioned param, DOCKER subdir lands in container view
- spawn_agent: except SandboxError propagates, others wrapped as ProvisionFailed
- enforce_tool_whitelist: use ToolWhitelistError instead of base HanflowError
- Add K8sProvisioner stub (NotImplementedError Phase 10)
- New tests: dedicated_sandbox contract (direction acceptance #8)"
```

---

## Task 4: `LocalProvisioner` + `_LocalExec`

**Files:**
- Create: `hanflow/isolation/local_provisioner.py`
- Test: `tests/isolation/test_local_provisioner.py`
- Modify: `tests/isolation/conftest.py`(加 `_FakeProvisioner` / `_FakeExec` fixtures,后续 Task 复用)

**Why:** LocalProvisioner 是 DOCKER 的同构基础,且无需 docker daemon,CI 必绿。先把 LOCAL 档做实,DockerProvisioner 复用同样的形状。

- [ ] **Step 1: 写失败测试**

```python
# tests/isolation/test_local_provisioner.py
from datetime import UTC, datetime
from pathlib import Path
import sys
import pytest

from hanflow.core.errors import SandboxTimeoutError
from hanflow.core.sandbox_contract import RunSandbox, SandboxMode
from hanflow.isolation.local_provisioner import LocalProvisioner, _LocalExec


class _FakeMgr:
    def workspace_for(self, run_id): return Path(f"/tmp/{run_id}")


@pytest.mark.asyncio
async def test_local_provisioner_provision_returns_provisioned_sandbox():
    sb = RunSandbox.create("r1", SandboxMode.LOCAL, _FakeMgr())
    p = LocalProvisioner()
    provisioned = await p.provision(sb)

    assert provisioned.run_id == "r1"
    assert provisioned.mode == SandboxMode.LOCAL
    assert provisioned.container_id is None
    assert isinstance(provisioned.exec_interface, _LocalExec)


@pytest.mark.asyncio
async def test_local_provisioner_provision_wrong_mode_raises():
    sb = RunSandbox.create("r1", SandboxMode.DOCKER, _FakeMgr())
    p = LocalProvisioner()
    with pytest.raises(ValueError):
        await p.provision(sb)


@pytest.mark.asyncio
async def test_local_provisioner_destroy_noop():
    p = LocalProvisioner()
    sb = RunSandbox.create("r1", SandboxMode.LOCAL, _FakeMgr())
    provisioned = await p.provision(sb)
    await p.destroy(provisioned)  # should not raise


@pytest.mark.asyncio
async def test_local_exec_run_python_hello_world(tmp_path):
    exec_ = _LocalExec(tmp_path, "r1")
    snippet = tmp_path / "snippet.py"
    snippet.write_text("print('hello from local')", encoding="utf-8")

    result = await exec_.run(command=[sys.executable, str(snippet)], timeout=10)

    assert result["returncode"] == 0
    assert "hello from local" in result["stdout"]
    assert result["stderr"] == ""


@pytest.mark.asyncio
async def test_local_exec_run_timeout_raises_sandbox_timeout(tmp_path):
    exec_ = _LocalExec(tmp_path, "r1")
    snippet = tmp_path / "loop.py"
    snippet.write_text("import time; time.sleep(10)", encoding="utf-8")

    with pytest.raises(SandboxTimeoutError) as exc_info:
        await exec_.run(command=[sys.executable, str(snippet)], timeout=1)

    assert exc_info.value.code == "SANDBOX_TIMEOUT"
    assert exc_info.value.retryable is True
    assert exc_info.value.run_id == "r1"


@pytest.mark.asyncio
async def test_local_exec_run_nonzero_returncode(tmp_path):
    exec_ = _LocalExec(tmp_path, "r1")
    snippet = tmp_path / "fail.py"
    snippet.write_text("import sys; sys.exit(2)", encoding="utf-8")

    result = await exec_.run(command=[sys.executable, str(snippet)], timeout=5)

    assert result["returncode"] == 2
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_local_provisioner.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 3: 实现 `local_provisioner.py`**

完整代码见 design.md 组件 #2。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_local_provisioner.py -v`
Expected: 6 tests PASS

- [ ] **Step 5: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/isolation/local_provisioner.py tests/isolation/test_local_provisioner.py
git commit -m "feat(isolation): add LocalProvisioner + _LocalExec

LocalProvisioner wraps host subprocess execution. _LocalExec implements
ExecInterface, wraps asyncio.TimeoutError internally as SandboxTimeoutError."
```

---

## Task 5: `DockerProvisioner` + `_DockerExec`

**Files:**
- Create: `hanflow/isolation/docker_provisioner.py`
- Test: `tests/isolation/test_docker_provisioner.py`(含 skipif 守护)
- Modify: `pyproject.toml`(加 docker optional-extra,先于测试)

**Why:** DOCKER 档核心实现。契约测试用 `skipif` 守护无 daemon 环境,fake client 测试配置生成逻辑。

- [ ] **Step 1: 写失败测试**

```python
# tests/isolation/test_docker_provisioner.py
"""DockerProvisioner 测试。

策略:
  - 配置生成 (_build_config) 用纯单元测试, 不需 daemon
  - 完整 provision/destroy 用 pytest.mark.skipif(no docker daemon)
  - dep_missing 用 monkeypatch sys.modules 模拟 ImportError
"""
import shutil
import subprocess
import sys
import pytest

from hanflow.core.errors import (
    SandboxDependencyMissingError, SandboxProvisionFailedError,
)
from hanflow.core.sandbox_contract import RunSandbox, SandboxMode


def _docker_available() -> bool:
    if not shutil.which("docker"):
        return False
    try:
        r = subprocess.run(["docker", "info"], capture_output=True, timeout=5)
        return r.returncode == 0
    except Exception:
        return False


HAS_DOCKER = _docker_available()
skip_no_docker = pytest.mark.skipif(not HAS_DOCKER, reason="no docker daemon")


class _FakeMgr:
    def workspace_for(self, run_id):
        from pathlib import Path
        return Path(f"/tmp/{run_id}")


def test_build_config_resource_mapping(tmp_path):
    """纯单元: 验证资源字段正确映射到 Docker HostConfig(不需 daemon)。"""
    from hanflow.isolation.docker_provisioner import DockerProvisioner
    from hanflow.core.sandbox_contract import SandboxResources

    p = DockerProvisioner(base_image="python:3.11-slim")
    sb = RunSandbox(
        run_id="r1", mode=SandboxMode.DOCKER, workspace_root=tmp_path,
        resources=SandboxResources(
            cpu_limit="2.0", memory_limit_mb=2048, timeout_seconds=3600,
            disk_limit_mb=5120, network_egress=None,
        ),
    )
    config = p._build_config(sb)

    assert config["Image"] == "python:3.11-slim"
    assert config["Cmd"] == ["sleep", "3600"]
    assert config["WorkingDir"] == "/workspace"
    hc = config["HostConfig"]
    assert hc["CpuQuota"] == 200000  # 2.0 * 100000
    assert hc["Memory"] == 2048 * 1024 * 1024
    assert hc["NetworkMode"] == "none"  # network_egress is None
    assert hc["StorageOpt"] == {"size": "5120m"}
    assert any("/workspace:rw" in b for b in hc["Binds"])


def test_build_config_network_host_when_egress_set(tmp_path):
    """network_egress 非 None 时映射到 --network=host(本 cycle 不做 ACL)。"""
    from hanflow.isolation.docker_provisioner import DockerProvisioner
    from hanflow.core.sandbox_contract import SandboxResources

    p = DockerProvisioner()
    sb = RunSandbox(
        run_id="r1", mode=SandboxMode.DOCKER, workspace_root=tmp_path,
        resources=SandboxResources(network_egress=["*"]),
    )
    config = p._build_config(sb)
    assert config["HostConfig"]["NetworkMode"] == "host"


@pytest.mark.asyncio
async def test_provision_raises_dep_missing_when_aiodocker_absent(monkeypatch):
    """aiodocker 未装时抛 SandboxDependencyMissingError。"""
    from hanflow.isolation.docker_provisioner import DockerProvisioner

    # 模拟 aiodocker 不可用
    monkeypatch.setitem(sys.modules, "aiodocker", None)
    sb = RunSandbox.create("r1", SandboxMode.DOCKER, _FakeMgr())
    p = DockerProvisioner()

    with pytest.raises(SandboxDependencyMissingError) as exc_info:
        await p.provision(sb)
    assert exc_info.value.code == "SANDBOX_DEP_MISSING"
    assert exc_info.value.retryable is False


@skip_no_docker
@pytest.mark.asyncio
async def test_provision_real_container_lifecycle(tmp_path):
    """契约测试: 真起 container, 验证资源限额生效, destroy 清理。"""
    from hanflow.isolation.docker_provisioner import DockerProvisioner
    from hanflow.core.sandbox_contract import SandboxResources

    sb = RunSandbox(
        run_id=f"test-{tmp_path.name}", mode=SandboxMode.DOCKER, workspace_root=tmp_path,
        resources=SandboxResources(cpu_limit="1.0", memory_limit_mb=512, timeout_seconds=60),
    )
    p = DockerProvisioner(base_image="python:3.11-slim")
    provisioned = await p.provision(sb)

    try:
        assert provisioned.container_id is not None
        assert provisioned.mode == SandboxMode.DOCKER
        assert provisioned.workspace_root.name == "workspace" or str(provisioned.workspace_root) == "/workspace"

        # 验证 code 可在容器内执行
        result = await provisioned.exec_interface.run(
            command=["python3", "-c", "print('hello from docker')"], timeout=10,
        )
        assert result["returncode"] == 0
        assert "hello from docker" in result["stdout"]
    finally:
        await p.destroy(provisioned)


@skip_no_docker
@pytest.mark.asyncio
async def test_provision_resource_limits_enforced(tmp_path):
    """资源限额在真实 container 上生效(docker inspect 验证)。"""
    import asyncio
    from hanflow.isolation.docker_provisioner import DockerProvisioner
    from hanflow.core.sandbox_contract import SandboxResources

    sb = RunSandbox(
        run_id=f"rl-{tmp_path.name}", mode=SandboxMode.DOCKER, workspace_root=tmp_path,
        resources=SandboxResources(cpu_limit="1.5", memory_limit_mb=256, timeout_seconds=30),
    )
    p = DockerProvisioner(base_image="python:3.11-slim")
    provisioned = await p.provision(sb)

    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "inspect", "--format", "{{.HostConfig.Memory}}",
            provisioned.container_id,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        # 256 MB = 268435456 bytes
        assert stdout.decode().strip() == "268435456"
    finally:
        await p.destroy(provisioned)
```

- [ ] **Step 2: 加 docker optional-extra 到 `pyproject.toml`**

在 `[project.optional-dependencies]` 段加:

```toml
docker = ["aiodocker>=0.23"]
```

并更新 `all` 组合:`all = ["hanflow[langsmith,otel,postgres,redis,s3,openai,anthropic,glm,deepseek,ollama,docker]"]`

- [ ] **Step 3: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_docker_provisioner.py -v`
Expected: FAIL with `ModuleNotFoundError`

- [ ] **Step 4: 实现 `docker_provisioner.py`**

完整代码见 design.md 组件 #3。**注意 `_DockerExec.run()` 内部细节**:
- lazy import `aiodocker`(顶部 try/except ImportError 包成 `SandboxDependencyMissingError`)
- `client.containers.get(cid).exec(...)` 或 `client.exec_create(cid, cmd=...) + exec_start(...)`
- `asyncio.wait_for(...)` 守护 timeout,超时抛 `SandboxTimeoutError`
- 解码 stdout/stderr bytes → str,提取 returncode

- [ ] **Step 5: 安装 aiodocker(本地开发)**

Run: `cd E:/opensource/hanflow && pip install -e ".[dev,docker]"`
(若本机无 docker daemon,契约测试自动 skip,fake 测试仍跑)

- [ ] **Step 6: 运行测试验证通过**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_docker_provisioner.py -v`
Expected: 配置测试 + dep_missing 测试 PASS;契约测试 PASS 或 SKIP(取决于 daemon)

- [ ] **Step 7: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/isolation/docker_provisioner.py tests/isolation/test_docker_provisioner.py pyproject.toml
git commit -m "feat(isolation): add DockerProvisioner + _DockerExec (aiodocker)

Real container provisioning with resource limits, bind mount, destroy.
Optional-extra 'docker' added. Contract tests guarded by skipif(no daemon).
LocalExec/DockerExec wrap timeout internally as SandboxTimeoutError."
```

---

## Task 6: `build_sandbox` 组合根 + `RuntimeContextImpl` 接入 + `sdk.py` 接入

**Files:**
- Create: `hanflow/runtime/build_sandbox.py`
- Modify: `hanflow/orchestration/context_impl.py`(加 `provisioned` 字段)
- Modify: `hanflow/sdk.py`(单点接入)
- Test: `tests/isolation/test_build_sandbox.py`

**Why:** 把所有 provisioner 串起来,SDK 接入点是生产入口。

- [ ] **Step 1: 写失败测试**

```python
# tests/isolation/test_build_sandbox.py
from pathlib import Path
import pytest

from hanflow.core.errors import SandboxProvisionFailedError
from hanflow.core.sandbox_contract import ProvisionedSandbox, RunSandbox, SandboxMode
from hanflow.runtime.build_sandbox import build_sandbox


class _FakeMgr:
    def workspace_for(self, run_id): return Path(f"/tmp/{run_id}")


@pytest.mark.asyncio
async def test_build_sandbox_local_returns_both():
    sb, provisioned = await build_sandbox(
        run_id="r1", mode=SandboxMode.LOCAL, workspace_mgr=_FakeMgr(),
    )
    assert isinstance(sb, RunSandbox)
    assert isinstance(provisioned, ProvisionedSandbox)
    assert provisioned.mode == SandboxMode.LOCAL
    assert provisioned.container_id is None


@pytest.mark.asyncio
async def test_build_sandbox_none_reuses_local():
    sb, provisioned = await build_sandbox(
        run_id="r1", mode=SandboxMode.NONE, workspace_mgr=_FakeMgr(),
    )
    assert provisioned.mode == SandboxMode.NONE or provisioned.mode == SandboxMode.LOCAL


@pytest.mark.asyncio
async def test_build_sandbox_k8s_raises_not_implemented():
    with pytest.raises(NotImplementedError, match="Phase 10"):
        await build_sandbox(run_id="r1", mode=SandboxMode.K8S, workspace_mgr=_FakeMgr())


@pytest.mark.asyncio
async def test_build_sandbox_unknown_mode_raises_provision_failed():
    # 用非法 mode 构造(绕过 StrEnum 校验需要 mock)
    from hanflow.runtime import build_sandbox as bs
    # 直接测内部 dispatch: 传字符串 "weird" 经 SandboxMode() 会 ValueError
    with pytest.raises((SandboxProvisionFailedError, ValueError)):
        await build_sandbox(run_id="r1", mode="weird", workspace_mgr=_FakeMgr())  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_build_sandbox_docker_with_fake(monkeypatch):
    """用 fake DockerProvisioner 测 DOCKER 分派(不需 daemon)。"""
    from hanflow.isolation import docker_provisioner as dp_mod
    from hanflow.core.sandbox_contract import ProvisionedSandbox

    class _FakeDocker:
        name = "docker"
        async def provision(self, sb):
            return ProvisionedSandbox(
                run_id=sb.run_id, mode=SandboxMode.DOCKER, container_id="fake-cid",
                exec_interface=object(),  # _FakeExec 偷懒, 这里只测分派
                workspace_root=Path("/workspace"),
            )
        async def destroy(self, p): pass

    monkeypatch.setattr(dp_mod, "DockerProvisioner", _FakeDocker)

    sb, provisioned = await build_sandbox(
        run_id="r1", mode=SandboxMode.DOCKER, workspace_mgr=_FakeMgr(),
    )
    assert provisioned.container_id == "fake-cid"
    assert provisioned.mode == SandboxMode.DOCKER
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_build_sandbox.py -v`
Expected: FAIL with `ModuleNotFoundError: hanflow.runtime.build_sandbox`

- [ ] **Step 3: 实现 `runtime/build_sandbox.py`**

完整代码见 design.md 组件 #5。

- [ ] **Step 4: 运行测试验证通过**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_build_sandbox.py -v`
Expected: 5 tests PASS

- [ ] **Step 5: 修改 `RuntimeContextImpl` 加 `provisioned` 字段**

在 `hanflow/orchestration/context_impl.py` 的 `__init__` 加可选 `provisioned: ProvisionedSandbox | None = None` 参数,存到 `self._provisioned`。加 `def provisioned(self) -> ProvisionedSandbox | None: return self._provisioned` 方法。**RuntimeContext Protocol 不动**(避免污染 nodes 接口)。

- [ ] **Step 6: 修改 `sdk.py` 接入 build_sandbox**

在 `hanflow/sdk.py` 的 `Hanflow._ensure_components`(或 `run` 方法)中,把原 `sandbox = RunSandbox.create(mode=SandboxMode.LOCAL, ...)` 替换为:

```python
mode_str = self._config.get("isolation", {}).get("mode", "local") if isinstance(self._config, dict) else "local"
mode = SandboxMode(mode_str)
self._sandbox, self._provisioned = await build_sandbox(
    run_id=run_id, mode=mode, workspace_mgr=self._workspace_mgr,
    docker_image=self._config.get("isolation", {}).get("docker", {}).get("base_image", "python:3.11-slim")
    if isinstance(self._config, dict) else "python:3.11-slim",
)
```

`Hanflow` 实例持有 `self._provisioned`,后续 `RuntimeContextImpl` 构造时传入。

**注意**:`Hanflow` 类的现有 config 读取方式可能不是 dict(需探查 `hanflow/sdk.py` 实际),执行时先读源码确认。

- [ ] **Step 7: 运行 smoke test**

Run: `cd E:/opensource/hanflow && python -m pytest tests/test_smoke.py tests/test_sdk.py -v`
Expected: PASS(LOCAL 默认行为不变)

- [ ] **Step 8: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/runtime/build_sandbox.py hanflow/orchestration/context_impl.py hanflow/sdk.py tests/isolation/test_build_sandbox.py
git commit -m "feat(runtime): add build_sandbox composition root + ctx/sdk wiring

build_sandbox dispatches to provisioner by mode, returns (RunSandbox,
ProvisionedSandbox). RuntimeContextImpl holds provisioned privately.
sdk.py Hanflow._ensure_components uses build_sandbox (default mode=local)."
```

---

## Task 7: K8sProvisioner 占位 + config schema + 集成 smoke

**Files:**
- Verify: `hanflow/isolation/sandbox.py`(Task 3 已加 K8sProvisioner,这里只补测试)
- Modify: `hanflow/config.py` 或等价位置(加 isolation schema)
- Test: `tests/isolation/test_k8s_provisioner_stub.py`

**Why:** K8sProvisioner 占位已随 Task 3 加到 sandbox.py,这里补独立测试 + config schema。

- [ ] **Step 1: 写 K8sProvisioner 占位测试**

```python
# tests/isolation/test_k8s_provisioner_stub.py
import pytest
from hanflow.core.sandbox_contract import RunSandbox, SandboxMode
from hanflow.isolation.sandbox import K8sProvisioner


class _FakeMgr:
    def workspace_for(self, run_id):
        from pathlib import Path
        return Path(f"/tmp/{run_id}")


@pytest.mark.asyncio
async def test_k8s_provisioner_provision_raises_not_implemented():
    sb = RunSandbox.create("r1", SandboxMode.K8S, _FakeMgr())
    p = K8sProvisioner()
    with pytest.raises(NotImplementedError, match="Phase 10"):
        await p.provision(sb)


@pytest.mark.asyncio
async def test_k8s_provisioner_destroy_raises_not_implemented():
    p = K8sProvisioner()
    with pytest.raises(NotImplementedError, match="Phase 10"):
        await p.destroy(None)  # type: ignore[arg-type]


def test_k8s_provisioner_name():
    assert K8sProvisioner.name == "k8s"
```

- [ ] **Step 2: 运行测试验证通过(Task 3 已加实现)**

Run: `cd E:/opensource/hanflow && python -m pytest tests/isolation/test_k8s_provisioner_stub.py -v`
Expected: 3 PASS

- [ ] **Step 3: 探查并修改 config schema**

读 `hanflow/config.py` 找到 isolation 相关 schema(若有 Pydantic config model)。若无 config.py 集中式 schema,在 `sdk.py` 用 `self._config.get(...)` 即可,跳过此步。

- [ ] **Step 4: 提交**

```bash
cd E:/opensource/hanflow
git add tests/isolation/test_k8s_provisioner_stub.py
git commit -m "test(isolation): add K8sProvisioner stub tests

K8sProvisioner raises NotImplementedError(Phase 10) per CHARTER §4 placeholder convention."
```

---

## Task 8: `code_exec` DOCKER 路径 + mode 词表对齐

**Files:**
- Modify: `hanflow/tools/builtin/code_exec.py`
- Test: `tests/tools/test_code_exec.py`(创建或扩展)

**Why:** 让 code_exec 工具真正能经 provisioned sandbox 执行,DOCKER 档从占位变可用。

- [ ] **Step 1: 写失败测试**

```python
# tests/tools/test_code_exec.py
import sys
from pathlib import Path
import pytest

from hanflow.core.errors import HanflowError
from hanflow.tools.builtin.code_exec import CodeExecServer


@pytest.mark.asyncio
async def test_code_exec_none_mode_local_subprocess(tmp_path):
    server = CodeExecServer(workspace=tmp_path, mode="none")
    result = await server.call("run", {"language": "python", "code": "print('hello')"})
    assert result["returncode"] == 0
    assert "hello" in result["stdout"]


@pytest.mark.asyncio
async def test_code_exec_with_exec_interface_uses_it(tmp_path):
    """传入 exec_interface 时, 优先用它(覆盖 mode)。"""
    class _FakeExec:
        async def run(self, *, command, stdin=None, timeout=30, cwd=None):
            return {"stdout": "from fake", "stderr": "", "returncode": 0}
    server = CodeExecServer(workspace=tmp_path, mode="docker", exec_interface=_FakeExec())
    result = await server.call("run", {"language": "python", "code": "print(1)"})
    assert result["stdout"] == "from fake"


@pytest.mark.asyncio
async def test_code_exec_docker_without_exec_interface_raises(tmp_path):
    """mode=docker 但没传 exec_interface → 明确错误(对齐 Phase 8 文案)。"""
    server = CodeExecServer(workspace=tmp_path, mode="docker")
    with pytest.raises(HanflowError) as exc_info:
        await server.call("run", {"language": "python", "code": "print(1)"})
    # Phase 8 文案对齐(原 Phase 7 → Phase 8)
    assert "Phase 8" in str(exc_info.value) or "provisioned sandbox" in str(exc_info.value)


@pytest.mark.asyncio
async def test_code_exec_unsupported_language_raises(tmp_path):
    server = CodeExecServer(workspace=tmp_path, mode="none")
    with pytest.raises(HanflowError):
        await server.call("run", {"language": "javascript", "code": "..."})


@pytest.mark.asyncio
async def test_code_exec_unknown_tool_raises(tmp_path):
    server = CodeExecServer(workspace=tmp_path, mode="none")
    with pytest.raises(HanflowError):
        await server.call("frobnicate", {})
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd E:/opensource/hanflow && python -m pytest tests/tools/test_code_exec.py -v`
Expected: FAIL(`CodeExecServer.__init__` 还不接受 `exec_interface`)

- [ ] **Step 3: 修改 `code_exec.py`**

完整代码见 design.md 组件 #7。关键变更:
- `__init__` 加 `exec_interface: ExecInterface | None = None`
- `call()` 优先用 `self._exec`(若注入)
- fallback 错误文案对齐 "Phase 8" + "provisioned sandbox"

- [ ] **Step 4: 运行测试验证通过**

Run: `cd E:/opensource/hanflow && python -m pytest tests/tools/test_code_exec.py -v`
Expected: 5 PASS

- [ ] **Step 5: 提交**

```bash
cd E:/opensource/hanflow
git add hanflow/tools/builtin/code_exec.py tests/tools/test_code_exec.py
git commit -m "feat(tools): code_exec DOCKER path + mode vocab alignment

CodeExecServer accepts optional exec_interface (provisioner-injected).
Fallback error message aligned to Phase 8 (was Phase 7). mode string
vocab documented against SandboxMode enum."
```

---

## Task 9: charter-check + 全量回归 + 最终 smoke

**Files:** 无修改,验证性任务

**Why:** design 验收 #12/#13/#14 要求 charter-check 全绿 + 全量 pytest + core→isolation 反向 import 检查。

- [ ] **Step 1: 运行 charter-check --diff**

Run:
```bash
cd E:/opensource/hanflow-evolve
bash scripts/charter-check/run.sh --diff 2>&1 | tail -30
```
Expected: 0 违规(或仅 ADR-0005 豁免内的 isolation→observability 存量,清零截止 v1.1.0)

若有新增违规:
- core→isolation 反向 import: 严重,回 T2/T3 修
- 其它: 记录到 LEARNINGS

- [ ] **Step 2: 验证 core→isolation 反向 import 守护**

Run:
```bash
cd E:/opensource/hanflow
grep -rn "from hanflow.isolation" hanflow/core/ 2>&1
```
Expected: 空(core 不 import isolation)

- [ ] **Step 3: 运行全量 pytest**

Run: `cd E:/opensource/hanflow && python -m pytest -v 2>&1 | tail -50`
Expected: 全绿;DOCKER 契约测试在无 daemon 环境 SKIP 不报错

- [ ] **Step 4: 运行 ruff + mypy --strict**

Run:
```bash
cd E:/opensource/hanflow
python -m ruff check hanflow/ tests/
python -m mypy hanflow/ 2>&1 | tail -20
```
Expected: 0 errors / 0 warnings

- [ ] **Step 5: 运行 smoke test**

Run: `cd E:/opensource/hanflow && python -m pytest tests/test_smoke.py tests/test_e2e_v0.py -v`
Expected: PASS(默认 mode=local 行为不变)

- [ ] **Step 6: 提交 charter-check 证据(若有 ADR/白名单变动)**

若 charter-check 全绿无变动,无需 commit;若有 ADR/白名单更新:

```bash
cd E:/opensource/hanflow
git add docs/adr/ scripts/charter-check/
git commit -m "chore: charter-check green for cycle 2026-W30-1.1.1"
```

---

## DoD(完成定义)

- [ ] T1-T9 全部完成,每步都 commit
- [ ] 全量 pytest 全绿(DOCKER 契约测试无 daemon 时 SKIP)
- [ ] `ruff check` + `mypy --strict` 全绿
- [ ] `charter-check --diff` 全绿(无 core→isolation 反向 import)
- [ ] `tests/isolation/test_sandbox.py` 原 5 个 `RunSandbox.create` 调用点 0 改动
- [ ] dedicated_sandbox 契约单测守护(direction 验收 #8)
- [ ] `spawn_agent` 错误透传单测守护(SandboxTimeoutError 不降级)
- [ ] code_exec DOCKER 路径 + Phase 8 文案对齐
- [ ] pyproject.toml docker optional-extra + `all` 组合更新
- [ ] hanflow 仓库 git log 清晰(9 个原子 commit,conventional commits)

---

## Self-Review

**Spec coverage 核对**(对照 design.md 验收标准):

| design 验收 | 覆盖任务 |
|---|---|
| #1 core/sandbox_contract.py 定义全部类型 + Protocol | T2 |
| #2 charter-check layering(无 core→isolation) | T2(test) + T9(verify) |
| #3 RuntimeContext Protocol 不加 provisioned() | T6(注释说明) |
| #4 fake provisioner 测试覆盖 build_sandbox 全 4 档 | T6 |
| #5 现有 5 处 RunSandbox.create() 0 改动 | T3(test_type_identity) |
| #6 SandboxError 层级 + ToolWhitelistError | T1 |
| #7 core/__init__.py.__all__ 追加导出 | T2 |
| #8 dedicated_sandbox 契约单测(direction 验收 #8) | T3 |
| #9 spawn_agent 错误透传单测 | T3 |
| direction #6 code_exec Phase 7→8 文案对齐 | T8 |

**Placeholder scan**: 无 TBD/TODO,所有代码块完整。
**Type consistency**: `SandboxProvisioner/ProvisionedSandbox/ExecInterface` 全 plan 一致;`build_sandbox` 返回 `tuple[RunSandbox, ProvisionedSandbox]` 全 plan 一致。

---

## 执行选择

Plan 完成并保存。后续执行方式由 LOOP P8 code 阶段决定(主 session 用 subagent-driven-development 逐 task 派发,每 task 完成后 review)。
