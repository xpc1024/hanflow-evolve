# P6. CODE — TDD + 核心 Task 逐个专家 review (max 版)

> Forked-from: loop-evolve/references/code.md
> 差异:每个核心 Task 完成后派 code-reviewer 专家 review;非核心 Task 跳过(= loop-evolve)。

## 执行步骤

0. **加载本心**:读 `hanflow-evolve/CHARTER.md` 全文。后续编码遵守 §2 不变量、
   §3 依赖方向矩阵、§5 禁止模式。遇架构变更(CHARTER §6 触发清单)须先产 ADR 再编码。
   (SOUL.md 式注入:本心先于行动。)

1. cd hanflow 仓库, 创建 feature 分支: `git checkout -b evolve/$CYCLE_ID`

2. 按 execution-plan.md 的 Task 顺序:
   a. 每个 Task 调用 superpowers:test-driven-development(红绿循环)
   b. conventional commit(feat:/fix:/refactor:)
   c. 遇 bug 调用 superpowers:systematic-debugging
   d. 无依赖任务用 superpowers:dispatching-parallel-agents(上限 3, 不同文件)
   e. 【max 新增】Task 完成后判定是否核心 Task:
      - 读 `references/route-experts.md` §2 is_core_task:
        该 Task 的 affected files 命中 core_packages 或 security_surfaces → 核心
      - 读 config.yaml experts.p6_review_mode(默认 all_core):
        - all_core: 核心 Task 派 review;非核心跳过
        - sampled: 核心 Task 抽样派 review(每 N 个抽 1);非核心跳过
        - off: 全部跳过 P6 review, 留给 P7
      - 若该 Task 需 review(all_core 下为核心 / sampled 下被抽中):
        派 code-reviewer 专家 fresh-context review:
        - 读 `references/experts/code-reviewer.md`, 填占位符:
          {PAYLOAD}=本 Task 改动说明, {CONTEXT}=direction 目标 + Task 定义,
          {ROUTING}=expert_routing 字段
        - {BASE_SHA}=Task 开始前 commit, {HEAD_SHA}=本 Task commit
        - 用 Agent 工具(general-purpose)派发
        - 若 Assessment = No / With fixes 且有 Critical/Important:
          → 回 a 修复 → 重审(review 循环, 同 subagent-driven-development)
        - 全 pass 才进下一 Task

3. 所有 Task 完成, 写 state-max.yaml: `bash scripts/write-state.sh state-max.yaml phase verify`

4. Commit, 自动进入 P7

## 分支管理
- feature 分支 evolve/$CYCLE_ID
- 不直接动 main
- Gate3 通过后才 merge

## review 死锁防护
核心 Task review 反复不过(>3 次)→ 置 last_error(Class C), 停下报告"需人工介入"。
