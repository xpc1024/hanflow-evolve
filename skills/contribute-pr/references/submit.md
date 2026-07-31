# SUBMIT — 发 PR(P0 核心)

本阶段是 contribute-pr 唯一新写的阶段,替代 loop-evolve 的 release。
前置:gate3 已 approved,代码已在 `evolve/$CYCLE_ID` 分支且 verify 全绿。

## 流程总览

```
S0.  就绪检查(质量门)─── 发 PR 前最后一道闸
S0.5 版本判断 ─── 读 semver-rules.md + commit/diff → BUMP_TYPE + NEW_VERSION(MAJOR 警告暂停)
S1.  凭证与 fork 准备(首次才做)
S2.  代码 PR(主,必做)── push 到 fork + gh pr create 到上游
S3.  文档 PR(可选)── 仅 user-facing 变更才触发(S6.1 判定 DOC_NEEDED)
S4.  归档与清理 ─── 写 CONTRIBUTIONS.md + 抹 token + state.phase=submitted
S5.  贡献者名录登记(无条件必做)── honor PR 到 hanflow-home,与 S6 合并发一个 home-sync PR
S6.  文档 + 版本同步(条件)── DOC_NEEDED=1 才发文档;NEW_VERSION 非空才更新版本切换器
```

> **⚠️ S0.5 版本判断与 S5 名录登记是 submit 的必做步骤,不是可选项。**
> 即使本次无 user-facing 变更(S3/S6 文档跳过),仍必须:(1) 跑 S0.5 算 BUMP_TYPE 并改
> `hanflow/__init__.py`(patch/minor);(2) 跑 S5 发名录 PR。执行者**不得在 S4 后直接置
> `phase=submitted` 收尾**。下文的 home-sync 段是 S0.5 + S5 + S6 三步的**实现**,
> 不是"可选增强"。历史教训:曾有纯 `build:`/`chore:` 贡献因整段跳过 home-sync,导致
> 版本号未升级、contributors.json 未登记(见 hanflow-evolve LEARNINGS)。

---

## S0. 就绪检查(质量门)

**定位**:verify(P12)已覆盖测试 + smoke + auto-fix。S0 **不重复测试**,只补 verify 不覆盖的
"提交就绪性"检查。诚实讲,把测试再跑一遍是和 verify 重复劳动。

执行 `bash scripts/pr-readiness-check.sh <hanflow_repo>`:

| 检查项 | 来源 | 说明 |
|--------|------|------|
| charter-check 复核 | `scripts/charter-check/charter-check.sh` | audit 已做,S0 是双保险,确保不变量仍满足 |
| 代码格式/lint | ruff/mypy(hanflow 项目约定) | verify 不覆盖,S0 补 |
| 提交历史合规 | conventional commits,无 WIP/草稿提交 | verify 不覆盖,S0 补 |
| 文档同步检查 | 若 user-facing 变更,确认文档 PR 同步发 | P0 跳过,P1 末或 P2 实现 |

**结果处理**:
- 全部通过 → `write-state.sh state-contribute.yaml submit.quality verified`,进入 S1
- 任一失败 → **回 code 阶段修复**,写 `phase=code` + `last_error`,不发出半成品 PR
  (贡献者怀疑 gate3 后代码状态,可手动重跑测试,但 S0 不自动跑)

---

## S1. 凭证与 fork 准备(首次才做)

**前置**:读 state-contribute.yaml,若 `submit.fork_remote` 已存在则跳过本步。

详细凭证处理见 `credential-handling.md`,此处仅骨架:

1. **检测 gh auth status**:
   - 已登录 → 直接用(但提示贡献者:gh credential store 是持久的,见 credential-handling.md §替代路径)
   - 未登录 → 引导 PAT 输入(默认路径,零持久化)

2. **确认/创建 fork**(两条路径,详见 credential-handling.md):
   - 首选 `gh repo fork xpc1024/hanflow --clone=false`
   - 回退手动 fork,贡献者提供 fork URL

3. **配置 fork remote**(命名 `contribute-fork`,规避与既有 `origin`/`github` 撞名):
   ```bash
   # 把 fork 加为 hanflow 仓库的 remote
   git -C <hanflow_path> remote add contribute-fork <fork_url>
   # 若用 PAT 路径,remote URL 临时带 token(见 credential-handling.md)
   ```

4. 写 state:`submit.fork_remote=contribute-fork`

---

## S2. 代码 PR(主,必做)

执行 `bash scripts/submit.sh <hanflow_repo> hanflow`:

> 注:启动时的 `preflight-sync.sh contrib` 已把本地 main 同步到真正上游并把 main 推到 fork
> (保证 fork 不滞后)。下面的 fork 同步检查作为**双重保险**保留(feature 分支 rebase 到最新 upstream/main)。

1. **fork 同步检查**:fetch upstream main,若 fork 落后则 rebase(失败决策见 §8.1)
2. **push 到 fork**:`git push contribute-fork evolve/$CYCLE_ID`
3. **发 PR**:
   ```bash
   gh pr create --repo xpc1024/hanflow \
     --head <contributor>:evolve/$CYCLE_ID \
     --base main \
     --title "<conventional-commit-summary>" \
     --body "<PR 模板,见下方>"
   ```
4. **幂等处理**:若 gh pr create 报"分支已有 PR",调 `gh pr list --head <branch>` 取已存在
   PR URL,**视为成功**(spec §8.1)
5. **回填**:`write-state.sh state-contribute.yaml submit.pr_code_url <url>`

### PR 描述模板(数据式,引用脚本真实输出)

```markdown
## 🤖 Hanflow 社区贡献 (via contribute-pr skill)

**主题**: <target_theme>
**contribution_id**: <cycle_id 值,如 contrib-2026-W30-001>

### 质量验证(本地已通过,维护者可侧重评估需求价值)
- verify 阶段(P12): 测试全绿 + smoke PASS [N/4]
- S0 提交前检查: CHARTER 守护 PASS(errors/async-api/pydantic-data/registry/layering)
                  + lint 零告警 + conventional commits ✓

### 变更摘要
<由 design.md 的 summary 自动填充>

### 关联
- 设计文档: contributions/<cycle_id>/design.md 要点
- 测试报告: contributions/<cycle_id>/test-report.md 摘要

### 自进化产物
本 PR 由 Hanflow 自进化体系生成,遵循 CHARTER.md 设计不变量,
经 scan→design→code→verify 全流程 + 提交前质量门(S0)。

---
贡献者: @<github_username>
```

模板填充规则:
- `PASS [N/4]`、charter-check 五脚本名来自脚本真实输出,**不手写编造指标**
- `contribution_id` 显示用 cycle_id 的值(字段同构,见 SKILL.md)
- "侧重评估"而非"仅需"(本地 S0 ≠ CI 必绿,见 spec §8.3)

---

## S3. 文档 PR(可选,第二站)〔P2,P0 跳过〕

仅当本次涉及 user-facing 变更(CLI/DSL/API/schema/config)才触发。判定复用 loop-evolve
release.md 的 site_sync_needed 逻辑(扫 feat:/BREAKING commits)。

仓库指向 **hanflow-home**(github-only,无 gitee,Vercel 部署):
```bash
bash scripts/submit.sh <hanflow_repo> hanflow-home
```

文档版本目录:`content/<version>/<locale>/`(当前 1.0.1,locale en+zh)。

**P0 不实现 S3**——只发代码 PR,文档同步由维护者 release 时处理。

---

## S4. 归档与清理

1. **写贡献档案**:`bash scripts/write-contribution.sh <hanflow_repo>`
   追加一条记录到 CONTRIBUTIONS.md:
   ```markdown
   ## <cycle_id> · <type>: <summary> · @<username>
   - status: open
   - quality: verified
   - pr_code: <pr_code_url>
   - pr_docs: <pr_docs_url 或 ->
   - theme: <target_theme>
   - affected_modules: <列表>
   - created: <date>
   - merged: -
   ```

2. **刷新状态**(触发点 1):`bash scripts/refresh-status.sh <hanflow_repo>`
   校验刚发的 PR URL 真实可达,写完整记录。

3. **抹除 token**(默认 PAT 路径):
   ```bash
   git -C <hanflow_path> remote set-url contribute-fork <clean_url_without_token>
   ```
   脚本用 `trap ... EXIT INT TERM` 保证即使 Ctrl+C 也执行。**抹除失败必须显式报告**
   并给出手动清理命令(spec §8.1)。

4. **更新 state**:
   ```bash
   write-state.sh state-contribute.yaml phase submitted
   write-state.sh state-contribute.yaml submit.token_redacted true
   ```

---

## home-sync: hanflow-home 单一 PR(S5名录 + S6文档 + 版本同步)— 必做

> **本段是 submit 的必做收尾**(S0.5 + S5 + S6 三步的实现),不是可选增强。
> S5 名录登记**无条件必做**;S0.5 版本判断对任何 commit prefix 都要跑(`build:`/`chore:`
> 同样触发 PATCH)。详见流程总览段的 ⚠️ 提示。

submit 的最后阶段,合并发一个 PR 到 hanflow-home(spec 2026-07-29-doc-sync-s6-design.md)。

### S0.5 版本判断(S2 前)

AI 读 `references/semver-rules.md`,根据 commit prefix + 公开 API 变更判断 BUMP_TYPE:
- `feat:` → MINOR(1.X.0)
- `fix:`/`refactor:`/`docs:`/`build:`/`chore:`/`style:`/`perf:`/`test:`/`ci:` → PATCH(1.0.X)
- `BREAKING CHANGE`/`!` → MAJOR(X.0.0,警告暂停)

结果 NEW_VERSION:S2 改框架 `__init__.py` + pyproject.toml;home-sync 改官网 `package.json`(versions.ts 由 build 时 gen-versions.mjs 自动生成)。

### home-sync 执行

执行 `bash scripts/home-sync.sh <hanflow_repo> <hanflow_home_repo> [new_version]`:

- S5 名录登记:追加 contributors.json(无条件,幂等)
- S6.1 文档判断:doc-sync-judge.sh 匹配 doc-mapping.yaml
- S6.2-S6.3(若 user-facing):AI 生成 zh+en 文档 → 贡献者 git diff review
- 版本同步(若有 NEW_VERSION):package.json + 大版本线(minor/patch 原地合并到 content/<major>.x/,major 才 cp -r 新线;versions.ts 数据驱动)
- 发一个 PR:home/<cycle_id> 到 xpc1024/hanflow-home

回填 state.submit.pr_home_url。

**MVP 不自动刷新 pr_status**(初始 open)。

---

## 失败恢复决策树(详见 spec §8.1)

| 失败点 | 处理 |
|--------|------|
| S0 任一项失败 | 回 code 阶段修复,不推进;不重试 S0 |
| S1 PAT 权限不足(403) | 明确报错,不重试,等贡献者修 token |
| S1 gh repo fork 失败 | 提示手动 fork,读 fork URL |
| S2 push 被拒(non-ff) | fetch upstream + rebase,重试一次;再失败报告 |
| S2 gh pr create 撞分支 | gh pr list 取已存在 PR URL,视为成功(幂等) |
| S2 gh pr create 网络失败 | 重试 3 次(指数退避),仍失败保留本地提交,state 保持 submit |
| S2 代码 PR 成功但文档 PR 失败 | 代码 PR URL 已回填,文档失败记 last_error,提示稍后重试 |
| S4 write-contribution 失败 | PR 已发,下次启动 refresh-status 从 GitHub 反向补全 |
| S4 token 抹除失败 | 安全残留,显式报告 + 手动清理命令 |

**核心原则**:submit 必须幂等——重跑不产生重复 PR、不丢已发 PR、不留 token。
