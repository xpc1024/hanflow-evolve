# Direction 审核报告 — 2026-W34-1.2.4

- 审核对象: `cycles/2026-W34-1.2.4/direction.md`
- 审核日期: 2026-08-20
- 参考材料: `LEARNINGS.md` (框架架构模式/下次优先)、`scripts/signal-gather.sh` `collect_learnings()`、`cycles/2026-W34-1.2.4/signals.json`、`scripts/version-bump.sh`、`tests/test-version-bump.bats`、`scripts/charter-check/charter-check.sh`

## 审核结论

- **整体: 通过 (0 严重 / 3 轻微)**
- 文档核心实证全部经独立复核成立: 19 条 learning 信号、其中 8 条行首 `~~` 已完成、
  预期保留 11 条, 三组数字与 `signals.json` 逐条核对精确吻合; 动机中「#1 已修」的
  两处代码证据 (version-bump.sh:254-286 回写段、test-version-bump.bats:92 用例) 属实;
  charter-check WARN 判定为**假阳性** (详见 E 类)。

## 逐项判定

### A. 架构合规性

- [pass] **hanflow 本体零改动属实, 六层架构不触及**: 「影响模块」表唯一 hanflow 行
  明确标注零改动, 其余 4 行均为 hanflow-evolve 仓库侧 (signal-gather.sh / bats /
  LEARNINGS.md / signals.json)。改动对象是 LOOP 工具链 shell/python 脚本与文档产物,
  不落在 hanflow 的 core/atoms/orchestration/models/runtime/... 任何一层。
- [pass] **Protocol-based / HanflowError-only / RuntimeContext 注入 / DSL 单一真相源 /
  LangGraph 薄运行时均不触及**: 本周期不新增/修改任何 Protocol 定义、错误层级、
  context 注入、DSL schema 或 LangGraph 编译路径; LEARNINGS「框架架构模式」的 6 条
  设计不变量审查对象是 hanflow 源码, 本周期对其零交集。
- [pass] **charter-check WARN "提及架构变更但无 ADR" 为假阳性**: WARN 由
  charter-check.sh:48 正则中的字面关键词 `影响模块` 命中 direction.md 的
  「## 影响模块」章节标题触发, 属表格标题的字面匹配; 该表实际内容为 evolve 侧
  工具链文件 + hanflow 零改动, 不存在 hanflow 架构变更事实, 故无需 ADR。
  (该正则的误报史已由 LEARNINGS #15 记录, 本周期将其优化列为非目标, 处置一致。)

### B. 完整性

- [pass] **覆盖全部目标**: 动机列出的 2 个问题 (#1 已修待销账 / #2 未修待修) 与
  目标 1-6 一一对应——#2 的过滤规则 (目标 1)、测试 (目标 2)、重采自证 (目标 3)、
  #1 的测试验证与销账 (目标 4)、LEARNINGS 段落清理 (目标 5)、回归 (目标 6)。
- [pass] **有错误处理**: 风险评估 3 项 (误杀边界条目 / 未来新完成标记格式 /
  BACKLOG 排序语义变化) 各配缓解措施, 其中风险 1 的边界用例 (learning:2 正文含
  "已修"字样但行首无 `~~`) 已实际存在于本周期 signals.json, 非臆造。
- [pass] **有测试策略**: 3 类 bats 用例 (已完成跳过 / 正常保留 / 边界不误杀) +
  重采自证 (19→11) + 全套回归; `tests/test-signal-gather.bats` 已存在, 用例有落点。
- [pass] **有迁移兼容**: 信号 schema (id/source/weight_tier/raw) 与消费端
  (score-signals / update-backlog) 接口不变, 仅条目数量减少; signals.json 重采
  即重建, 无遗留格式迁移问题; LEARNINGS 销账保留 cycle 号可追溯。
- [pass] **有非目标**: 明确列出 4 条 out of scope (消费端过滤 / BACKLOG 结构改造 /
  hanflow 本体 / LEARNINGS 其他段落), 边界清晰。

### C. 自洽性

- [pass] **文档数字与实证一致 (19 / 8 / 11)**: 逐条核对 signals.json:
  learning:1-19 共 19 条; 行首 `~~` 者恰为 learning:4/5/7/12/13/14/15/16 共 8 条,
  与文档 "如 #4/#5/#7/#12-16" 精确一致; 19−8=11 与验收标准 #2 的 "learnings 信号
  = 11 条" 一致。
- [pass] **路径 A 与目标对应且技术方案可行**: `collect_learnings()`
  (signal-gather.sh:217-258) 现状对 `- `/`N. ` 条目无差别收录 (代码中无任何
  `~~`/`✓` 判定), 与动机 "确实未修" 相符; 路径 A 的 `body.startswith("~~")`
  挂接点 (body = lm.group(1).strip(), 第 245 行) 与现有解析结构吻合, 确为 1 行级
  改动; 全部 8 条已完成条目的 text 实测均以 `~~` 开头, 规则可精确命中。
- [pass] **验收标准可执行**: 验收 1-6 均为可机械验证项 (bats 命令 + 3 类用例、
  重采后信号计数 = 11、`pytest tests/test-score-signals.py` 文件实存、LEARNINGS
  标注带 cycle 号、hanflow 工作区零提交、release 决策分支明确)。
  动机中 "#1 已修" 的两处证据亦复核属实: version-bump.sh:254-286 存在经
  write-state.sh 回写 current_version 的完整段落,
  test-version-bump.bats:92 存在 "writes back state.yaml.current_version" 用例。

### D. 复杂度控制

- [pass] **无过度设计 (YAGNI)**: 路径 C (双向过滤) 被明确否决为过度设计; 风险 2
  拒绝对 "仅 `✓` 无 `~~`" 格式的投机覆盖 (当前无此格式条目); 消费端过滤以
  "不重复设卡" 排除。三处收敛均有明确理由, 非隐式裁剪。
- [pass] **复杂度匹配主题**: 1 行级过滤规则 + 3 类测试 + 销账清理 + 重采自证,
  单周期体量恰当; 无引入新脚本/新配置/新依赖。

### E. 历史一致性

- [pass] **不与 LEARNINGS 约束冲突**: 「框架架构模式」6 条设计不变量与编码风格的
  约束对象均为 hanflow 源码, 本周期零交集; 与 LEARNINGS「下次优先」#2 的诉求
  (过滤已完成条目) 方向一致——原文建议 "`~~删除线~~` 或 `✓ 已完成`" 双标记识别,
  文档收敛为仅行首 `~~`, 理由充分 (现网所有 `✓` 均伴随 `~~` 前缀, 已逐条核实)。
- [pass] **不与现有工具链行为冲突**: 过滤规则追加在 collect_learnings 既有两种
  条目格式解析之后, 不破坏其 docstring 声明的解析契约; 信号 id 编号 (idx 递增)
  在过滤后重排, signals.json 为周期内快照, 无跨周期 id 依赖问题。
- [pass] **charter-check WARN 判定**: 假阳性 (理由见 A 类第 3 条)。文档改动对象
  为 hanflow-evolve 工具链, 不涉及 hanflow 架构, 无需补 ADR; 该 WARN 不构成本
  文档的修订义务。

## 建议修订

1. (轻微) **注明 learning 编号双体系**: 动机段 "#1/#2" 用的是 LEARNINGS「下次优先」
   原生编号 (1-16), 而 "#4/#5/#7/#12-16" 用的是 signals.json 展开后的编号 (1-19,
   含 #3 的 3 个内嵌子项)。两套编号在相邻段落混用, 当前语境可辨, 但建议在动机段
   加一句括注 (如 "signals.json 编号, 非 LEARNINGS 原生编号"), 避免后续 retro/audit
   误读。
2. (轻微) **段落清理可顺手去重**: LEARNINGS.md「下次优先」段尾 232/234 行
   "注意: prioritization 阶段会按 source_weights + theme_weights 重算..." 重复出现
   两次。目标 5 本就要动该段落, 建议将去重纳入清理范围; 同时可顺带评估滞留的
   #9-#13 五条 `~~` 已完成条目是否物理销账 (运行时过滤已治标, 段落物理清理治本;
   保守保留亦可接受)。
3. (轻微) **行号引用微校**: 动机中 "version-bump.sh:254-289" 实际回写段为
   254-286 行 (287-289 为文件尾空区), "signal-gather.sh:217-257" 的函数体为
   217-258 行。偏差 ≤3 行且引用范围覆盖实际代码, 无实质影响, 下次修订时顺手校准。
