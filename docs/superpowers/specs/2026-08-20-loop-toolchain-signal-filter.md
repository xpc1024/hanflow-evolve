# Direction — 2026-W34-1.2.4 · loop-toolchain-state-sync-and-signal-filter

- **cycle**: 2026-W34-1.2.4
- **theme**: loop-toolchain-state-sync-and-signal-filter (human_override)
- **date**: 2026-08-20
- **target_version**: 1.2.4 (预期 hanflow 本体零提交 → 不对 hanflow 发空 tag,见验收标准 #6)

## 动机

LEARNINGS「下次优先」#1/#2 记录的两个 LOOP 工具链问题,经本周期 scan 前核实:

1. **#1 (version-bump.sh 同步 state.yaml.current_version)** — **代码已修复**:
   `scripts/version-bump.sh:254-289` 已有完整回写段(release 后经 write-state.sh
   对齐 current_version),且 `tests/test-version-bump.bats:92` 已有覆盖用例。
   LEARNINGS 未销账,属过时条目。
2. **#2 (signal-gather 不过滤已完成 LEARNINGS 条目)** — **确实未修**:
   `collect_learnings()` (scripts/signal-gather.sh:217-257) 对「下次优先」段落
   所有列表条目无差别收录。本周期实测:19 条 learning 信号中 **8 条为已完成项**
   (行首 `~~` 删除线标记,如 #4/#5/#7/#12-16),learnings-priority 主题被虚增至
   score 44 长期霸占 BACKLOG 队首,污染下周期选题质量。

## 目标 (in scope)

1. `collect_learnings()` 增加**行首 `~~` 判定**:条目正文以 `~~` 开头 → 已完成,
   跳过不采集。
2. 新增 bats 测试覆盖过滤规则,含三类用例:已完成(行首 `~~`)跳过、正常条目
   保留、**边界不误杀**(正文含"已修/已完成"字样但行首无 `~~` 的待办,如实测
   中的 learning:2)。
3. 修复后**重新采集本周期 signals.json** 自证效果(预期 learning 19 → 11)。
4. 跑既有 `test-version-bump.bats` 确认 #1 已修实现全绿,LEARNINGS #1/#2 销账。
5. LEARNINGS「下次优先」段落清理:#1 #2 标注完成,#3 内嵌已完成子项核对。
6. evolve 仓库全套测试(bats + pytest)回归全绿。

## 非目标 (out of scope)

- score-signals.py 消费端过滤(信号已在采集端治理,不重复设卡)
- BACKLOG 生成结构改造、charter-check 正则优化(LEARNINGS #18,另周期)
- hanflow 本体任何代码改动(hanflow 仓库零提交)
- LEARNINGS 其他段落(技术债/实践)的整理

## 实现路径

- **路径 A — 采集端过滤 (推荐)**: `collect_learnings()` 解析循环中,取条目
  正文 `body` 后判定 `body.startswith("~~")` → `continue`。改动 1 行级,源头
  治理,signals.json 本身恢复干净,所有下游消费者(score-signals /
  update-backlog)自然受益。重跑 signal-gather 即可端到端自证。
- **路径 B — 消费端过滤**: score-signals.py 打分时剔除已完成 learning。
  缺点:signals.json 仍携带脏数据,产物失真;过滤逻辑与解析逻辑分离两处。
- **路径 C — 双向过滤**: A+B 同时做。过度设计,无增量收益。

**推荐 A**。风险最低、治本、可自证。

## 影响模块

| 仓库 | 模块 | 改动 |
|------|------|------|
| hanflow-evolve | scripts/signal-gather.sh | +行首 `~~` 过滤 (1 处) |
| hanflow-evolve | tests/test-signal-gather.bats | +过滤用例 (3 类) |
| hanflow-evolve | LEARNINGS.md | #1/#2 销账 + 段落清理 |
| hanflow-evolve | cycles/2026-W34-1.2.4/signals.json | 修复后重采 |
| hanflow | — | **零改动** |

## 风险评估

- **风险 1**: 误杀正文提及完成事项的待办条目(如实测 learning:2)。
  缓解:规则严格限定**行首 `~~`**,现有 LEARNINGS 全部已完成项均为该格式;
  边界用例入测试。
- **风险 2**: 未来出现新完成标记格式(如仅 `✓` 无 `~~`)不被覆盖。
  缓解:当前无此格式条目;不做投机覆盖,LEARNINGS 维护约定继续用 `~~` 划线。
- **风险 3**: 重采后 learnings-priority 得分变化影响 BACKLOG 排序语义。
  缓解:这正是修复目的(队首去虚高);排序规则未动。

## 验收标准

1. `bats tests/test-signal-gather.bats` 全绿,新增用例覆盖:行首 `~~` 跳过 /
   正常条目保留 / 边界条目(正文含"已修"但行首无 `~~`)保留。
2. 重跑 `signal-gather.sh` 后 `cycles/2026-W34-1.2.4/signals.json` 的
   learnings 信号 = **11 条**(19 − 8)。
3. evolve 仓库全套测试绿:全部 bats + `pytest tests/test-score-signals.py`。
4. LEARNINGS「下次优先」#1/#2 已标注完成(带 cycle 号 2026-W34-1.2.4)。
5. hanflow 仓库工作区零提交(仅 evolve 侧交付)。
6. release 阶段决策:hanflow 零提交 → 跳过 hanflow version-bump/tag/
   github-sync Phase A 与 site-sync(版本不变,官网已对齐 1.2.3);evolve 仓库
   正常 commit + push + CHANGELOG-EVOLVE 记录。
