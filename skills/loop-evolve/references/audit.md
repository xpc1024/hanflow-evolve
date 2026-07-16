# AUDIT — 设计文档自动审核 (P3b / P4b)

## 适用阶段
- P3b: audit_direction (审核 direction.md)
- P4b: audit_design (审核 design.md)

## 两层审核 (spec §4b.3)

### Layer 1: 规则检查 (脚本, 零 token)
```bash
# direction:
bash scripts/audit-rules-check.sh cycles/$CYCLE_ID/direction.md direction
# 文档契约检查（若 direction 涉及架构变更，须有 ADR 引用）：
bash scripts/charter-check/charter-check.sh --doc cycles/$CYCLE_ID/direction.md

# design:
bash scripts/audit-rules-check.sh cycles/$CYCLE_ID/design.md design
bash scripts/charter-check/charter-check.sh --doc cycles/$CYCLE_ID/design.md
```
退出 0 = 通过, 非 0 = 有缺失章节。
`charter-check --doc` 扫描文档中的架构变更信号（新增/迁移模块、改依赖等），
若命中却无 ADR 引用 → 输出 WARN（非 FAIL）；ADR 必要性由 Layer 2 的 E 类判定。

### Layer 2: 语义审核 (独立 subagent, fresh context)
用 Agent 工具派一个**未参与设计**的 subagent:

Agent prompt:
  你是设计文档审核员。审核以下文档, 按 5 类 checklist 逐项判定。

  文档: [文档内容]
  hanflow 设计约束: [LEARNINGS 框架架构模式区块内容]

  5 类 checklist (spec §4b.2):
  A. 架构合规性: 6层定位/Protocol-based/HanflowError-only/RuntimeContext注入/DSL单一真相源/LangGraph薄运行时
  B. 完整性: 覆盖direction全部目标/有错误处理/有测试策略/有迁移兼容/有非目标
  C. 自洽性: 接口输入输出匹配/组件依赖无环/数据流闭环/命名一致
  D. 复杂度控制: 无过度设计(YAGNI)/复杂度匹配主题
  E. 历史一致性: 不与LEARNINGS约束冲突/不与现有specs冲突

  输出格式 (写入 audit-<doc>.md):
  ## 审核结论
  - 整体: 通过/需修订 (N严重/M轻微)
  ## 逐项判定
  ### A. 架构合规性
  - [pass/fail] 检查项: 理由
  ...
  ## 建议修订
  1. (严重/轻微) 具体建议

## 结果处理 (spec §4b.4)

读 audit_retry_count (state.yaml):

IF 无严重问题 (仅轻微建议):
  通过 → audit 摘要附文档末尾, 进 Gate

IF 有可自动修复的问题 (缺章节/命名不一致):
  LOOP 自动修订文档
  audit_retry_count++
  IF <= 2: 重审
  ELSE: 带问题标注进 Gate

IF 有严重问题 (违背架构约束/自相矛盾):
  回 P3/P4 修订 (不占 audit_retry_count)

## 严重度判定
- 轻微 = B/D 类 (缺章节、过度设计) → 可自动补全
- 严重 = A/C/E 类 (违背约束、自相矛盾、历史冲突) → 必须回 P3/P4

## 产物
cycles/$CYCLE_ID/audit-direction.md 或 audit-design.md
