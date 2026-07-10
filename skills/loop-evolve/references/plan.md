# P3. PLAN — 迭代方向计划

## 执行步骤

1. 读 target_theme + signals.json + LEARNINGS (注入架构模式+用户偏好区块)
2. 调用 superpowers:brainstorming 轻量模式:
   - 跳过"逐个问澄清问题"(信号已充分)
   - 跳过 visual companion
   - 直接: 提 2-3 实现路径 → 选推荐 → 生成 direction.md
3. 产物: cycles/$CYCLE_ID/direction.md
4. 副本到 docs/superpowers/specs/ (保持可发现性)
5. 写 state.yaml: phase=audit_direction
6. Commit, 自动进入 P3b AUDIT

## direction.md 必须包含
元信息 / 动机 / 目标(in scope) / 非目标(out of scope) /
实现路径(2-3 选项+推荐) / 影响模块 / 风险评估 / 验收标准
