# P7. VERIFY — 测试 + 行为化验证 + 多专家全量 review (max 版)

> Forked-from: loop-evolve/references/verify.md
> 差异:CI 主体委托 loop-evolve;追加整 cycle BASE..HEAD 的多专家全量 code review。

## 执行步骤

1. 跑 make ci(ruff + mypy --strict + pytest)

1b. 跑架构契约守护(增量):
    `bash scripts/charter-check/charter-check.sh --diff`
    FAIL → 按输出修代码(优先);有意架构演进 → 产/引用 ADR + 白名单放行。
    失败回 P6, 计入 retry_count。

2. 若涉及前端: `cd web && npm run typecheck && npm test`

3. 跑 `bash scripts/smoke-test.sh`(行为化验证)

4. 【max 新增·全量多专家 code review】对整个 cycle 的 BASE..HEAD diff:
   按 direction 的 expert_routing 各派一位 code-reviewer 专家 fresh-context:
   - 读 `references/experts/code-reviewer.md`, 填占位符:
     {PAYLOAD}=整 cycle 改动说明, {CONTEXT}=direction 目标 + execution-plan,
     {ROUTING}=expert_routing 字段
   - {BASE_SHA}=cycle 开始前 main 的 commit, {HEAD_SHA}=当前 evolve/$CYCLE_ID HEAD
   - 各专家自带领域专项检查钩子(见 code-reviewer.md)
   - 汇总各专家结论 → `cycles/$CYCLE_ID/code-review-cycle.md`(含合并判定)
   - 任一专家 Critical → 回 P6 修复, 计入 retry_count

5. 调用 superpowers:verification-before-completion(必须贴命令输出)

6. 产物: `cycles/$CYCLE_ID/test-report.md` + `code-review-cycle.md`

7. 写 state-max.yaml: `bash scripts/write-state.sh state-max.yaml phase gate3`

## auto-fix 子循环
retry_count 从 state-max.yaml 读取
若任何测试失败 或 code-review Critical:
  retry_count++
  若 retry_count < 3: 回 P6 修复
  若 retry_count >= 3: 置 last_error(Class C), 停下报告"需人工介入"

## P6 vs P7 互补
P6 = 粒度细, 单 Task review(抓单点缺陷)
P7 = 粒度粗, 整周期多专家 review(抓集成与跨任务回归)
