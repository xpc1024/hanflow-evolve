# Retro: cycle 2026-W31-1.2.1 (clear pre-existing tech debt)

- cycle_id: 2026-W31-1.2.1
- 主题: clear-preexisting-tech-debt-s0-gates (human_override)
- 版本: 1.2.0 → 1.2.1 (patch,纯 fix)
- Gate 通过: 3/3(实现先行,事后补流程,门确认 approve)
- retry_count: 0
- audit_retry_count: 0
- 日期: 2026-07-29

## 目标达成率

**100% 达成**。用户目标"让 S0 三道门全绿 + 测试全过"完全满足:

| 门 | 修复前 | 修复后 | 达成 |
|---|---|---|---|
| ruff check | ❌ 15 errors | ✅ 0 | ✅ |
| ruff format | ❌ 25 文件 | ✅ clean | ✅ |
| mypy --strict | ❌ 28 errors | ✅ 0 | ✅ |
| pytest | ✅ 411 passed | ✅ 417 passed, 5 skipped | ✅(无回归) |
| charter-check | GREEN | ✅ GREEN 5/5 | ✅ |
| smoke-test | 4/4 | ✅ 4/4 | ✅ |

## 什么有效 (Keep Doing)

1. **先复现基线再动手**:用 `ruff check` / `mypy` / `pytest` 三件套先摸清完整失败面,
   再分组修(A 自动 / B 手动 / C format / D mypy),避免边修边引入新错误。
2. **charter-check 作为第二道守护**:mypy 绿 ≠ 契约绿。本周期 mypy 先过,charter-check
   抓到 `DockerError(Exception)` stub 违反 §2 不变量 1。两套检查互补,缺一不可。
3. **贡献者 PR 集成验证**:拉取 PR #5 后立即重跑全部门,确认 6 个新 stream 测试通过且
   `base.py` 的 `__all__` 修复未破坏 provider 对重导出符号的引用。
4. **version-bump.sh 顺手修路径 bug**:跑了 2 个 cycle 的旧账(LEARNINGS #70 行)一次清零,
   而非再次手动绕过。

## 什么卡住 (Pain Points)

1. **TYPE_CHECKING stub 触发 charter 回归**:为让 mypy 精确识别 `Docker`/`DockerError`
   类型,初版加了 `class DockerError(Exception)` stub,结果 charter errors 守护误判为
   违反"所有异常继承 HanflowError"。教训:**type-checking stub 也是源码,会被 charter
   扫描**;改用 `type[Any]` + pyproject `ignore_missing_imports` 更干净。
2. **MSYS Git Bash 的 grep -E 多 pattern bug**:`grep -E "a|b|c"` 在本环境报 "conflicting
   matchers"。改用 `grep -e a -e b -e c` 绕过。非代码债,工具环境问题。

## token 消耗(分阶段,估算)

- 拉取 main + 集成 PR #5:~5k
- 四组修复(A/B/C/D)+ 迭代收紧:~20k
- 产物落盘(direction/design/execution/test-report)+ retro:~10k
- version-bump + github-sync + learn:~8k
- 合计:~43k(远低于 250k/cycle 预算)

## 意外发现

1. **`base.py` 缺 `__all__` 是真实契约 bug**:影响 13 个文件 16 个 mypy 错,长期潜伏只因
   上周期 mypy 跑不起来(环境阻塞)。一旦 mypy 恢复就暴露。说明"环境阻塞会掩盖真实债"。
2. **mypy 环境已恢复**:上周期(2026-W30-1.1.1)记录"Python 3.13 + numpy stub 阻塞 mypy",
   本周期 mypy 正常运行(strict,114 文件)。环境问题已自然解决,无需 pin。

## 下次优先 (→ 写入 LEARNINGS)

1. **docker daemon 环境实跑 DockerProvisioner 契约测试**(延续上周期,仍未验证)。
2. **score-signals.py Windows 路径 bug**(LEARNINGS #78,3 个 cycle 复现,仍未修)。
3. **migrations → alembic 版本化**(低优先,但每次 release 都触及)。
4. 引入 pytest-cov 建立覆盖率基线(本周期纯机械修复,正好需要量化回归基线兜底)。
