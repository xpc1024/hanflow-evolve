# Design — DockerProvisioner 真实测试 CI 可见性与可靠性加固

| 元信息 | |
|---|---|
| cycle_id | `2026-W32-1.2.2` |
| 方向 | direction.md (Gate 1 已批准) |
| target_version | `1.2.3` (patch) |
| 是否涉及前端 | **否** (纯测试/CI 基础设施) |
| 运行时变更 | **零** (docker_provisioner.py 不动) |

## 架构定位

本设计**不触及任何运行时模块**。它是对 hanflow 的**测试基础设施层**的一次加固, 完全位于:
- 测试选择机制 (pytest markers)
- CI 编排 (`.github/workflows/ci.yml`)
- 开发者入口 (Makefile targets)
- 文档 (tests/isolation/)

不新增/迁移/修改任何 `hanflow/` 下的模块、Protocol、契约或错误层级。因此:
- 不触发 CHARTER §2 任何不变量
- 不需要 ADR (Layer-2 E 类已判定)
- 不影响 DSL→编译→执行三段式、per-run sandbox 契约、错误层级

## 现状基线 (经源码核实)

### 测试选择机制 — `pyproject.toml`
```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]
addopts = "-ra"
markers = [
    "integration: requires external services (postgres/redis/s3); skipped by default",
]
```
现有 marker 仅 `integration` (指 postgres/redis/s3 外部服务)。`test-unit` 用 `-m "not integration"` 排除它。

### CI — `.github/workflows/ci.yml` (现状)
```yaml
- run: docker pull python:3.11-slim
  continue-on-error: true        # ← 缺口 A: 静默退化源
- run: make test                 # ← 423 passed 里混着 4 个真实测试, 无独立可见性
```

### 测试文件 — `tests/isolation/test_docker_provisioner.py`
- 13 个测试函数: 5 build_config/name 单测 + 2 dep/mode + 2 storage-opt(mock) + **4 lifecycle(真实 daemon)**
- 4 个 lifecycle 测试仅带 `@skip_no_docker` (基于 `_docker_available()`: CLI + daemon + 本地镜像存在), 无 marker
- 本机无 daemon → 4 skipped; CI 有 daemon+镜像 → 13/13 全 pass

### Makefile (现状)
`test` / `test-unit` (`-m "not integration"`) / `test-cov` / `lint` / `typecheck` / `ci`。无 `test-docker`。

## 组件分解

### 改动 1: 注册 `docker` marker (`pyproject.toml`)
```toml
markers = [
    "integration: requires external services (postgres/redis/s3); skipped by default",
    "docker: needs a real docker daemon + python:3.11-slim image locally; "
    "auto-skipped via @pytest.mark.skipif when the daemon/image is absent",
]
```
- 语义边界: `docker` = 真实容器测试; `integration` = 外部服务 (pg/redis/s3)。两者正交, 一个测试可同时带两个标记 (本周期不涉及, 但语义允许)。

### 改动 2: 4 个 lifecycle 测试加 `@pytest.mark.docker`
在现有 `@skip_no_docker` 之外加 `@pytest.mark.docker`。**双标记并存**:
```python
@skip_no_docker
@pytest.mark.docker
@pytest.mark.asyncio
async def test_provision_real_container_lifecycle(tmp_path):
    ...
```
4 个测试:
1. `test_provision_real_container_lifecycle` (provision→exec→destroy)
2. `test_provision_resource_limits_enforced` (Memory 限额生效)
3. `test_destroy_removes_container` (destroy 后容器消失)
4. `test_exec_timeout_wrapped_as_sandbox_timeout` (exec 超时 → SandboxTimeoutError)

`skip_no_docker` 仍负责本机无 daemon 时的 skip (判定逻辑不变, 非目标已声明); `docker` marker 只负责"可选运行 + 可辨识"。

### 改动 3: Makefile 加 `test-docker` target
```makefile
.PHONY: install test test-unit test-docker test-cov lint typecheck ci

test-docker:
	uv run pytest -m docker -v
```
- `-v` 让每个 docker 测试名显式列出 (本机无 daemon 时显示 4 个 SKIPPED + reason)
- 不改 `test` (默认仍全跑, 行为不变)
- 加进 `.PHONY`

### 改动 4: CI 拆分测试报告 + 镜像缺失可见信号 (`ci.yml`)
```yaml
# 预拉镜像 (保留 continue-on-error, Docker Hub 不稳是现实)
- run: docker pull python:3.11-slim
  continue-on-error: true

# 显式镜像 gate: 拉取失败时发可见 warning, 不静默
- name: Verify docker image present
  run: |
    if ! docker image inspect python:3.11-slim >/dev/null 2>&1; then
      echo "::warning::python:3.11-slim missing — 4 real-container tests will SKIP; live container path NOT verified this run"
    else
      echo "python:3.11-slim present — real-container tests will run"
    fi

# 测试分两步显式报告 (修正 audit 轻微建议: 命名精确化)
- name: test (non-docker)
  run: uv run pytest -m "not docker" -ra
- name: test (docker, real daemon)
  run: uv run pytest -m docker -v
```
**设计决策 (关键)**:
- **不硬失败**: 镜像缺失只 `::warning::` (黄字, GitHub UI 可见), 不 `exit 1`。理由: Docker Hub 限流/不可达是抖动, 硬失败会阻断所有无关 PR; 但 warning 让退化从"完全看不见"变成"显式可见", 消除假绿陷阱。
- **测试总数不变**: `-m "not docker"` + `-m docker` 的合集 = 原 `make test` 的全集 (每个测试要么带 docker 要么不带), 总 passed 数 = 之前的单步数 (本机无 daemon 时 docker 桶全 skip, 与现状一致)。
- **命名精确化** (落实 audit 建议): 步骤名 `test (non-docker)` 而非 `test (unit)`, 因 `not docker` 桶含 unit + 非 docker 的 integration 测试, 标签须如实。

**退化矩阵**:
| 场景 | non-docker step | docker step | 结果 |
|---|---|---|---|
| CI 正常 (镜像在) | 全 pass | 4 passed | 全绿, 真实验证 ✓ |
| 镜像拉取失败 | 全 pass | 4 skipped + ::warning:: | 步骤仍绿, 但 UI 有黄字 warning ✓ (不再静默) |
| 本机开发 (无 daemon) | 全 pass | 4 skipped | `make test-docker` 显示 4 SKIPPED + reason |

### 改动 5: 文档 (`tests/isolation/README.md` 新建)
简短 README, 说明:
- 如何本地跑真实 docker 测试 (`make test-docker` 或 `pytest -m docker`)
- 前置: 安装 Docker Desktop 并启动 daemon; `docker pull python:3.11-slim`
- `docker` marker vs `integration` marker 语义区别
- 无 daemon 时这 4 个测试会 skip (设计如此, 非 bug)

## 接口契约

本设计**无运行时接口变更**。唯一的"接口"是开发者面向的 CLI 入口:

| 入口 | 命令 | 行为 |
|---|---|---|
| 全量测试 | `make test` | 不变 (全跑, 含/不含 docker 桶) |
| 仅 docker 真实测试 | `make test-docker` | 新增: `pytest -m docker -v` |
| CI non-docker | (CI 内部) | `pytest -m "not docker"` |
| CI docker | (CI 内部) | `pytest -m docker -v` |
| pytest marker 选择 | `pytest -m docker` / `-m "not docker"` | 新 marker 可用 |

## 数据流

```
开发者/CI → make test-docker / pytest -m docker
  → pytest 收集带 @pytest.mark.docker 的测试 (4 个)
  → 每个测试先经 @skip_no_docker 判定 (_docker_available: CLI+daemon+镜像)
    ├─ 条件不满足 → SKIPPED (reason: "no docker daemon or python:3.11-slim image")
    └─ 条件满足 → 真实跑 DockerProvisioner.provision → exec → destroy
  → -v 输出每个测试名 + PASSED/SKIPPED 状态

CI 退化路径:
  docker pull (continue-on-error)
    ├─ 成功 → image inspect gate 输出 "present" → docker step 跑 4 passed
    └─ 失败 → image inspect gate 输出 ::warning:: → docker step 4 skipped (可见)
```

## 错误处理

**与 HanflowError 层级的关系 (CHARTER §2 不变量 1)**: 本设计**零运行时改动**, 不新增、不修改、不捕获任何 `HanflowError` 子类。`DockerProvisioner` 运行时抛出的 `SandboxProvisionFailedError` / `SandboxDestroyFailedError` / `SandboxTimeoutError` / `SandboxDependencyMissingError` 全部保持不变, 它们的抛出路径、`code`、`retryable`、关联坐标 (run_id) 均不被本设计触碰。错误处理章节因此只描述**测试基建层面**的退化处理, 不涉及框架错误契约。

- **测试自身错误** (provision/exec/destroy 失败): 不变, 测试断言失败即该 step 红。本设计不改测试逻辑, 已有的真实测试覆盖了 `SandboxTimeoutError` (test_exec_timeout_wrapped_as_sandbox_timeout) 等错误路径, 这些断言保持原样。
- **镜像缺失 (缺口 A 的核心)**: `::warning::` + docker step 显示 skipped, 不硬失败 (设计决策: Docker Hub 限流是抖动, 硬失败会阻断所有无关 PR; 但 warning 让退化从静默变可见, 消除假绿)。这是**测试基建退化处理**, 非 HanflowError 范畴。
- **marker 未注册**: pyproject 同步注册 `docker` marker, 不会有 unknown-marker warning (pytest 注册即合规)。
- **本机无 daemon**: `skip_no_docker` (`_docker_available()` 返回 False) 原有 skip 逻辑保留, 行为不变。注意: 这里的 skip 是 pytest 机制, 不经过 HanflowError —— daemon 缺失是环境前置条件, 不是框架错误。

## 测试策略

本周期**即测试基建本身**, 其正确性由以下保证:
1. `make test` 总数不变 (marker 不增减测试, 只分组) —— 回归断言。
2. `pytest --markers` 列出 `docker` marker, 无 unknown-marker warning。
3. 本机 `pytest -m docker` 显示 4 个测试 (全 skipped, reason 明确); `pytest -m "not docker"` 显示其余全 pass。
4. CI 上 docker step 显示 4 passed (镜像在时)。
5. S0 门 (ruff/mypy/pytest) 全绿。

## 前端影响

**无**。不涉及 `web/`、`schema.py`、任何 UI/API。direction.md 影响模块无前端文件。

## 迁移兼容

- `make test` 行为不变 (默认全跑), 现有开发者工作流零影响。
- 现有 `@skip_no_docker` 保留, 不破坏本机 skip 语义。
- 新 `docker` marker 是纯增量, 不影响任何现有 marker (`integration`)。
- CI 总测试数不变, 只是拆成两个 step 报告。

## 文件清单 (执行期改动)

| 文件 | 改动 |
|---|---|
| `pyproject.toml` | markers 加 `docker` (2 行) |
| `tests/isolation/test_docker_provisioner.py` | 4 个测试各加 `@pytest.mark.docker` (4 行) |
| `Makefile` | 加 `test-docker` target + `.PHONY` 更新 (3 行) |
| `.github/workflows/ci.yml` | docker pull 后加 image-gate warning + 拆 test 为两步 (~12 行) |
| `tests/isolation/README.md` | 新建 (文档) |

**总计**: ~20 行代码/配置 + 1 个 README。零 `hanflow/` 运行时改动。
