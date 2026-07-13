# BACKLOG.md — hanflow-evolve 主题候选队列 (spec §7)

由 LOOP 的 signal + prioritization 阶段自动维护。每个候选**主题 (theme)** 是一个可独立交付的演进单元, 对应一个 release。

> 自动生成于 2026-07-13T02:51:06+00:00 · 共 3 个候选主题 (cycle `init-scan`)。

> 排序: `[human_override]` 主题无条件优先; 其余按 prioritization 得分降序。

---

## 待实现 (Pending)

> 按 prioritization 得分降序。标注 `[HUMAN]` 的条目为 human_override, 无条件优先。

### [1] Priorities from LEARNINGS.md · score 44 · minor · effort medium · risk low

- **theme_id**: `learnings-priority`
- **source**: `learnings`
- **member_signals**: `learning:1`, `learning:2`, `learning:3`, `learning:4`, `learning:5`

### [2] Complete source stubs in 'E:' module · score 38 · patch · effort medium · risk low

- **theme_id**: `stub-E:`
- **affected_modules**: `E:`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/api/routes/observe.py:4`, `stub:E:/opensource/hanflow\hanflow/api/routes/observe.py:48`, `stub:E:/opensource/hanflow\hanflow/isolation/sandbox.py:15`, `stub:E:/opensource/hanflow\hanflow/isolation/sandbox.py:71`, `stub:E:/opensource/hanflow\hanflow/memory/filesystem.py:5`, `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:9`, `stub:E:/opensource/hanflow\hanflow/tools/builtin/code_exec.py:47`, `stub:E:/opensource/hanflow\hanflow/tools/builtin/vector_search.py:42`, `stub:E:/opensource/hanflow\hanflow/tools/builtin/web_search.py:42`, `stub:E:/opensource/hanflow\hanflow/observability/provider.py:23`, `stub:E:/opensource/hanflow\hanflow/observability/provider.py:26`, `stub:E:/opensource/hanflow\hanflow/observability/trace.py:85`, `stub:E:/opensource/hanflow\hanflow/observability/trace.py:94`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:83`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:86`, `stub:E:/opensource/hanflow\hanflow/persistence/checkpoint.py:89`, `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:93`, `stub:E:/opensource/hanflow\hanflow/persistence/resume.py:96`, `stub:E:/opensource/hanflow\hanflow/tools/transport.py:75`

### [3] CLI command completion (stub delegation to SDK) · score 35 · patch · effort medium · risk low

- **theme_id**: `cli-completion`
- **affected_modules**: `E:`
- **source**: `source_stub`
- **member_signals**: `stub:E:/opensource/hanflow\hanflow/cli/main.py:136`

---

## 进行中 (In Progress)

> 当前 cycle 锁定的主题。同一时刻最多 1 条 (单主题版本策略)。

(空)

---

## 已完成 (Done)

> 已合并到 main 并 release 的主题。保留简短记录 (cycle_id / 版本 / 主题 / 日期)。

(空)

---

## 暂缓 (Deferred)

> 暂不处理的主题 (风险过高 / 等待外部依赖 / 优先级被压低)。人类可随时移回 Pending。

(空)
