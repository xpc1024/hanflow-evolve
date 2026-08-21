# Retro — 2026-W34-1.2.4 · loop-toolchain-state-sync-and-signal-filter

## 元信息

- **周期**: 2026-W34-1.2.4 (2026-08-20, 单日完成)
- **主题**: LOOP 工具链修复 (human_override): signal-gather 过滤已完成条目 + version-bump state 同步核实销账
- **版本**: hanflow **1.2.3 不变** (零改动, 不发空 tag — direction 验收 #6)
- **Gate**: Gate1/2/3 全部用户批准
- **retry_count**: 0 (实现) · audit_retry_count: design 一轮修订 (C 类自洽 ×2, 不占计数)
- **交付**: evolve 15 commits 推送 origin/main

## 目标达成率: 6/6 (100%)

direction 全部验收达成: 过滤落地 (TDD 红→绿) / learnings 19→11 / 测试全绿 /
LEARNINGS #1#2 销账 / hanflow 零提交 / 不发空 tag。

## 什么有效 (Keep Doing)

- **核实先于计划**: P3 前实测两个"待修 bug"现状, 发现 #1 早已修复 (d18e9b9),
  避免重复劳动, 周期范围即时收敛为"过滤 + 销账"
- **设计审核抓真问题**: design 首轮审出断言矛盾 (==3 vs 保留 2 条) 与执行顺序
  矛盾 (先销账则 11≠9), 修订后复核 0/0 — 两处都会在实现期造成返工
- **"先重采后销账"顺序约束**: 作为 design 显式契约写入, T3/T4 严格遵循,
  自证数字 (11) 与验收精确一致
- **边界用例设计**: fixture 故意放入"正文含已修但行首无划线"条目, 锁死
  startswith("~~") 规则不误杀 (对应真实 learning:2)
- **cmd 层绕过 bats 挂死**: 发现即最小复现 (run bash -c "exit 1"), 定位为
  环境级后不纠缠, 绕过继续交付

## 什么卡住 (Pain Points)

- **ZCode Git Bash pty 与 bats 1.13.0 不兼容**: `run` 非零退出子进程挂死,
  全量 bats 首跑 17 分钟无输出被杀 (→ LEARNINGS 环境债)
- **裸 Python 3.13 环境缺 zhipuai + numpy stub 语法错**: mypy/pytest 门受阻,
  `uv run` 网络超时无法补齐 (→ 环境恢复后重跑全量门, W31 教训再现)
- **charter-check --full 的 layering 单项慢**: 与前四项合并跑时 300s 超时,
  单独给 540s 通过 — 非问题, 但说明全量门需要更长超时预算
- Gate 提问两次未获即时响应 (会话异步), 流程按设计停在等待, 无损

## token 消耗 (估算)

- 主循环 (scan→learn 全阶段): ~350k
- direction 审核 subagent: ~151k
- design 审核 subagent (两轮): ~338k
- 合计约 ~840k; 重活集中在两个审核 agent, 实现本身极轻 (净 diff +90/-265)

## 意外发现

1. LEARNINGS「下次优先」#1 记录的 bug 实际已修 (commit d18e9b9, W32 后直接
   落 main 但未销账) — **知识库滞后于代码**是独立于代码 bug 的问题
2. score-signals 的 member_score 与条数解耦 (learnings 40 固定), 过滤后
   learnings-priority 仍 44 分 — 修复收益是**成员净化**而非分数回落,
   "队首虚高"的另一半根因在打分权重结构 (记录备查, 不动)
3. evolve 仓库 main 直连工作流 (无 feature 分支), github-sync Phase A/B 的
   feature-branch 假设对 evolve 自身周期不适用 — 本周期手动 push 等同 Phase B

## 下次优先 (→ LEARNINGS 覆盖式更新)

1. [中] DOCKER sandbox 定制镜像构建流水线 (含 hanflow runtime)
2. [中] K8S sandbox 落地 (Phase 10)
3. [中] MCP remote transport 实现
4. [中] Group B 命令后端
5. [低] pytest-cov 覆盖率基线
6. [低] charter-check 正则优化 (假阳性, 本周期 direction 又复现一次)
7. [低] gh release 权限
8. [环境] ZCode 会话 bats 挂死 + python 环境缺依赖 (恢复后重跑全量门)
