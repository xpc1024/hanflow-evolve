---
name: contribute-pr
description: 面向无写权限的社区成员,复用 Hanflow 自进化体系(loop-evolve)的全流程,
  以 Pull Request 形式提交贡献。支持 /contribute-pr (默认从当前阶段继续)
  /contribute-pr topic <描述> (贡献者直接指定主题,跳过选题)
  /contribute-pr status (只读) /contribute-pr refresh (刷新本机贡献档案状态)
  /contribute-pr gate approve|revise|reject (Gate 确认)
  /contribute-pr docs <描述> (纯文档贡献,跳到 hanflow-site)
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
   期望路径(仓库内,与 contribute-pr 同源):
     <hanflow-evolve>/skills/loop-evolve/references/*.md
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

3. **定位 evolve 家目录**:`E:\opensource\hanflow-evolve`(或 `$HANFLOW_EVOLVE_DIR`)。
   读 `state-contribute.yaml`(注意:**不是** loop-evolve 的 `state.yaml`,字段同构但文件独立):

   - 无 state-contribute.yaml 或 `phase == "uninitialized"` → 从 scan 开始新贡献
   - `phase` 是普通阶段(scan/prioritize/check_occupied/human_topic/plan/audit_direction/
     design/audit_design/plan_exec/code/verify/submit)且无 `last_error` → 继续该阶段
   - `phase` 是 `gateN` 且 `gate_status == "awaiting_user"` → 提示 Gate 确认
   - `phase == "submitted"` → 上次贡献已完成,询问是否开始新贡献
   - `last_error` 非空 → 报告错误,按 spec §8.1 恢复决策树询问如何继续

4. **刷新本机档案(可选,触发点 2)**:若 CONTRIBUTIONS.md 存在且有 status=open 记录,
   启动时调 `scripts/refresh-status.sh` 刷新(spec §5.4)。失败不阻断(离线可继续)。

5. **获取并发锁**:`source scripts/acquire-lock.sh $EVOLVE_HOME`
   锁文件 `.loop-contribute.lock`(与 loop-evolve 的 `.loop.lock` **独立**,可并行)。

6. **进入对应阶段**,按阶段路由执行。

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

- state 文件:`hanflow-evolve/state-contribute.yaml`(不是 `state.yaml`)
- 锁文件:`.loop-contribute.lock`(不是 `.loop.lock`)
- 产物目录:`contributions/<cycle_id>/`(不是 `cycles/<cycle_id>/`)
- `write-state.sh` 调用:第一个参数传 `state-contribute.yaml` 路径
- `acquire-lock.sh`:用本 skill 自带版本(独立锁名)

委托路径(仓库内相对引用,可靠):
```
skills/loop-evolve/references/<phase>.md
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
| submit | **本 skill** | `references/submit.md`(含 S0 质量门 + S1-S4) |

## 命令变体

| 命令 | 行为 |
|------|------|
| `/contribute-pr` | 默认:读 state-contribute.yaml 继续当前阶段;无 state 则从 scan 开始 |
| `/contribute-pr topic <描述>` | 跳过 scan/prioritize/check_occupied,贡献者指定主题,直接进 plan |
| `/contribute-pr status` | 只读:打印当前 state + CONTRIBUTIONS.md 本机 open 记录 |
| `/contribute-pr refresh` | 只刷新 CONTRIBUTIONS.md 的 open 记录状态(spec §5.4 触发点 3) |
| `/contribute-pr gate approve\|revise\|reject` | Gate 确认(委托 loop-evolve gate 行为) |
| `/contribute-pr docs <描述>` | 纯文档贡献:跳到 hanflow-site 直接走 submit(P2) |
| `/contribute-pr abort` | 终止当前贡献,**清理 token**(从 git remote URL 抹除) |

## 子命令执行路径

非默认流程的子命令,直接调脚本,不进阶段循环:

| 子命令 | 执行路径 |
|--------|---------|
| `/contribute-pr status` | 读 state-contribute.yaml 打印;读 CONTRIBUTIONS.md 打印本机 open 记录摘要 |
| `/contribute-pr refresh` | `bash scripts/refresh-status.sh $EVOLVE_HOME`(spec §5.4 触发点 3) |
| `/contribute-pr gate approve\|revise\|reject` | 委托 loop-evolve gate 行为,写 gate_status 后推进/回退 |
| `/contribute-pr abort` | 抹 token(`git remote set-url contribute-fork <clean_url>`)+ 删 `.loop-contribute.lock` + state 标 aborted |

## 阶段循环内的脚本调用

| phase | 脚本 |
|-------|------|
| check_occupied(2.5) | `bash scripts/check-occupied.sh $EVOLVE_HOME`(Level 1,P1) |
| submit.S0 | `bash scripts/pr-readiness-check.sh $EVOLVE_HOME` |
| submit.S2 | `bash scripts/submit.sh $EVOLVE_HOME hanflow` |
| submit.S3(P2) | `bash scripts/submit.sh $EVOLVE_HOME hanflow-site` |
| submit.S4 | `bash scripts/write-contribution.sh $EVOLVE_HOME` + `bash scripts/refresh-status.sh $EVOLVE_HOME` |

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
