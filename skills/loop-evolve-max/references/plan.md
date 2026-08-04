# P3. PLAN — 迭代方向计划 (max 版: 专家路由 + 设计前注入)

> Forked-from: loop-evolve/references/plan.md
> 差异:brainstorming 前插入专家路由(步骤 2)+ 设计前注入(步骤 4)。

## 执行步骤

1. 读 target_theme + signals.json + LEARNINGS(注入架构模式 + 用户偏好区块)

2. 【专家路由】读 `references/route-experts.md` §3 路由表:
   - 据 target_theme + 影响模块匹配领域专家
   - 按 §2 判定 is_core_cycle(任一 Task 命中核心面 / major / P2b 人工 core)
   - 写入 direction 草案的 expert_routing 字段(design_experts / core / conditional)

3. 调用 superpowers:brainstorming 轻量模式(跳过逐个澄清 + visual companion),
   生成方向草案(2-3 路径 + 推荐)。

4. 【设计前注入】为 expert_routing.design_experts 每位派 fresh-context subagent:
   - 读 `references/experts/<role>.md`, 填占位符:
     {PAYLOAD}=方向草案, {CONTEXT}=目标+影响模块, {ROUTING}=expert_routing 字段
   - 用 Agent 工具(general-purpose)派发
   - 收集各专家"风险/盲区 + 必须覆盖的约束"(3-5 条)
   - 汇总成 `cycles/$CYCLE_ID/expert-precheck.md`
   - 若 core==true, security/performance 专家亦在此派发

5. 将 expert-precheck.md 喂回 brainstorming, 生成更优 direction.md(含 expert_routing 字段)

6. 副本到 docs/superpowers/specs/

7. 写 state-max.yaml: `bash scripts/write-state.sh state-max.yaml phase audit_direction`

8. Commit, 自动进入 P3b

## direction.md 必须包含(max 追加)
元信息 / 动机 / 目标 / 非目标 / 实现路径(2-3 + 推荐) /
影响模块 / 风险评估 / 验收标准 / **专家路由字段(expert_routing)**

## Token 防护
派发前检查 config.yaml experts.max_dispatch_budget_per_phase(默认 8);
超限则优先保 QA + 至少一位领域专家, 跳过 conditional, 记 LEARNINGS。
