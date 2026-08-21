# Execution Plan — 2026-W34-1.2.4 · loop-toolchain-state-sync-and-signal-filter

- **上游**: design.md (Gate 2 approved, P4b 复核 0/0)
- **date**: 2026-08-20

## 任务列表 (原子化, 单 commit/任务)

### Task 1 — 新增过滤 bats 用例 (TDD 红)
- 文件: `tests/test-signal-gather.bats` 追加 `@test "filters completed (strikethrough) LEARNINGS entries"`
- fixture: fake-evolve/LEARNINGS.md「## 下次优先」5 条 (条目 1/2/5 行首 `~~` → 跳过; 3/4 保留; 4 为边界—正文含「已修」)
- config: `signals.learnings: {enabled: true}`, github/source_stubs/competitor 全关 (learnings 计数即总数)
- 断言: 总数 == 2; 无信号 text 以 `~~` 开头; 边界条目在结果中; id 连续 learning:1, learning:2
- 验证: 用例失败 (过滤未实现, 采集 5 条 ≠ 2) → 红

### Task 2 — 实现 collect_learnings 行首 `~~` 过滤 (TDD 绿)
- 文件: `scripts/signal-gather.sh` `collect_learnings()` L245-248 区
- 变更: `body = lm.group(1).strip()` 判空后加:
  ```python
  if body.startswith("~~"):
      continue
  ```
- 验证: Task 1 用例转绿; 既有 3 个 signal-gather 用例不回归

### Task 3 — 重采本周期 signals.json (自证)
- 运行: `bash scripts/signal-gather.sh . 2026-W34-1.2.4` (此时 LEARNINGS **尚未销账**)
- 断言: learnings 信号 == 11 (19 − 8 行首划线); source_stub 20 不变; 总数 31
- 顺带: score-signals + update-backlog 重跑, BACKLOG learnings-priority 得分回落观察记录

### Task 4 — LEARNINGS 销账
- 「下次优先」#1 (version-bump state 同步) / #2 (signal-gather 过滤): 行首加 `~~` + `✓ 已完成 (2026-W34-1.2.4)` 标注
- #3 内滞留已完成子项核对 (version-bump 路径 bug / score-signals 已划线, 仅核对)
- 评估 #9-13 (direction audit 遗留建议②): 物理删除已划线条目 → 决定: 保留划线 (audit 建议仅"评估", 划线条目已被采集端过滤, 物理删除无增量收益且丢历史)

### Task 5 — 全量回归
- `bats tests/` 全部
- `pytest tests/test-score-signals.py`
- 重点确认: `test-version-bump.bats` (state 回写, direction 目标 4) 绿

## 依赖顺序 (Task DAG)

```
T1 (红) → T2 (绿) → T3 (重采自证) → T4 (销账, 必须在 T3 后) → T5 (全量回归)
```

关键约束 (design 组件分解): **T4 必须在 T3 之后** — 销账会给 #1/#2 加行首 `~~`,
先销账则重采得 9 条, 验收的 11 条对应销账前快照。

## 测试计划

| 层 | 用例 | 期望 |
|----|------|------|
| 单元 (bats) | 新增过滤用例 3 类断言 | T2 后绿 |
| 回归 (bats) | 既有 3 个 signal-gather 用例 + 全部其他 *.bats | 全绿 |
| 回归 (pytest) | test-score-signals.py | 全绿 |
| 行为 (端到端) | 重采 signals.json: learnings 19→11, 总数 39→31 | T3 验证 |
| 行为 (下周期推演) | BACKLOG 重排后 learnings-priority 不再虚高 44 | T3 观察记录 |

## 完成定义 (DoD)

1. Task 1-5 全部 commit, 工作区干净
2. 全套测试绿 (bats + pytest, 含新增用例)
3. signals.json learnings == 11, 无行首 `~~` 条目
4. LEARNINGS #1/#2 已销账 (带 2026-W34-1.2.4 标注)
5. hanflow 仓库零提交 (`git -C E:/opensource/hanflow status` 干净)
6. 每 Task 一个 commit, message 前缀 `cycle(2026-W34-1.2.4):`
