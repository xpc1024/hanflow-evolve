# Retro — cycle 2026-W32-1.2.2

| 元信息 | |
|---|---|
| cycle_id | `2026-W32-1.2.2` |
| 主题 | docker-provisioner-real-contract-tests (human_override) |
| 版本 | 1.2.2 → **1.2.3** (patch) |
| Gate 通过 | Gate1 ✓ / Gate2 ✓ / Gate3 ✓ (全部一次通过) |
| retry_count | 0 (verify 无 auto-fix) |
| audit_retry_count | 0 (direction/design 全通过) |
| 完成日期 | 2026-08-04 |

## 目标达成率

**100%**。原始主题"docker 真实测试"的前提经 P3 调研发现已过时, 转化为"真实测试 CI 可见性加固", 5 项交付全部完成并验证:
- ✅ docker marker 注册 (pyproject.toml)
- ✅ 4 lifecycle 测试打标 (test_docker_provisioner.py)
- ✅ make test-docker (Makefile)
- ✅ CI 拆分 + image-gate ::warning:: (ci.yml)
- ✅ tests/isolation/README.md

## 什么有效 (Keep Doing)

1. **P3 调研用源码证据纠偏失效信号** — 这周期最大价值。LEARNINGS #1 说"CI 未验证真实容器路径", 但查 CI 日志发现 13/13 全 pass 含 4 个 lifecycle。没有盲目执行已完成的"债", 而是挖出两个真实缺口。**direction 阶段的调研是不可省略的价值环节**。
2. **独立 subagent Layer-2 审核** — direction 和 design 两轮都派 fresh-context subagent, design 审核 0/0 全过且源码核实了所有基线声明 (13 测试构成、marker 现状、错误类名)。审核质量高, 非橡皮图章。
3. **小改动原子 commit** — 5 个 Task 各一个 conventional commit, 每个 < 10 行, 易审核易回滚。
4. **测试守恒验证** — `-m docker`(4) + `-m "not docker"`(9) = 13 = 全集, 在实现后立即用 `--co` 验证, 防止 marker 拆分引入遗漏。
5. **charter-check --diff 与 --full 双跑** — diff 增量 (P9) 快速过, full 全量 (P10 release) 强制审计, 两者都 GREEN, 架构契约零风险。

## 什么卡住 (Pain Points)

1. **evolve state.yaml.current_version 滞后 (中等)** — version-bump.sh 只改 hanflow 的 4 处版本, 不更新 state.yaml.current_version。site-sync.sh 从 state.yaml 读 LATEST, 导致 hanflow-home 先被错同步到 1.2.1 (state 里的滞后值), 后手动修正到 1.2.3。**这是 LOOP 工具链的真实 bug, 应在下个 cycle 修**。
2. **hanflow-evolve 分支混杂 (轻微)** — 启动时 evolve 在 `feature/loop-evolve-max` 分支且有未提交改动, 与周期产物提交语义冲突。用 stash + checkout main 规避, 但说明并行工作流需要更清晰的分支隔离。
3. **gh release 缺 workflow scope (轻微)** — `gh release create` 因缺 workflow scope 失败, tag 已推送但 release 页面未创建。需用户本地 `gh auth refresh -h github.com -s workflow` 后手动创建。
4. **BACKLOG 队首主题质量差 (已知)** — learnings-priority (score 44) 聚合了 15 条 learning 含多个已完成项 (score-signals.py bug 已修、mypy 已恢复), signal-gather 不过滤已完成的 LEARNINGS 条目。本次靠人工判断绕过, 但 BACKLOG 刷新机制需要改进。
5. **Git Bash 无 make 命令 (环境)** — 本机 Git Bash 环境没有 make, 验证 Makefile target 时用等价 pytest 命令替代。不影响 CI (CI 用 ubuntu-latest 有 make)。

## token 消耗 (估算)

| 阶段 | 占比 | 备注 |
|---|---|---|
| P1-P2 (scan/prioritize) | 低 | 脚本驱动, 零 LLM |
| P2b-P3 (topic/plan) | **高** | 主题分析 + 深度调研 (读 docker_provisioner.py 全文 + CI 日志 + 测试文件) |
| P3b-P4b (audit×2) | 中 | 2 个独立 subagent (sonnet) |
| P5 (plan_exec) | 低 | design 已明确 |
| P6 (code) | 低 | 5 个小改动 |
| P9 (verify) | 低 | 跑脚本 + 写报告 |
| P10 (release) | 中 | site-sync 排错 |

调研 (P3) 是 token 大头, 也是价值最大的环节。

## 意外发现

1. **score-signals.py 的 Windows bug 已被修复** — LEARNINGS #4 说"3 个 cycle 复现未修", 但脚本第 203-212 行有专门的 backslash 规范化 + 跨平台模块提取, BACKLOG 已正确按模块聚合 (不再是 stub-E:)。**LEARNINGS #4 实际已完成, 应标删除线**。
2. **charter-check 的 ADR WARN 是正则误报** — direction/design 因含"影响模块"一词触发"架构变更无 ADR"警告, 但该词指测试/CI 文件非架构模块。Layer-2 E 类判定为假阳性。charter-check 的架构变更检测正则可优化 (区分"影响模块"表的语义)。
3. **site-sync.sh 无条件触发 vs release.md site_sync_needed=false 跳过** — 两者语义不同: site_sync_needed 控制**文档内容**同步 (release.md Step 3-7), site-sync.sh 只做**版本号数据**同步。本周期版本号变了 (1.2.2→1.2.3) 所以 site-sync 合理触发, 即使文档内容不需要更新。

## 下次优先 (→ LEARNINGS)

1. **[高] 修 version-bump.sh: 同步 state.yaml.current_version** — 本周期暴露的 LOOP 工具链 bug, 导致 site-sync 读到滞后版本。
2. **[高] signal-gather 过滤已完成 LEARNINGS 条目** — learnings-priority 主题混入已完成项 (score-signals bug、mypy), 污染打分。应识别 `~~删除线~~` 或 `✓ 已完成` 标记并跳过。
3. **[中] gh release 权限**: 需 `gh auth refresh -h github.com -s workflow`。
4. **[中] LEARNINGS 清理**: #4 (score-signals bug) 标删除线, #6 (site_sync) 紧迫性已降 (home 已对齐)。
5. **[低] charter-check 正则优化**: 区分"影响模块"表的语义, 减少假阳性 ADR WARN。
6. **延续项**: MCP remote transport / K8s sandbox (本周期未触及, 仍为候选)。
