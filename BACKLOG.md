# BACKLOG.md — hanflow-evolve 主题候选队列 (spec §7)

由 LOOP 的 signal + prioritization 阶段自动维护。每个候选**主题 (theme)** 是一个可独立
交付的演进单元, 对应一个 release。

## 优先级与 human_override

- 排序由 prioritization 阶段按 `config.yaml` 的 `source_weights` + `theme_weights` 计算
  得分自动产生。
- **human_override 优先**: 任何时候, 人类 (用户) 可以在 `## 待实现 (Pending)` 中给某条
  主题加 `[human_override]` 标记或调整顺序, LOOP 系统将**无条件优先**采用该主题作为下一
  cycle 的 `target_theme`, 不再受自动评分约束。
- 无 `[human_override]` 时, 队列顶部 (得分最高, 且与 `score_gap_for_tie` 不构成平局)
  的主题即下一候选。
- 已进入 `## 进行中 (In Progress)` 的主题被锁定, 不会被重新评分抢占。
- 暂缓 (`## 暂缓 (Deferred)`) 的主题不参与下轮评分, 直到人类移回 Pending。

---

## 待实现 (Pending)

> 按 prioritization 得分降序。每条建议字段: `[score] 主题 — 来源信号 / 备注`。
> 标注 `[human_override]` 的条目无条件优先。

(初始为空。首次 signal + prioritization 运行后填充。)

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
