# Contribute-PR (Codex 版)

> 这是 contribute-pr skill 的 **Codex 原生格式**(Description/Trigger/Steps 三段)。
> 内容与 ZCode/Claude Code 版(`../SKILL.md`)保持同步,但格式按 Codex Skills 约定。
> install.sh 会把本文件装到 `~/.codex/agents/skills/contribute-pr/SKILL.md`。

## Description

面向无 `xpc1024/hanflow` 写权限的社区成员的 Hanflow 贡献 skill。复用 Hanflow 自进化体系
(loop-evolve)的 scan→code→verify 全流程,产出符合 CHARTER 设计不变量的代码,并以
Pull Request 形式提交(发 PR 而非 merge to main)。完整流程:选题 → 设计 → TDD 实现 →
测试验证 → S0 质量门 → fork push → 发 PR。支持纯文档贡献(`/docs` 子命令跳过代码阶段)。
凭证默认走 `gh auth login`(浏览器授权),无浏览器环境可用 fine-grained PAT。

## Trigger

当用户表达以下意图时自动触发:
- "给 hanflow 提 PR" / "contribute to hanflow PR" / "社区贡献" / "community contribution"
- "contribute-pr"(直接说 skill 名)
- "修 hanflow 的 issue" / "fix hanflow issue"(隐含贡献意图)
- "$contribute-pr"(Codex 显式调用)

也可在 Codex 里跑 `codex /skills` 确认本 skill 已被发现,然后用 `$contribute-pr` 强制触发。

## Steps

### 0. 前置校验 + 安全声明(必须先做)

1. 校验 loop-evolve skill 可达:`~/.zcode/skills/loop-evolve/references/`(Codex 版通过 install.sh
   装到 `~/.codex/agents/skills/loop-evolve/`)。不可达则报错并提示跑 install.sh。
2. **打印凭证安全声明**(在任何输入请求之前):
   ```
   即将用 gh auth 已登录的凭证发 PR。凭证由 gh 安全存储,Hanflow 不接触。
   无浏览器环境可改用 fine-grained PAT(限你自己的 fork,零持久化)。
   ```

### 1. 定位工作目录 + 读 state

- 工作目录 = 贡献者 clone 的 hanflow 仓库(如 `~/hanflow-dev/hanflow`)
- state 文件 = `<hanflow_repo>/.contribute/state.yaml`(字段同构 loop-evolve,cycle_id 用 `contrib-` 前缀)
- 无 state → 从 scan 开始;有 state → 从记录的 phase 继续

### 2. 阶段路由(委托 loop-evolve references)

前 13 阶段(scan → gate3)**委托** loop-evolve 的 reference 执行,执行前注入上下文:
- state 文件用 `<hanflow_repo>/.contribute/state.yaml`
- 锁用 `<hanflow_repo>/.contribute/lock`
- 产物目录用 `<hanflow_repo>/.contribute/contributions/<cycle_id>/`

委托路径:`~/.codex/agents/skills/loop-evolve/references/<phase>.md`

特殊阶段:
- `check_occupied`:跑 `~/.codex/agents/skills/contribute-pr/scripts/check-occupied.sh <hanflow_repo>`(去重)
- `submit`:本 skill 专属,见 Step 3

### 3. submit 阶段(本 skill 专属)

- **S0 质量门**:跑 `pr-readiness-check.sh <hanflow_repo>`(charter 复核 + lint + commits)
- **S1-S2 发 PR**:跑 `submit.sh <hanflow_repo> hanflow`(fork 同步 + push + gh pr create)
- **S4 归档**:跑 `write-contribution.sh <hanflow_repo>` + `refresh-status.sh <hanflow_repo>`

### 4. 命令变体

| 触发短语 | 行为 |
|---------|------|
| `contribute-pr` / 默认 | 从当前 phase 继续 |
| `contribute-pr topic <描述>` | 跳过选题,直接指定主题进 plan |
| `contribute-pr docs <描述>` | 纯文档贡献,跳到 hanflow-home 走简化 submit |
| `contribute-pr status` | 打印当前 state |
| `contribute-pr refresh` | 刷新本机贡献档案状态 |
| `contribute-pr abort` | 终止 + 清理凭证 |

### 5. 工具映射(Codex → 脚本调用)

Codex 执行本 skill 时,工具调用映射:
- "调用 Agent / 子 agent" → Codex 的 Task 工具
- "Edit/Write 文件" → Codex 的 apply_patch
- "执行 bash 脚本" → Codex 的 shell 工具(直接跑 `.sh`)
- "Read 文件" → Codex 原生读

### 6. 验证(每次贡献完成)

- PR URL 已回填到 state.submit.pr_code_url
- `.contribute/CONTRIBUTIONS.md` 多一条 status=open 记录
- `git remote -v` 无 token 残留(若用 PAT 路径)

## 备注

- Codex Skills 是 2025-12 上线的实验性机制,若 `codex /skills` 看不到本 skill,回退用
  AGENTS.md 片段(见 `../references/codex-adaptation.md` 的 fallback 段)
- 完整设计:`docs/superpowers/specs/2026-07-20-contribute-pr-skill-design.md`
