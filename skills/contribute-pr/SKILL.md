---
name: contribute-pr
description: 面向无写权限的社区成员,复用 Hanflow 自进化体系(loop-evolve)的全流程,
  以 Pull Request 形式提交贡献。支持 /contribute-pr (默认从当前阶段继续)
  /contribute-pr topic <描述> (贡献者直接指定主题,跳过选题)
  /contribute-pr status (只读) /contribute-pr refresh (刷新本机贡献档案状态)
  /contribute-pr gate approve|revise|reject (Gate 确认)
  /contribute-pr docs <描述> (纯文档贡献,跳到 hanflow-home)
  /contribute-pr abort (终止并清理 token)
  当用户说"给 hanflow 提 PR""社区贡献""contribute-pr"时触发。
  跨工具支持:ZCode / Claude Code(Claude Code 见 references/claude-code-adaptation.md);
  Codex 见 references/codex-adaptation.md。
---

# Contribute-PR — Hanflow 社区贡献 PR Skill

面向**无 `xpc1024/hanflow` 写权限**的社区成员。复用 loop-evolve 的前 13 阶段
(scan→gate3),唯一差异:最后一步**发 PR 而非 merge to main**。

完整设计见 spec:
`E:\opensource\docs\superpowers\specs\2026-07-20-contribute-pr-skill-design.md`

## 启动逻辑

1. **前置校验(第一件事)**:确认 loop-evolve skill 可达。
   本 skill 委托复用 loop-evolve 的 references,必须先确认其存在:

   ```
   期望路径(install.sh 装到 ~/.zcode/skills/):
     ~/.zcode/skills/loop-evolve/references/*.md
   ```

   若不可达,报错并提示贡献者:
   ```
   ERROR: contribute-pr 依赖 loop-evolve skill 的 reference 文件。
   请确保已通过 install.sh 安装(它会同时安装 contribute-pr + loop-evolve)。

   一键安装:
     curl -fsSL https://raw.githubusercontent.com/xpc1024/hanflow-evolve/main/install.sh | bash

   或手动:
     git clone https://github.com/xpc1024/hanflow-evolve
     cd hanflow-evolve && bash install.sh
   ```
   **不继续**——无 loop-evolve references 委托会失败。

2. **打印安全声明(第二件事,在任何输入请求之前)**:见下方"凭证安全声明"小节,
   或完整版见 `references/credential-handling.md`。

3. **定位工作目录**:贡献者 clone 的 hanflow 仓库(如 `~/hanflow-dev/hanflow`)。
   本 skill 以该仓库为工作中心,state/锁/CONTRIBUTIONS 都放其 `.contribute/` 子目录:

   ```
   <hanflow_repo>/.contribute/
   ├── state.yaml          # 本 skill 唯一状态(字段同构 loop-evolve, 文件独立)
   ├── CONTRIBUTIONS.md    # 贡献档案(本机本地)
   ├── lock                # 并发锁
   └── adr/                # charter-check 白名单(空, 贡献者无 ADR)
   ```

   **重要**:首次贡献时,若 `<hanflow_repo>/.contribute/` 不存在,自动创建。
   并提示贡献者把 `.contribute/` 加入 hanflow 仓库的 `.gitignore`(避免提交本地状态):

   ```
   echo ".contribute/" >> <hanflow_repo>/.gitignore
   ```

4. **读 `.contribute/state.yaml`**:
   - 无 state.yaml 或 `phase == "uninitialized"` → 从 scan 开始新贡献
   - `phase` 是普通阶段(scan/prioritize/check_occupied/.../verify/submit)且无 `last_error` → 继续
   - `phase` 是 `gateN` 且 `gate_status == "awaiting_user"` → 提示 Gate 确认
   - `phase == "submitted"` → 上次贡献已完成,询问是否开始新贡献
   - `last_error` 非空 → 报告错误,按 spec §8.1 恢复决策树询问如何继续

5. **刷新本机档案(可选,触发点 2)**:若 CONTRIBUTIONS.md 有 status=open 记录,
   启动时调 `scripts/refresh-status.sh <hanflow_repo>` 刷新。失败不阻断(离线可继续)。

6. **获取并发锁**:`source scripts/acquire-lock.sh <hanflow_repo>`
   锁文件 `<hanflow_repo>/.contribute/lock`(与 loop-evolve 完全独立,可并行)。

7. **启动强制拉取最新代码(贡献模式)**:加锁**之后**、进阶段**之前**,把工作仓库同步到
   真正主仓库(`xpc1024/<repo>`)的最新 main,并保证 fork 不滞后:

   ```
   bash scripts/preflight-sync.sh contrib <hanflow_repo> [hanflow_home_repo]
   ```

   - 拉取的是**真正上游**(按候选 `upstream|github|origin` 取 URL 含 `xpc1024/<repo>` 的 remote),
     **不是 fork**;上游有滞后则合并进本地 main(ff-only 优先,分叉则 merge 保留 fork 独有提交)。
   - 若配置了 fork remote(`contribute-fork` / `contribute-fork-home`),把同步后的 main 推到 fork,
     保证 fork 不滞后;之后 feature 分支 `evolve/$CYCLE_ID` 正常开发/在 submit 时 rebase。
   - docs 子命令需同时传 `<hanflow_home_repo>`。
   - 失败不阻断(离线可继续)。详见 `scripts/preflight-sync.sh`。

8. **进入对应阶段**,按阶段路由执行。

## 字段同构(委托跑通的前提,关键约束)

contribute-pr 的 `state-contribute.yaml` **字段名与 loop-evolve 的 state.yaml 完全一致**
(`cycle_id` / `phase` / `artifacts` / `gate_status` / `last_error` 等),仅文件名不同。
语义区分通过**值的前缀**实现:

- `cycle_id` 的值用 `contrib-` 前缀(如 `contrib-2026-W30-001`),loop-evolve 用
  `<周序>-<版本>`(如 `2026-W29-1.0.2`)。字段名相同,值可区分。
- 分支名 `evolve/$CYCLE_ID` → `evolve/contrib-2026-W30-001`,PR 列表靠 `contrib-` 前缀区分。
- `target_version` 保留字段名但**恒为 null**(贡献不改版本号,release 阶段不执行)。

**代价**:`cycle_id` 语义在 contribute-pr 实为"contribution_id",轻微混淆。这是换取
委托复用可靠性的主动选择(spec §1.2)。

## 委托复用机制

前 13 阶段(scan 到 gate3)**不复制** loop-evolve 的 reference 内容,而是委托执行。
**委托时的上下文注入**(每个委托阶段执行前,必须告知执行者):

- 工作目录:贡献者 clone 的 hanflow 仓库(`$HANFLOW_REPO`)
- state 文件:`$HANFLOW_REPO/.contribute/state.yaml`(不是 loop-evolve 的 state.yaml)
- 锁文件:`$HANFLOW_REPO/.contribute/lock`(不是 loop-evolve 的 .loop.lock)
- 产物目录:`$HANFLOW_REPO/.contribute/contributions/<cycle_id>/`(不是 cycles/)
- `write-state.sh` 调用:第一个参数传 `$HANFLOW_REPO/.contribute/state.yaml`
- `acquire-lock.sh`:用本 skill 自带版本(独立锁路径)

委托路径(install.sh 装到 skill 目录,可靠):
```
~/.zcode/skills/loop-evolve/references/<phase>.md
```

## 阶段路由

| phase | 执行方式 | reference |
|-------|---------|-----------|
| scan | 委托 | `skills/loop-evolve/references/scan.md` |
| prioritize | 委托 | `skills/loop-evolve/references/prioritize.md` |
| check_occupied | **本 skill** | `references/check-occupied.md` + `scripts/check-occupied.sh`(Level 1,P1) |
| human_topic | 委托 | `skills/loop-evolve/references/human-topic.md` |
| plan | 委托 | `skills/loop-evolve/references/plan.md` |
| audit_direction | 委托 | `skills/loop-evolve/references/audit.md` |
| gate1 | 委托(inline gate) | loop-evolve gate 行为 |
| design | 委托 | `skills/loop-evolve/references/design.md` |
| audit_design | 委托 | `skills/loop-evolve/references/audit.md` |
| gate2 | 委托(inline gate) | loop-evolve gate 行为 |
| plan_exec | 委托 | `skills/loop-evolve/references/execute.md` |
| code | 委托 | `skills/loop-evolve/references/code.md` |
| verify | 委托 | `skills/loop-evolve/references/verify.md` |
| gate3 | 委托(inline gate) | loop-evolve gate 行为 |
| submit | **本 skill** | `references/submit.md`(含 S0 质量门 + S0.5 版本判断 + S1-S6;S0.5 版本判断 + S5 名录登记**必做**,经 home-sync 合并发一个 hanflow-home PR) |

## 命令变体

| 命令 | 行为 |
|------|------|
| `/contribute-pr` | 默认:读 state-contribute.yaml 继续当前阶段;无 state 则从 scan 开始 |
| `/contribute-pr topic <描述>` | 跳过 scan/prioritize/check_occupied,贡献者指定主题,直接进 plan |
| `/contribute-pr status` | 只读:打印当前 state + CONTRIBUTIONS.md 本机 open 记录 |
| `/contribute-pr refresh` | 只刷新 CONTRIBUTIONS.md 的 open 记录状态(spec §5.4 触发点 3) |
| `/contribute-pr gate approve\|revise\|reject` | Gate 确认(委托 loop-evolve gate 行为) |
| `/contribute-pr docs <描述>` | 纯文档贡献:跳到 hanflow-home 直接走 submit(P2) |
| `/contribute-pr abort` | 终止当前贡献,**清理 token**(从 git remote URL 抹除) |

## `/contribute-pr docs <描述>` 子命令流程(P2)

纯文档贡献(修错别字、补示例、改 contribute-pr.mdx 等)的专用路径,**跳过 scan→code 全流程**,
直接对 hanflow-home(官网源)走简化 submit。流程:

```
1. 定位 hanflow-home 仓库 (默认 $HANFLOW_DEV_DIR/hanflow-home, 或询问贡献者)
2. 创建 feature 分支 evolve/<cycle_id> 在 hanflow-home (cycle_id 用 docs- 前缀, 如 docs-2026-W30-001)
3. 贡献者在 hanflow-home 里改文档 (人工或 AI 辅助, 不走 scan/design/code)
4. 提交 (conventional commits, 用 docs: 前缀)
5. S0 (docs 降级): bash scripts/pr-readiness-check-docs.sh <hanflow_home_repo>
   - 只跑 npm run build + conventional commits (跳过 charter/lint/mypy)
6. submit: bash scripts/submit.sh <hanflow_home_repo> hanflow-home
   - fork 同步 + push + gh pr create 到 xpc1024/hanflow-home
7. 归档: bash scripts/write-contribution.sh <hanflow_home_repo> (CONTRIBUTIONS.md 记一条)
```

**与默认流程的差异**:
- 跳过 scan/prioritize/check_occupied/plan/design/code/verify(选题→编码全流程)
- cycle_id 用 `docs-` 前缀(而非 `contrib-`),分支名 `evolve/docs-xxx`,PR 列表易区分
- S0 用文档专用脚本(`pr-readiness-check-docs.sh`),不跑代码质量门
- submit.sh 参数 `<repo>` 传 `hanflow-home`(PR 发到 xpc1024/hanflow-home)

## S6 文档内容同步(submit 内自动)— home-sync 为必做

> **home-sync 是 submit 的必做收尾**(不是可选)。即使本次非 user-facing(文档跳过),
> 仍必须跑 S0.5 版本判断 + S5 名录登记。详见 `references/submit.md` 流程总览 ⚠️ 提示。

submit 的 home-sync 阶段会自动判断是否需要更新官网文档(spec 2026-07-29-doc-sync-s6-design.md):

1. **S0.5 版本判断**(S2 前,**必做**):AI 读 `references/semver-rules.md` + commit/diff → BUMP_TYPE(major/minor/patch)+ NEW_VERSION
   - MAJOR:警告暂停(社区贡献一般不 breaking)
   - 任何 commit prefix 都要判断:`feat:`→MINOR,`fix:/build:/chore:/...`→PATCH
   - 结果传给 S2(改框架 `__init__.py`)+ home-sync(改官网 `lib/versions.ts`)
2. **S5 名录登记**(home-sync 内,**无条件必做**):追加 contributors.json(无论是否 user-facing)
3. **S6.1 文档判断**(home-sync 内,**条件**):`doc-sync-judge.sh` 读代码 diff 匹配 `doc-mapping.yaml`
   - 非 user-facing → 跳过文档
   - user-facing → AI 生成 zh+en 文档草稿 → 贡献者 git diff review
4. **home-sync 合并 PR**:名录(contributors.json)+ 文档(若有)+ 版本切换器(若有)合并发一个 hanflow-home PR

**docs 子命令不 bump 版本**(文档修订不改变软件版本)。

## 子命令执行路径

非默认流程的子命令,直接调脚本,不进阶段循环(`<hanflow_repo>` 是贡献者 clone 的 hanflow 仓库):

| 子命令 | 执行路径 |
|--------|---------|
| `/contribute-pr status` | 读 `.contribute/state.yaml` 打印;读 `.contribute/CONTRIBUTIONS.md` 打印本机 open 记录摘要 |
| `/contribute-pr refresh` | `bash scripts/refresh-status.sh <hanflow_repo>`(spec §5.4 触发点 3) |
| `/contribute-pr gate approve\|revise\|reject` | 委托 loop-evolve gate 行为,写 gate_status 后推进/回退 |
| `/contribute-pr abort` | 抹 token(`git remote set-url contribute-fork <clean_url>`)+ 删 `.contribute/lock` + state 标 aborted |

## 阶段循环内的脚本调用

| phase | 脚本 |
|-------|------|
| check_occupied(2.5) | `bash scripts/check-occupied.sh <hanflow_repo>`(Level 1,P1) |
| submit.S0 | `bash scripts/pr-readiness-check.sh <hanflow_repo>` |
| submit.S2 | `bash scripts/submit.sh <hanflow_repo> hanflow` |
| submit.S3(P2) | `bash scripts/submit.sh <hanflow_repo> hanflow-home` |
| submit.S4 | `bash scripts/write-contribution.sh <hanflow_repo>` + `bash scripts/refresh-status.sh <hanflow_repo>` |
| submit.S0.5 | 版本判断(AI 读 semver-rules.md + commit/diff → BUMP_TYPE + NEW_VERSION;MAJOR 警告暂停) |
| submit.home-sync | `bash scripts/home-sync.sh <hanflow_repo> <hanflow_home_repo> [new_version]`(**必做**:S5 名录无条件登记 + S0.5 版本判断 + S6 文档(条件);合并一个 hanflow-home PR。**不得在 S4 后跳过**) |

## 凭证安全声明(启动时必须先打印,在请求任何输入之前)

```
═══════════════════════════════════════════════════════════
  ⚠️  关于接下来要请求的 GitHub 凭证 — 请先阅读

  • 你即将提供的 Personal Access Token (PAT) 仅在本机当前会话中
    使用,用于把你写的代码 push 到【你自己的 fork】并向上游发 PR。
  • Hanflow 不会上传、转发、存储你的 token。它只在本机 git/gh
    的本地配置里临时存在,流程结束后会被自动从 git remote URL
    中移除。
  • 我们【强烈建议】你创建一个 fine-grained PAT,权限仅限:
      - Contents: Read and Write
      - Pull requests: Read and Write
      - Repository access: 仅勾选【你自己的 hanflow fork】
    这样即使 token 泄漏,影响范围也只是你自己的 fork。
  • 全程不需要你的 GitHub 账号密码,不需要 OAuth 授权任何第三方
    应用。你随时可以在 GitHub Settings → Developer settings →
    Personal access tokens 一键撤销。
═══════════════════════════════════════════════════════════
```

完整凭证处理(默认 PAT 路径零持久化、gh auth login 替代路径、fork 策略、token 抹除)
见 `references/credential-handling.md`。

## 关键约束

- `state-contribute.yaml` 是本 skill 唯一状态真相源(字段同构 loop-evolve state.yaml,
  文件独立),每次阶段转换用 `scripts/write-state.sh` 原子更新(传 state-contribute.yaml 路径)
- Gate 阶段不自动推进,必须等用户 approve/revise/reject
- 所有阶段产物落盘到 `contributions/<cycle_id>/`(不是 loop-evolve 的 `cycles/`)
- **不污染** loop-evolve 资源:不写 state.yaml、不写 BACKLOG.md、不写 LEARNINGS.md
  (LEARNINGS 只读)、不用 .loop.lock
- submit 必须幂等:重跑不产生重复 PR(gh pr create 撞分支视为成功取已存在 URL)
- token 在 submit 结束后必须从 git remote URL 抹除(trap EXIT/INT/TERM 保证)

## 跨工具适配

- **ZCode**:本 skill 主体工具中立,直接用 `/contribute-pr` 触发
- **Claude Code**:几乎同构,差异见 `references/claude-code-adaptation.md`
- **Codex**:无原生 Skill 工具,用 AGENTS.md 注入,见 `references/codex-adaptation.md`
