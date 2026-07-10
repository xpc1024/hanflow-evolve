# P9. LEARN — 回顾

## 执行步骤

1. 生成 cycles/$CYCLE_ID/retro.md:
   - 元信息 (周期/主题/版本/Gate 通过/retry_count)
   - 目标达成率
   - 什么有效 (Keep Doing)
   - 什么卡住 (Pain Points)
   - token 消耗 (分阶段)
   - 意外发现
   - 下次优先 (→ 写入 LEARNINGS)
2. 提炼关键点更新 LEARNINGS.md:
   - 新架构模式 → "框架架构模式" 区块追加
   - 新技术债 → "已知技术债" 追加
   - 有效做法/失败教训 → 对应区块追加
   - "下次优先" 覆盖式更新
3. 更新 BACKLOG.md: 完成项标记 done
4. 更新 CHANGELOG-EVOLVE.md
5. 写 state.yaml: phase=awaiting_next_cycle, last_cycle_completed=today
6. Commit, 报告"周期完成, 下次提醒在 N 天后"
