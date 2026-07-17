# Retrospective — 2026-W29-1.0.2 LLM Streaming

- cycle_id: 2026-W29-1.0.2
- target_version: 1.1.0（已发布）
- 日期: 2026-07-17

## 目标达成

**100% 达成**。LLM 流式输出全链路打通：StreamChunk + ModelProvider.stream Protocol + ModelRouter.stream（首 token 前 fallback）+ RuntimeContext.stream/emit_run_event + openai/glm provider 真实实现 + 4 占位 + LLMExecutor 流式分支 + Hanflow.run 注入 queue。v1.1.0 已 push 到 GitHub + Gitee 的 main 分支。

## 量化

- hanflow feature 分支：9 commits（实现 + lint + refactor + 版本 bump）
- 测试：347 passed, 1 skipped, 0 failed（含 35 新增）
- charter-check：--diff exit 0（修了 core→models 违规）+ --full exit 0
- P4b 审核：2 轮（第 1 轮抓 3 严重，修订后第 2 轮通过）

## 做得好的

1. **P4b 两阶段审核价值凸显**：第 1 轮 Layer-2 抓到 3 个实质 design 缺陷（错误包装矛盾致 fallback 不触发 / 数据流断链 ctx.event 不推 queue / glm async 误判物化丧失流式），全部在实现前修复。若未审核直接实现，这 3 个会变成运行时 bug，成本远高。
2. **charter-check 实战阻止架构漂移**：P7 --diff 抓到 `core/context.py → models` 反向依赖（StreamChunk 定义位置），forcing 了正确修复（移到 core/result.py）。这是 policy-as-code 的核心价值验证——实时阻止违规而非事后补救。
3. **实战驱动 charter-check 自身演进**：跑真实 cycle 暴露 3 个 charter-check 缺陷并修复（--doc 正则漏检 ADR-0006 / --diff HEAD-vs-base ADR-0007 / core→models 抓到后修代码）。体系在用中变强。
4. **TDD 全程**：7 个实现任务严格红绿循环，实现中又发现 2 个真实 bug（finish_reason 在 content chunk 不在 usage chunk / DeepSeek·VLLM 继承 OpenAIProvider 会继承真 stream 需 override 占位）。

## 做得不好的 / 教训

1. **execution-plan 的 fixture 构造多处理解不符**：NexusState/FakeTraceExporter/WorkflowNode 的真实构造与计划假设不同，subagent 每次要现读 conftest 调整。计划阶段应先跑一遍 fixture 探查。
2. **`git add -A` 扫进运行时产物**：T7 lint 修复用了 `git add -A`，把 Web Studio 运行时保存的 `workflows/*.yaml` 扫进 commit，跟着 merge 进 master。已清理 + gitignore。教训：commit 前用 `git add <具体文件>`，避免 `-A`。
3. **LICENSE 损坏未早发现**：master 的 LICENSE 是空文件（0 行），GitHub main 的是完整 Apache 2.0。push 前才发现，靠 github/main 恢复。应在 init-scan 或首个 cycle 就校验 LICENSE 完整性。
4. **version-bump.sh 路径 bug**：脚本找 `api/__init__.py`，实际在 `hanflow/api/__init__.py`。预存 bug，本 cycle 手动 bump 绕过。需修脚本。
5. **github-sync.sh 硬编码 main vs master**：LEARNINGS[7] 已记录。本 cycle 你决定废弃 master 统一到 main，所以这个 bug 反而"将错就对"了——但脚本仍需适配。

## charter-check 守护体系验证结论（本 cycle 核心目标）

| 守护机制 | 实战表现 | 结论 |
|---|---|---|
| CHARTER.md SOUL 注入（P6 step0） | code.md 加载本心生效 | ✅ 有效 |
| --doc 信号检测（P3b/P4b Layer-1） | 检测到 Protocol 扩展信号（修 ADR-0006 后） | ✅ 有效（需扩正则） |
| Layer-2 ADR 必要性判定 | 2 轮均正确判无需 ADR | ✅ 有效（避免流程税） |
| 两阶段审核 forcing 修订 | 抓 3 严重并修复 | ✅ 高价值 |
| --diff 代码守护（P7） | 抓 core→models 违规并 forcing 修复 | ✅ **核心价值验证** |
| --full release 审计（P8） | exit 0，无新增违规 | ✅ 有效 |
| policy-as-code 闭环 | 文档信号→代码检查→白名单→ADR 全通 | ✅ 闭环 |

**总结论：架构守护体系有效、可运行、自我改进。** 在真实进化中做到了三件事——不误报合法改动、抓住设计缺陷、自我演进补强。3 个实战缺陷（--doc 正则 / --diff base / core→models）都被体系自身捕获并修复，证明守护在起作用。

## 已知技术债更新

- **DOCKER sandbox**：用户指定下个 cycle 优先（已记 LEARNINGS 下次优先[1]）。
- **github-sync.sh 适配 main**：现在用 main，脚本硬编码 main 反而对了，但 master→main 迁移需清理远程 master 分支。
- **version-bump.sh 路径 bug**：`api/__init__.py` → `hanflow/api/__init__.py`，待修。
- **GLM SDK 流式 async**：本 cycle 按 async 写 + mock 通过，真实 GLM SDK 行为待生产确认。
- **官网同步**：LLM streaming 是新特性，hanflow-site 文档需补 streaming 章节（本 cycle 跳过，标待办）。

## 下一 cycle 候选

1. **DOCKER sandbox 落地**（用户指定优先）
2. version-bump.sh + github-sync.sh 脚本修复（小，可并入下个 cycle）
3. 官网 streaming 文档同步
