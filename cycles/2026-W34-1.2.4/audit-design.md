# Design Audit — 2026-W34-1.2.4 · loop-toolchain-state-sync-and-signal-filter

- **审核对象**: cycles/2026-W34-1.2.4/design.md
- **上游**: direction.md (Gate 1 已批准)
- **审核日期**: 2026-08-20 (round 1 + round 2 复核)
- **核实材料**: scripts/signal-gather.sh、tests/test-signal-gather.bats、
  cycles/2026-W34-1.2.4/signals.json、LEARNINGS.md、tests/ 目录清单

## 审核结论

- **整体: 通过 (0 严重 / 0 轻微)** — A/B/C/D/E 五类全 pass
- round 1 判「需修订 (2 严重 / 2 轻微)」, 4 条建议全部落实并经 round 2 逐条复核
  确认解决 (见文末修订记录); 修订未引入新问题。

## 逐项判定

### A. 架构合规性

- **[pass] 组件分解全部落在 hanflow-evolve 侧, hanflow 零改动属实**: 组件表 5 项
  (scripts/signal-gather.sh、tests/test-signal-gather.bats、LEARNINGS.md、
  cycles/2026-W34-1.2.4/signals.json、tests/test-version-bump.bats) 经逐一核实均
  存在于 hanflow-evolve 仓库, 无一落入 hanflow 六层 (dsl/core/api/runtime/tools/
  observability)。信号采集端是管道最上游, score-signals.py / update-backlog.sh
  零改动, 与 direction 影响模块表逐行对应。

### B. 完整性

- **[pass] direction 6 项目标全覆盖**: 目标 1→接口契约; 2→测试策略 3 类用例
  (fixture 条目 1/2/5 跳过、3 保留、4 边界保留); 3→数据流+自证重采组件;
  4→回归确认组件+知识库销账; 5→「清理滞留已完成子项」; 6→回归段 (全量 bats +
  pytest test-score-signals.py, 该文件经核实存在)。验收对照表 6 行完整。
- **[pass] 错误处理/测试策略/迁移兼容三章齐备**: 错误处理覆盖文件缺失、无段、
  body 空、过滤后全空四类分支, 且逐条与源码现状吻合 (signal-gather.sh L225-233
  确为缺失/无段返回 `[]`)。
- **[pass] 非目标与 direction out-of-scope 一致**: 无 score-signals 消费端过滤、
  无 BACKLOG 改造、无 hanflow 改动、LEARNINGS 仅动「下次优先」段, 四项均未越界。

### C. 自洽性

- **[pass] 新用例断言与 fixture 一致 (round 2 修订后)**: 断言「learnings 信号
  总数 == 2 (fixture 条目 3/4 两条待办保留)」与 fixture 标注 (1/2/5 跳过、3/4
  保留)、「id 连续重编号 learning:1, learning:2」三处互相一致。round 1 的
  「== 3」矛盾已消除。
- **[pass] 执行顺序约束已显式声明, 表序与数据流断言一致 (round 2 修订后)**:
  组件分解表前新增「先重采、后销账」约束 (含反例推演: 先销账则 9 条 ≠ 11,
  经实测数据 19−8−2=9 验证正确); 表格顺序列为 过滤器→测试→重采(注明「此时
  LEARNINGS 尚未销账, 预期 11 条」)→销账→回归, 数据流 19→11 在该顺序下必然
  成立。销账步补充「此后下周期 scan 它们亦被过滤」的推演亦正确。
- **[pass] 代码变更片段与实际源码插入点吻合**: 现状片段 (body 取值 → 判空
  continue → idx+=1) 与 signal-gather.sh 实际代码逐字符一致; 插入点 (body 判空后、
  idx+=1 前) 正确实现「跳过且不占用 learning:N 编号」; 接口契约引用 L245-248 与
  实际行号 (body= 在 245、判空 246-247、idx+=1 在 248) 精确吻合, 组件分解
  L217-258 函数边界亦准确 (round 2 已校准)。
- **[pass] 19→11 数据流经实测复核成立**: 脚本统计 signals.json — learnings 共
  19 条, 行首 `~~` 8 条 (learning:4/5/7/12/13/14/15/16), 过滤后 11 条, 与
  direction 验收 #2 (19−8=11) 及动机段引用的条目号完全一致。
- **[pass] learnings 开关配置与计数口径正确 (round 2 修订后)**: 源码 main() 读
  `signals.learnings.enabled` (L329) + `learning.learnings_file` (L330, 默认
  LEARNINGS.md 相对 evolve_home); 设计已补 config 要点「signals.learnings:
  {enabled: true} 且其他信号源全部关闭, 使 learnings 计数即 signals 总数」,
  与源码配置键及 bats 现有用例 YAML 写法吻合, 口径歧义消除。

### D. 复杂度控制

- **[pass] 改动量与主题量级匹配, 无过度设计**: 核心改动为 2 行插入
  (`if body.startswith("~~"): continue`), 即 direction 所称「1 行级」; 测试仅
  1 个 @test 含 3 类断言。未引入可配置开关、未动 schema、未做消费端双卡过滤
  (direction 路径 C 已否决)、未投机覆盖 ✓-only 格式 (direction 风险 2 决策)。
  fixture 5 条还顺带覆盖有序 (`1. `)/无序 (`- `)两种列表前缀, 与
  collect_learnings docstring 声明的两种支持格式对应, 恰当不冗余。

### E. 历史一致性

- **[pass] HanflowError N/A 声明自洽**: signal-gather.sh 为 hanflow-evolve 仓库
  的 bash+heredoc python 独立脚本, 无任何 hanflow import, 不在 hanflow 运行时内
  执行; LEARNINGS 设计不变量 #1 约束的是 hanflow 框架代码, 采集脚本沿用自身
  「宽松降级」约定 (collect_github 的 degraded 机制同源) 的声明成立。
- **[pass] 不与 LEARNINGS 约束冲突**: 实测 8/8 已完成条目均为行首 `~~` 格式,
  direction 风险 1 缓解声明属实。设计过滤规则为 LEARNINGS #2 原文建议
  (「`~~删除线~~` 或 `✓ 已完成`」)的收窄子集, 但有 direction 风险 2 的显式决策
  背书 (不做投机覆盖), 且迁移兼容章重申维护约定继续用 `~~`, 逻辑闭环。
  单主题版本、3 硬门等「用户偏好」均无冲突。

## 建议修订

无。round 1 提出的 4 条建议全部落实 (见下), 无新增问题。

## 修订记录 (round 2 复核, 2026-08-20)

| # | round 1 判定 | 修订内容 (design.md 位置) | 复核结论 |
|---|------------|--------------------------|---------|
| 1 | 严重: 断言「总数 == 3」与 fixture (保留 2 条) 及 id 断言矛盾 | 测试策略断言改为「== **2** (fixture 条目 3/4 两条待办保留)」, id 断言改「连续重编号: learning:1, learning:2」 | **解决**: 三处 (fixture 标注/总数/id) 互相一致 |
| 2 | 严重: 「销账」与「重采」顺序未声明, 原表序 (销账在前) 将使重采得 9 ≠ 11 | 组件分解表前新增「执行顺序约束: 先重采、后销账」(含 9 条反例推演), 表格加顺序列 (过滤器→测试→重采[销账前快照, 预期 11 条]→销账→回归) | **解决**: 顺序约束明确, 反例推演经实测数据验证正确 (19−8−2=9), 19→11 在声明顺序下必然成立 |
| 3 | 轻微: 接口契约「现状 L244-246」与实际 L245-248 偏差 1-2 行 | 行号校准为「L245-248」 | **解决**: 与实际行号 (245 body= / 246-247 判空 / 248 idx+=1) 精确吻合 |
| 4 | 轻微: 未写明新用例 learnings 开关及其他源关闭的 config 要点, 计数口径有歧义 | 断言段补 config 要点: 「signals.learnings: {enabled: true} 且其他信号源全部关闭, 使 learnings 计数即 signals 总数」 | **解决**: 与源码 L329 配置键及现有用例 YAML 风格吻合, 口径唯一 |

**round 2 改判依据**: 4 处修订逐条对照实际源码/fixture/signals.json 复核确认
解决, 且修订仅触及组件分解(顺序)、接口契约(行号)、测试策略(断言+config)三处,
未改动其余章节, 原 pass 判定全部维持, 未引入新问题。
