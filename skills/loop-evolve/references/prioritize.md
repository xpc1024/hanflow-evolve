# P2. PRIORITIZE — 优先级排序

## 执行步骤

1. 运行打分: python scripts/score-signals.py . "$CYCLE_ID"
   产物: cycles/$CYCLE_ID/scored.json

2. 运行重排序: bash scripts/update-backlog.sh . "$CYCLE_ID"
   产物: BACKLOG.md (更新)

3. 读 BACKLOG 队首,提取 target_version (从主题 version_impact 推导:
   patch→x.y.Z, minor→x.Y.0, major→X.0.0)

4. 写入 state.yaml: target_theme, target_version, phase=human_topic

5. Commit: git add BACKLOG.md state.yaml && git commit -m "cycle($CYCLE_ID): P2 prioritize complete"

6. 自动进入 P2b (human_topic)

## 人工介入
scored.json 的 themes 的 estimated_effort/risk 是脚本默认值(medium/low)。
P2 阶段 agent 应审阅主题,根据主题实际复杂度调整 effort/risk。
