# P7. VERIFY — 测试 + 行为化验证 + auto-fix

## 执行步骤

1. 跑 make ci (ruff + mypy --strict + pytest)
2. 若涉及前端: cd web && npm run typecheck && npm test
3. 跑 bash scripts/smoke-test.sh (行为化验证: 真跑 hanflow 工作流)
4. 调用 superpowers:verification-before-completion (必须贴命令输出)
5. 调用 superpowers:requesting-code-review (自我审查 diff)
6. 产物: cycles/$CYCLE_ID/test-report.md
7. 写 state.yaml: phase=gate3

## auto-fix 子循环
retry_count 从 state.yaml 读取
若任何测试失败:
  retry_count++
  若 retry_count < 3: 回 P6 修复 (写 phase=code)
  若 retry_count >= 3: 置 last_error (Class C), 停下报告"需人工介入"
