# P5. PLAN-EXEC — 执行计划

## 执行步骤

1. 读 design.md (已 Gate 2 确认)
2. 调用 superpowers:writing-plans
3. 产物: cycles/$CYCLE_ID/execution-plan.md
4. 副本到 docs/superpowers/plans/hanflow-evolve-$CYCLE_ID-$THEME.md
5. 写 state.yaml: phase=code
6. Commit, 自动进入 P6

## execution-plan.md 必须包含
任务列表(原子化,0.5-2h/单 commit) / 详细测试计划(单元+契约+行为化) /
依赖顺序(Task DAG) / 完成定义(DoD)
