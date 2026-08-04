# AUDIT — 设计文档自动审核 (max 版: 领域专家审核) (P3b / P4b)

> Forked-from: loop-evolve/references/audit.md
> 差异:Layer 2 从 generic 审核员升级为 design-reviewer 专家(带领域视角)。

## 适用阶段
- P3b: audit_direction(审核 direction.md)
- P4b: audit_design(审核 design.md)

## 两层审核

### Layer 1: 规则检查 (脚本, 零 token, 委托 loop-evolve 零改动)
```bash
# direction:
bash scripts/audit-rules-check.sh cycles/$CYCLE_ID/direction.md direction
bash scripts/charter-check/charter-check.sh --doc cycles/$CYCLE_ID/direction.md
# design:
bash scripts/audit-rules-check.sh cycles/$CYCLE_ID/design.md design
bash scripts/charter-check/charter-check.sh --doc cycles/$CYCLE_ID/design.md
```
退出 0 = 通过。

### Layer 2: 领域专家语义审核 (design-reviewer, fresh context)
读 `references/experts/design-reviewer.md`, 填占位符:
- {PAYLOAD} = direction.md(P3b)或 design.md(P4b)全文
- {CONTEXT} = direction 目标 + 影响模块
- {ROUTING} = direction 的 expert_routing 字段(决定叠加哪些领域视角)

用 Agent 工具(general-purpose)派发。专家按 5 类 checklist + 领域视角复核,
输出写入 audit-direction.md 或 audit-design.md。

## 结果处理
读 audit_retry_count(state-max.yaml):

IF 无严重问题(仅轻微建议):
  通过 → audit 摘要附文档末尾, 进 Gate

IF 有可自动修复的问题(缺章节/命名不一致):
  LOOP 自动修订文档
  audit_retry_count++
  IF <= 2: 重审
  ELSE: 带问题标注进 Gate

IF 有严重问题(违背架构约束/自相矛盾/历史冲突):
  回 P3/P4 修订(不占 audit_retry_count)

## 严重度判定
- 轻微 = B/D 类(缺章节、过度设计)→ 可自动补全
- 严重 = A/C/E 类(违背约束、自相矛盾、历史冲突)→ 必须回 P3/P4

## 产物
cycles/$CYCLE_ID/audit-direction.md 或 audit-design.md
