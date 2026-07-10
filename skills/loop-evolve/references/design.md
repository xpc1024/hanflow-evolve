# P4. DESIGN — 概要 + 架构设计

## 执行步骤

1. 读 direction.md (已 Gate 1 确认)
2. 深读相关源码 (用 Agent 工具并行探索 affected_modules)
3. 调用 superpowers:brainstorming 完整设计 + writing-plans 设计部分
4. 判断是否涉及前端 (direction.md 影响模块含 web/ 或 schema.py 等):
   - 若涉及: 调用 design-taste-frontend, 传入现有 tokens.css + 8 不变量约束
5. 生成 design.md
6. 副本到 docs/superpowers/specs/
7. 写 state.yaml: phase=audit_design
8. Commit, 自动进入 P4b AUDIT

## design.md 必须包含
架构定位 / 组件分解 / 接口契约 / 数据流 /
错误处理 / 测试策略 / 前端影响 / 迁移兼容
