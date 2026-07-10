# P2b. HUMAN_TOPIC — 开发者主题输入 (优先级最高)

## 前置条件
- state.yaml.phase == "human_topic"
- BACKLOG.md 已更新 (P2 完成)

## 设计理由
开发者对自己框架的判断往往比任何信号采集都准。此阶段让开发者有机会覆盖 AI 决策。
若不提供,则由 AI 自主决定 (用 BACKLOG 队首)。

## 执行步骤

1. 检查 state.yaml.pending_human_topic:
   若非 null (开发者用 /loop-evolve topic 预设过):
   - 用预设主题作为本周期目标
   - 在 BACKLOG 中标注该主题 source=human_override (或新建)
   - 清空 pending_human_topic: bash scripts/write-state.sh state.yaml pending_human_topic null
   - 设置 target_theme

   若为 null (未预设):
   - 读 BACKLOG 队首 3 个候选主题
   - 用 AskUserQuestion 询问开发者:
     问题: "本周期的迭代主题?"
     选项:
       1. "用 AI 推荐: <队首主题>" (推荐)
       2. "我指定主题" → 让开发者自由输入
       3. "跳过本周期" → 转 awaiting_next_cycle
   - 若开发者选"我指定": 接受自由文本,匹配 BACKLOG 或新建,标注 source=human_override
   - 若无响应/选 AI 推荐: 用 BACKLOG 队首 (source 保持 ai_signal)

2. 确定 target_theme + target_version, 写入 state.yaml

3. 更新 state.yaml.phase = "plan"

4. Commit: git add BACKLOG.md state.yaml && git commit -m "cycle($CYCLE_ID): P2b topic selected"

5. 自动进入 P3 (plan)

## 优先级语义
- human_override 主题绕过 P2 打分算法,直接成为本周期目标
- 但仍走 P3 (方向计划) + Gate 1, 把模糊想法变成可验收的目标
- 无响应时默认用 AI 队首 (保证 LOOP 无人值守时可自主运行)
