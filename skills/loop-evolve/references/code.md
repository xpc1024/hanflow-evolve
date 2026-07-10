# P6. CODE — TDD 实现

## 执行步骤

1. cd hanflow 仓库, 创建 feature 分支: git checkout -b evolve/$CYCLE_ID
2. 按 execution-plan.md 的 Task 顺序:
   - 每个任务调用 superpowers:test-driven-development (红绿循环)
   - conventional commit 格式 (feat:/fix:/refactor:)
   - 遇 bug 调用 superpowers:systematic-debugging
   - 无依赖任务用 superpowers:dispatching-parallel-agents (上限 3, 不同文件)
3. 所有 Task 完成后, 写 state.yaml: phase=verify
4. Commit, 自动进入 P7

## 分支管理
- feature 分支 evolve/$CYCLE_ID
- 不直接动 main
- Gate 3 通过后才 merge
