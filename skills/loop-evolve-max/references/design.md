# P4. DESIGN — 专家驱动设计 (max 版)

> Forked-from: loop-evolve/references/design.md
> 差异:领域专家直接产出设计分片, 控制器整合解决冲突。

## 执行步骤

1. 读 direction.md(已 Gate1 确认, 含 expert_routing 字段)

2. 【专家驱动】为 expert_routing.design_experts 每位派 fresh-context subagent:
   - 读 `references/experts/<role>.md`, 填占位符:
     {PAYLOAD}="请产出你领域的设计分片", {CONTEXT}=direction 目标+影响模块,
     {ROUTING}=expert_routing 字段
   - 用 Agent 工具(general-purpose)派发, 各产出领域设计分片:
     - backend-architect → 接口契约 / 数据流 / 错误处理
     - frontend-designer → 组件分解 / 可访问性(若涉前端, 复用 design-taste-frontend + tokens.css)
     - security-engineer(core) → 威胁建模 / 信任边界
     - performance-engineer(core) → 关键路径 / 资源预算
     - data-modeler → schema / migration
     - devops-engineer → 沙箱 / CI / 发布
     - qa-architect → 测试策略 / DoD 映射

3. 深读相关源码(用 Agent 工具并行探索 affected_modules)

4. 【冲突整合】控制器(fresh context) 汇总各分片 → 整合 design.md。
   冲突解决规则:
   - 数据/接口层冲突 → backend-architect 优先
   - 展示/交互层冲突 → frontend-designer 优先
   - 安全冲突(仅 core) → security-engineer 在安全相关问题上最终裁定(安全保守);非安全问题不走此规则
   - 性能 vs 可读性 → 默认偏可读性, 性能退化超阈值才升级
   - 仍僵持 → 升级至 Gate2, design.md 标注"待裁决冲突"

5. 若涉前端 → 复用 loop-evolve design.md 的 design-taste-frontend 调用(传 tokens.css + 8 不变量)

6. 生成 design.md(含"专家分片整合"章节, 记录各分片来源与冲突裁决)

7. 副本到 docs/superpowers/specs/

8. 写 state-max.yaml: `bash scripts/write-state.sh state-max.yaml phase audit_design`

9. Commit, 自动进入 P4b

## design.md 必须包含(max 追加)
架构定位 / 组件分解 / 接口契约 / 数据流 / 错误处理 / 测试策略 /
前端影响 / 迁移兼容 / **专家分片整合(来源 + 冲突裁决记录)**
