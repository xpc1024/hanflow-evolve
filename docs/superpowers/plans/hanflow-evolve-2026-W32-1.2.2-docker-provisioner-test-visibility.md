# Execution Plan — DockerProvisioner 测试 CI 可见性加固

| 元信息 | |
|---|---|
| cycle_id | `2026-W32-1.2.2` |
| design | design.md (Gate 2 已批准) |
| 改动规模 | ~20 行配置 + 1 README, 5 个文件 |
| 预计 | 全部 < 1h (无运行时逻辑, 纯配置/标记/CI) |

## 任务列表 (原子化, 单 commit / Task)

任务依赖为线性 (改动小, 无并行必要)。每 Task = 1 个独立改动点。

### Task 1: 注册 `docker` marker (pyproject.toml)
- **文件**: `pyproject.toml`
- **改动**: `[tool.pytest.ini_options].markers` 列表追加:
  ```toml
  "docker: needs a real docker daemon + python:3.11-slim image locally; auto-skipped via @pytest.mark.skipif when the daemon/image is absent",
  ```
- **验证**:
  - `uv run pytest --markers | grep docker` 列出新 marker
  - `uv run pytest --co -q` 无 unknown-marker warning (此时还没测试用它, 仅注册)
- **DoD**: marker 注册成功, markers 列表含 docker, 无 warning

### Task 2: 4 个 lifecycle 测试加 `@pytest.mark.docker`
- **文件**: `tests/isolation/test_docker_provisioner.py`
- **改动**: 4 个函数各加一行装饰器 (在现有 `@skip_no_docker` 之外):
  - `test_provision_real_container_lifecycle`
  - `test_provision_resource_limits_enforced`
  - `test_destroy_removes_container`
  - `test_exec_timeout_wrapped_as_sandbox_timeout`
  ```python
  @skip_no_docker
  @pytest.mark.docker       # ← 新增
  @pytest.mark.asyncio
  async def test_provision_real_container_lifecycle(tmp_path):
  ```
- **验证** (本机无 daemon):
  - `uv run pytest tests/isolation/test_docker_provisioner.py -m docker -v` → 显示这 4 个测试名 + SKIPPED (reason: no docker daemon or python:3.11-slim image)
  - `uv run pytest tests/isolation/test_docker_provisioner.py -m "not docker" -v` → 显示其余 9 个测试 + PASSED (无 lifecycle)
  - `uv run pytest tests/isolation/test_docker_provisioner.py -v` (全跑) → 13 个, 9 passed + 4 skipped (总数不变)
- **DoD**: marker 选择正确分组, 总测试数 13 不变, 4 个 lifecycle 在 -m docker 下可辨识

### Task 3: Makefile 加 `test-docker` target
- **文件**: `Makefile`
- **改动**:
  - `.PHONY` 行加 `test-docker`
  - 在 `test-unit` target 后加:
    ```makefile
    test-docker:
    	uv run pytest -m docker -v
    ```
- **验证**:
  - `make test-docker` → 本机显示 4 个 SKIPPED + reason (无 daemon)
  - `make test` 仍全跑 (行为不变, 回归断言)
- **DoD**: target 可用, make test 行为不变

### Task 4: CI 拆分测试报告 + 镜像缺失可见信号
- **文件**: `.github/workflows/ci.yml`
- **改动**: 把现有
  ```yaml
  - run: docker pull python:3.11-slim
    continue-on-error: true
  - run: make test
  ```
  改为:
  ```yaml
  - run: docker pull python:3.11-slim
    continue-on-error: true
  - name: Verify docker image present
    run: |
      if ! docker image inspect python:3.11-slim >/dev/null 2>&1; then
        echo "::warning::python:3.11-slim missing — 4 real-container tests will SKIP; live container path NOT verified this run"
      else
        echo "python:3.11-slim present — real-container tests will run"
      fi
  - name: test (non-docker)
    run: uv run pytest -m "not docker" -ra
  - name: test (docker, real daemon)
    run: uv run pytest -m docker -v
  ```
- **验证**:
  - 本地无法直接跑 GitHub Actions, 但可用 `act` 或直接推 branch 看 CI
  - 逻辑验证: yaml 语法正确 (yamllint 或 python yaml.safe_load)
  - 退化矩阵自洽 (设计 §退化矩阵)
- **DoD**: ci.yml 语法合法, image-gate + 两步拆分就位, make test 总集不变

### Task 5: tests/isolation/README.md 文档
- **文件**: `tests/isolation/README.md` (新建)
- **改动**: 简短 README (~30 行):
  - 本目录测试什么 (sandbox 隔离: Local/Docker/K8s provisioner)
  - 如何跑全部: `make test` / `pytest tests/isolation/`
  - 如何仅跑 docker 真实测试: `make test-docker` / `pytest -m docker`
  - 前置: Docker Desktop 运行 + `docker pull python:3.11-slim`
  - 无 daemon 时 4 个 lifecycle 测试会 SKIPPED (设计如此, 非 bug)
  - `docker` marker vs `integration` marker 语义区别
- **验证**: markdown 渲染正常, 命令与 Makefile/实际 marker 一致
- **DoD**: 文档准确, 命令可复制粘贴运行

## Task DAG (依赖顺序)

```
Task 1 (marker 注册) ──┐
                       ├─→ Task 2 (测试用 marker) ──→ Task 3 (Makefile) ──→ Task 4 (CI) ──→ Task 5 (文档)
                       │                              (依赖 marker 存在)     (依赖 marker)     (汇总)
                       └─ (Task 2 依赖 Task 1: marker 必须先注册否则 unknown warning)
```
线性执行: 1 → 2 → 3 → 4 → 5。Task 1 必须先于 2 (否则 pytest unknown marker warning)。

## 完成定义 (DoD — 整体)

1. ✅ 5 个 Task 全部完成, 每个有独立 commit (遵循 conventional commits)
2. ✅ S0 门全绿:
   - `make lint` (ruff check + format --check) 0 错
   - `make typecheck` (mypy hanflow) 0 错 (本不涉及运行时, 应天然绿)
   - `make test` 通过, 总数 ≥ 当前基线 (以实测为准, design audit 已提示基线可能 423/424)
3. ✅ marker 体系可验证:
   - `pytest --markers` 含 docker
   - `pytest -m docker --co -q` 列出 4 个测试
   - 无 unknown-marker warning
4. ✅ LEARNINGS #1 更新为"已加固" (消除过时信号, 防下周期误选)
5. ✅ 本机退化正确: 无 daemon 时 `pytest -m docker` 显示 4 SKIPPED + 明确 reason
6. ✅ charter-check --diff GREEN (运行时零改动, 应天然过)

## 测试计划

本周期**即测试基建**, 测试策略侧重验证 marker 选择行为正确:

| 验证点 | 命令 | 期望 (本机无 daemon) |
|---|---|---|
| marker 注册 | `pytest --markers \| grep docker` | 列出 docker marker |
| 选择 docker 桶 | `pytest -m docker --co -q` | 4 个 lifecycle 测试名 |
| 选择 not docker 桶 | `pytest -m "not docker" --co -q tests/isolation/test_docker_provisioner.py` | 9 个测试名 |
| 总数守恒 | `pytest tests/isolation/test_docker_provisioner.py --co -q \| wc -l` | 13 |
| 无 unknown warning | `pytest --co -q 2>&1 \| grep -i "unknown marker"` | 空 |
| make test-docker | `make test-docker` | 4 SKIPPED + reason |
| S0 lint | `make lint` | All checks passed |
| S0 typecheck | `make typecheck` | Success (0 errors) |
| S0 test | `make test` | 全 pass (lifecycle skip), 总数不降 |

## 风险与缓解
- **CI yaml 语法错误**: 用 `python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` 预检; 推 branch 验证
- **marker 大小写/拼写不一致**: pyproject 注册名与测试装饰器名必须完全一致 (`docker`), 复制粘贴避免手误
- **本机无法验证 CI 真实跑 4 个测试**: 这是已知约束 (本机无 daemon); 推 branch 后 GitHub Actions 会验证; 设计已预期
