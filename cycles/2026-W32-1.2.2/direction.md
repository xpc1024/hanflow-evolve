# Direction — DockerProvisioner 真实测试 CI 可见性与可靠性加固

| 元信息 | |
|---|---|
| cycle_id | `2026-W32-1.2.2` |
| theme_id | `docker-provisioner-real-contract-tests` |
| target_version | `1.2.3` (patch) |
| source | `human_override` (P2b 用户选定, P3 调研后聚焦) |
| estimated_effort | small → medium |
| estimated_risk | low |
| version_impact | patch (纯测试/CI 基础设施, 零运行时行为变更) |

## 动机

**原始信号**: LEARNINGS #1 (高) — "在有 docker daemon 的环境实跑 DockerProvisioner 契约测试; 本 cycle (2026-W30-1.1.1) 4 个生命周期测试 skipif 跳过, 真实 container create/exec/destroy 路径未在 CI 验证"。

**P3 调研发现(关键, 修正了信号的前提)**:
- CI (`.github/workflows/ci.yml:20-22`) **已经** `docker pull python:3.11-slim` 并 `make test`。
- 最近一次 main 的 CI 运行 (run 30613595396) `test_docker_provisioner.py .............` **13/13 全 pass, 0 skip** —— 包含 4 个 `@skip_no_docker` 的真实生命周期测试 (provision→exec→destroy / 资源限额 / destroy 清理 / exec 超时)。
- 也就是说: **真实容器路径已经在 CI 被验证且全绿**, LEARNINGS #1 的描述已过时 (被后续 5 个 commit 6a3e487/88178fb/1490e2c/529e4da 等修复)。

**但是调研同时发现两个真实缺口**, 这才是本周期要做的事:

- **缺口 A — 静默退化**: `docker pull python:3.11-slim` 设了 `continue-on-error: true` (ci.yml:21)。一旦 Docker Hub 不可达或限流, 镜像拉取失败 → `_docker_available()` 返回 False → 4 个生命周期测试**静默 skip**, CI 仍然绿, **无人察觉真实容器路径不再被验证**。这是一个测试基础设施的"假绿"陷阱。
- **缺口 B — 可见性缺失**:
  - 4 个真实容器测试没有独立的 pytest 标记 (现有 markers 只有 `integration` 指 postgres/redis/s3), 无法用 `-m docker` 选择性运行或单独报告。
  - 它们和 419 个普通单测混在 `423 passed` 里, 无法从汇总数字看出"docker 真实测试是否跑了几个"。
  - 本机 (Windows, 无 docker daemon) 开发时, 这 4 个测试永远 skip, 但开发者看不到"本机少了哪些验证", 也无法方便地仅触发它们。

## 目标 (In Scope)

1. **消除静默退化 (缺口 A)**: 让 `docker pull` 失败**可见**而非静默吞掉。CI 必须能区分"docker 真实测试 pass 了"和"docker 真实测试因为镜像没拉到而 skip 了"——后者应让 CI 步骤显式告警(非硬失败, 但写进 summary/可见信号), 避免"假绿"。
2. **建立 docker 测试标记体系 (缺口 B)**:
   - 新增 pytest marker `docker` (语义: "需要真实 docker daemon 才有意义, 非 skip 即真跑")。
   - 4 个生命周期测试打上 `@pytest.mark.docker` (与现有 `skip_no_docker` 并存, skip_no_docker 仍负责本机无 daemon 时的 skip)。
   - `make test` 默认全跑 (行为不变); 新增 `make test-docker` / `pytest -m docker` 仅跑这批; CI 单独步骤跑 `-m docker` 并在 step 名/输出里显式报告数量。
3. **CI 报告可见性**: CI 里把 docker 真实测试拆成显式可见的一步 (或在 `make test` 后加一个 `-m docker -v` 的只读汇报), 让"4 个真实容器测试跑了几个/pass 几个"从汇总里可读。
4. **文档**: 在 `tests/isolation/` 加简短 README 段或 docstring, 说明本地如何跑真实 docker 测试 (装 Docker Desktop / `make test-docker`), 以及 `docker` marker 与 `integration` marker 的区别。

## 非目标 (Out of Scope)

- ❌ 不改 `DockerProvisioner` / `_DockerExec` 的运行时行为 (provision/destroy/exec 逻辑不动)。
- ❌ 不引入 K8s 真实测试 (K8sProvisioner 仍是占位, 另一主题)。
- ❌ 不为其它 provisioner (Local/K8s) 加真实集成测试 (本周期只聚焦 docker)。
- ❌ 不做定制镜像构建流水线 (LEARNINGS #8, 另一主题)。
- ❌ 不改 `_docker_available()` 探测逻辑的判定条件 (CLI + daemon + 本地镜像存在, 这个逻辑正确, 保留)。

## 实现路径 (Options + 推荐)

### 选项 1: 纯 marker + CI step 拆分 (推荐 ✅)

- `pyproject.toml` markers 加 `"docker: needs a real docker daemon + python:3.11-slim image"`。
- 4 个 lifecycle 测试加 `@pytest.mark.docker` (双标记: skip_no_docker + docker)。
- `Makefile` 加 `test-docker: uv run pytest -m docker -v`。
- CI: `docker pull` 后, 把 `make test` 拆为两步显式汇报:
  - 步骤 `test (unit, no daemon needed)`: `pytest -m "not docker"` (其实也含单测, 保证本机语义)。
  - 步骤 `test (docker integration, real daemon)`: `pytest -m docker -v`, 输出里能看到具体跑了几条。
  - `docker pull` 保持 `continue-on-error: true` (Docker Hub 不稳是现实), **但**在 docker 测试步骤前加一个**显式 gate**: 若 `docker image inspect python:3.11-slim` 失败, 则 `echo "::warning::docker image missing — 4 real-container tests will SKIP and CI will not verify the live container path"` 并 `exit 1` (可选, 见下)。
- **静默退化处理**: 推荐 `::warning::` + step summary 写明 "0/4 docker tests ran", 不硬失败 (避免 Docker Hub 抖动阻断所有 PR); 但让退化从"完全看不见"变成"GitHub UI 里有黄字 warning + summary 计数"。

**优点**: 最小改动, 纯测试基建, 风险极低, 直接命中两个缺口。
**缺点**: `::warning::` 仍可能被忽略 (但比完全静默好得多)。

### 选项 2: 选项 1 + 独立 docker CI job (matrix)

- 选项 1 全部 + 把 docker 测试挪到**独立的 job** (`job: docker-tests`, 依赖 `services.docker` 或直接用 ubuntu-latest 自带 daemon), 与 unit test job 并行。
- docker pull 失败时该 job 显式 fail (因为这是 docker job 的唯一职责, 没有其它测试能掩盖)。

**优点**: 可见性最强, docker 测试有独立的状态指示灯。
**缺点**: 多一个 job, CI 时间略增; 对当前规模 (4 个测试, 9 秒总量) 可能过重。

### 选项 3: testcontainers / 测试隔离增强

- 引入 testcontainers-python 管理测试容器生命周期, 每个测试独立容器前缀, 避免并发 run_id 冲突。

**优点**: 更健壮。
**缺点**: 引入新依赖, 超出"加固可见性"的范围; 现有 run_id 已用 `tmp_path.name` 隔离, 无实际并发问题。**不推荐**。

### 推荐: 选项 1

理由: 本周期是 patch + 测试基建, 选最小、最低风险、直接命中缺口的方案。若未来 docker 测试数量增长到需要独立 job, 再升到选项 2 (渐进)。

## 影响模块

| 模块 | 文件 | 改动类型 |
|---|---|---|
| CI | `.github/workflows/ci.yml` | docker pull 后加显式 image-gate warning; 拆 test 汇报 |
| 测试基建 | `pyproject.toml` (`[tool.pytest.ini_options].markers`) | 加 `docker` marker |
| 测试 | `tests/isolation/test_docker_provisioner.py` | 4 个 lifecycle 测试加 `@pytest.mark.docker` |
| 构建 | `Makefile` | 加 `test-docker` target |
| 文档 | `tests/isolation/` (README 或 docstring) | 说明本地如何跑 + marker 语义 |

**运行时代码**: 零改动 (`docker_provisioner.py` 不动)。

## 风险评估

| 风险 | 等级 | 缓解 |
|---|---|---|
| 改 CI 导致 PR 被 docker 测试 flaky 阻塞 | 低 | docker pull 保持 continue-on-error; 测试步骤默认 warning 不硬失败 (选项 1) |
| 新 marker 与现有 `integration` 语义混淆 | 低 | docstring 明确: `docker`=真实 daemon 容器测试; `integration`=外部服务(pg/redis/s3) |
| marker 注册遗漏触发 pytest unknown-marker warning | 低 | pyproject markers 同步注册 |
| Windows 本机无 daemon, 无法本地验证 4 个测试真的 pass | 中 | 本机验证 marker/skip 行为 (`-m docker` 显示 4 skipped); 真实 pass 依赖 CI (本就如此) |

## 验收标准

1. ✅ `pyproject.toml` 注册了 `docker` marker, `pytest --markers` 列出它, 无 unknown-marker warning。
2. ✅ 4 个真实生命周期测试 (`test_provision_real_container_lifecycle` / `test_provision_resource_limits_enforced` / `test_destroy_removes_container` / `test_exec_timeout_wrapped_as_sandbox_timeout`) 带 `@pytest.mark.docker`。
3. ✅ `make test-docker` 存在; 本机跑 `pytest -m docker` 显示这 4 个测试 (无 daemon 则 4 skipped, reason 明确)。
4. ✅ CI 的 docker 测试结果**可单独辨识**: 要么独立 step 输出 `N passed`, 要么 step summary 写明 docker 测试计数。
5. ✅ `docker pull` 失败时, CI 有**可见信号** (`::warning::` + summary), 不再完全静默。
6. ✅ S0 门全绿: `ruff check` / `ruff format --check` / `mypy` / `pytest` (含新标记后总数不变, 仍 ≥423 passed, 本机 docker 测试合理 skip)。
7. ✅ `tests/isolation/` 有文档说明本地跑 docker 测试的方式。
8. ✅ LEARNINGS #1 更新为"已完成/已加固" (消除过时信号), 避免下个 cycle 再次误选。
