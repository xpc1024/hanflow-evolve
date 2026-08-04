# Test Report — cycle 2026-W32-1.2.2

| 元信息 | |
|---|---|
| cycle_id | `2026-W32-1.2.2` |
| 分支 | `evolve/2026-W32-1.2.2` (hanflow repo) |
| 运行环境 | Windows, 本机**无 docker daemon** (Docker Desktop 未运行) |
| 时间 | 2026-08-04 |

## S0 门 (make ci 等价)

### 1. lint (`ruff check` + `ruff format --check`)
```
All checks passed!
200 files already formatted
```
**结果: ✅ PASS** (0 错)

### 2. typecheck (`mypy hanflow --strict`)
```
Success: no issues found in 114 source files
```
**结果: ✅ PASS** (0 issue; 本周期零运行时改动, 天然绿)

### 3. test (`pytest` 全量)
```
419 passed, 5 skipped, 2 warnings in 13.62s
```
**结果: ✅ PASS**

skip 明细 (5 个, 全部预期内):
- 4 × `tests/isolation/test_docker_provisioner.py` — `no docker daemon or python:3.11-slim image` (本周期加的 `@pytest.mark.docker` 测试, 本机无 daemon, 设计如此)
- 1 × `tests/persistence/test_integration.py` — `set HANFLOW_INTEGRATION=1` (pre-existing, 非本周期能力)

**与基线对照**: CI (有 daemon) 上次 `423 passed, 1 skipped`。本机 419 + 5 = (423 - 4 docker) + (1 + 4 docker skip) = 完全自洽, 零回归。

## 架构契约守护

### charter-check --diff (增量守门)
```
OK: errors passed (scanned 0 files)
OK: registry passed (scanned 0 files)
OK: pydantic-data passed (scanned 0 files)
OK: async-api passed (scanned 0 files)
OK: layering passed (scanned 0 files)
=== charter-check: exit 0 ===
```
**结果: ✅ PASS** (0 hanflow/ 运行时文件被改, 架构契约天然未触碰)

## marker 体系验证 (本周期核心交付)

### docker marker 注册
```
$ pytest --markers | grep docker
@pytest.mark.docker: needs a real docker daemon + python:3.11-slim image locally;
auto-skipped via @pytest.mark.skipif when the daemon/image is absent
```
✅ 注册成功

### 选择性运行
```
$ pytest tests/isolation/test_docker_provisioner.py -m docker --co -q
4/13 tests collected (9 deselected)        ← 正好 4 个 lifecycle

$ pytest tests/isolation/test_docker_provisioner.py -m "not docker" --co -q
9/13 tests collected (4 deselected)        ← 其余 9 个

$ pytest tests/isolation/test_docker_provisioner.py --co -q
13 tests collected                          ← 守恒: 9 + 4 = 13 = 全集
```
✅ 选择正确, 计数守恒

### 退化验证 (本机无 daemon)
```
$ pytest -m docker -v
SKIPPED [1] test_docker_provisioner.py:306: no docker daemon or python:3.11-slim image
SKIPPED [1] test_docker_provisioner.py:341: no docker daemon or python:3.11-slim image
SKIPPED [1] test_docker_provisioner.py:378: no docker daemon or python:3.11-slim image
SKIPPED [1] test_docker_provisioner.py:412: no docker daemon or python:3.11-slim image
4 skipped, 420 deselected
```
✅ 4 个测试可辨识 + reason 明确 (不再是埋在总数里的不可见项)

### unknown-marker 检查
```
$ pytest --co -q 2>&1 | grep -i "unknown marker"
(no output — 无 unknown marker warning)
```
✅ pyproject 注册与测试装饰器拼写一致

## CI yaml 验证 (本地静态)
```
$ python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"
(无异常, 语法合法)
steps: docker pull → Verify docker image present → test (non-docker) → test (docker, real daemon)
```
✅ 语法合法, image-gate + 两步拆分就位
(注: 真实 CI 运行需推 branch, GitHub Actions 验证; 本地已尽静态验证)

## smoke test (行为化验证)
```
PASS [1/4] hanflow importable
PASS [2/4] DSL validation works
PASS [3/4] static workflow with FakeProvider
PASS [4/4] API app buildable
=== smoke-test: 0 failure(s) ===
```
**结果: ✅ 4/4 PASS**

## 前端验证
N/A — 本周期不涉及前端 (direction 影响模块无 web/ 文件)。

## 结论

| 检查项 | 结果 |
|---|---|
| S0 lint | ✅ PASS |
| S0 typecheck | ✅ PASS |
| S0 test | ✅ PASS (419 passed, 5 expected skip, 0 fail) |
| charter-check --diff | ✅ PASS (0 运行时文件) |
| marker 体系 | ✅ 注册/选择/守恒/退化/无 warning 全验证 |
| CI yaml | ✅ 语法合法 (真实运行待 CI) |
| smoke | ✅ 4/4 PASS |
| 前端 | N/A |

**整体: ✅ 全部门通过, 零回归, 可进 Gate 3。**

retry_count: 0 (无需 auto-fix)。
