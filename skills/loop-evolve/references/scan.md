# P1. SCAN — 信号采集

## 前置条件
- state.yaml.phase == "scan"
- config.yaml.paths.hanflow 指向有效路径

## 执行步骤

1. 确定周期标识 (若新周期): week=$(date +%Y-W%V), cycle_id="$week"
   用 write-state.sh 更新: cycle_id, phase=scan, started_at

2. 创建周期目录: mkdir -p cycles/$CYCLE_ID

3. 运行信号采集: bash scripts/signal-gather.sh . "$CYCLE_ID"
   产物: cycles/$CYCLE_ID/signals.json

4. 报告采集结果: 信号总数(按来源分类)、降级情况、关键发现摘要

5. 更新 state.yaml:
   bash scripts/write-state.sh state.yaml phase prioritize
   bash scripts/write-state.sh state.yaml artifacts.signals "cycles/$CYCLE_ID/signals.json"

6. Commit: git add cycles/$CYCLE_ID/signals.json state.yaml && git commit -m "cycle($CYCLE_ID): P1 scan complete"

7. 自动进入 P2 (prioritize)

## 降级处理
- gh 无认证: signals.json 的 degraded.gh 记录原因,继续(用 stubs+learnings)
- 全部信号源失败: 记录 last_error (Class C),停下提示用户
