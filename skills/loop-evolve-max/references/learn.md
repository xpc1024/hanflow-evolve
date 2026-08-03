# P9. LEARN — 回顾 + 专家效能回顾 (max 版: 委托 + 追加)

> 委托 loop-evolve learn.md 主体;追加专家团队效能回顾。

## 执行步骤

1. 【委托主体】读 loop-evolve 的 learn.md 并执行,
   执行前将 `state.yaml` 全局替换为 `state-max.yaml`(其余字面量保持不变)。
   loop-evolve reference 路径解析(取先找到者):
   - 优先 `~/.zcode/skills/loop-evolve/references/learn.md`
   - 回退 `$EVOLVE_HOME/skills/loop-evolve/references/learn.md`
   完成 retro.md + LEARNINGS.md 更新。

2. 【max 追加·专家效能回顾】汇总本周期专家使用情况, 追加到 retro.md 的
   "专家团队效能" 章节:
   - 哪些专家被命中(design_experts + conditional)
   - 各专家产出质量(审核是否抓到真问题 / code review 是否有效)
   - 是否过度(某专家产出冗余)或不足(某领域该派未派)
   - core 判定是否准确(自动 vs 人工)
   - token 实际消耗 vs budget

3. 据回顾提炼可复用经验写入 LEARNINGS.md(若专家 prompt/路由需优化)

4. 写 state-max.yaml: `bash scripts/write-state.sh state-max.yaml phase awaiting_next_cycle`

5. Commit, 报告下次提醒
