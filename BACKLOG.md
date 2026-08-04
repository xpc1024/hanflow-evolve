# BACKLOG.md — hanflow-evolve 主题候选队列 (spec §7)

由 LOOP 的 signal + prioritization 阶段自动维护。每个候选**主题 (theme)** 是一个可独立交付的演进单元, 对应一个 release。

> 自动生成于 2026-08-04T01:51:29+00:00 · 共 8 个候选主题 (cycle `2026-W32-1.2.2`)。

> 排序: `[human_override]` 主题无条件优先; 其余按 prioritization 得分降序。

---

## 待实现 (Pending)

> 按 prioritization 得分降序。标注 `[HUMAN]` 的条目为 human_override, 无条件优先。

### [1] Priorities from LEARNINGS.md · score 44 · minor · effort medium · risk low

- **theme_id**: `learnings-priority`
- **source**: `learnings`
- **member_signals**: `learning:1`, `learning:2`, `learning:3`, `learning:4`, `learning:5`, `learning:6`, `learning:7`, `learning:8`, `learning:9`, `learning:10`, `learning:11`, `learning:12`, `learning:13`, `learning:14`, `learning:15`

### [2] Complete source stubs in 'api' module · score 39 · patch · effort medium · risk low

- **theme_id**: `stub-api`
- **affected_modules**: `api`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/api/routes/observe.py:4`, `stub:E:/opensource/hanflow\hanflow/api/routes/observe.py:48`

### [3] Complete source stubs in 'memory' module · score 39 · patch · effort medium · risk low

- **theme_id**: `stub-memory`
- **affected_modules**: `memory`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/memory/filesystem.py:5`

### [4] Complete source stubs in 'tools' module · score 39 · patch · effort medium · risk low

- **theme_id**: `stub-tools`
- **affected_modules**: `tools`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/tools/builtin/vector_search.py:42`, `stub:E:/opensource/hanflow\hanflow/tools/builtin/web_search.py:42`, `stub:E:/opensource/hanflow\hanflow/tools/transport.py:75`

### [5] Complete source stubs in 'persistence' module · score 38 · patch · effort medium · risk low

- **theme_id**: `stub-persistence`
- **affected_modules**: `persistence`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:9`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:83`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:86`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:89`, `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:93`, `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:96`

### [6] Complete source stubs in 'isolation' module · score 37 · patch · effort medium · risk low

- **theme_id**: `stub-isolation`
- **affected_modules**: `isolation`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/isolation/sandbox.py:208`, `stub:E:/opensource/hanflow\hanflow/isolation/sandbox.py:214`, `stub:E:/opensource/hanflow\hanflow/isolation/sandbox.py:219`

### [7] Complete source stubs in 'observability' module · score 37 · patch · effort medium · risk low

- **theme_id**: `stub-observability`
- **affected_modules**: `observability`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/observability/provider.py:23`, `stub:E:/opensource/hanflow\hanflow/observability/provider.py:26`, `stub:E:/opensource/hanflow\hanflow/observability/trace.py:85`, `stub:E:/opensource/hanflow\hanflow/observability/trace.py:94`

### [8] Complete source stubs in 'runtime' module · score 37 · patch · effort medium · risk low

- **theme_id**: `stub-runtime`
- **affected_modules**: `runtime`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/runtime/build_sandbox.py:55`

---

## 进行中 (In Progress)

> 当前 cycle 锁定的主题。同一时刻最多 1 条 (单主题版本策略)。

(空)

---

## 已完成 (Done)

> 已合并到 main 并 release 的主题。保留简短记录 (cycle_id / 版本 / 主题 / 日期)。

- `2026-W32-1.2.2` · v1.2.3 · docker-provisioner-real-contract-tests(human_override) · 2026-08-04
  — DockerProvisioner 真实测试 CI 可见性加固: docker marker + make test-docker + CI 拆分报告 + 镜像缺失 ::warning:: (消除假绿陷阱) + tests/isolation/README。零运行时改动。P3 调研纠偏了 LEARNINGS #1 失效前提 (CI 实已验证真实容器路径)。
- `2026-W31-1.2.1` · v1.2.1 · clear-preexisting-tech-debt-s0-gates(human_override) · 2026-07-29
  — 清零 S0 三道门: ruff check 15→0 / ruff format 25 文件→clean / mypy 28→0; 集成贡献者 PR #5; 修 version-bump.sh 路径 bug。
- `2026-W30-1.1.1` · v1.2.0 · docker-sandbox(human_override) · 2026-07-21
  — DOCKER sandbox provisioner 落地(LocalProvisioner + DockerProvisioner + K8sProvisioner 占位 + build_sandbox 组合根)。

---

## 暂缓 (Deferred)

> 暂不处理的主题 (风险过高 / 等待外部依赖 / 优先级被压低)。人类可随时移回 Pending。

(空)
