# 凭证处理与 fork 策略

contribute-pr 最敏感的部分。本文档含安全声明、两条凭证路径、fork 策略、token 抹除机制。

---

## 1. 安全声明(启动时必须先打印,在请求任何输入之前)

```
═══════════════════════════════════════════════════════════
  ⚠️  关于接下来要请求的 GitHub 凭证 — 请先阅读

  • 你即将提供的 Personal Access Token (PAT) 仅在本本机当前会话中
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

**打印时机**:SKILL.md 启动逻辑第 2 步,在任何输入请求之前。

---

## 2. 两条凭证路径(互斥,贡献者选一)

### 路径 A:默认 PAT 路径(零持久化,推荐)

贡献者创建 fine-grained PAT(权限见安全声明),skill 用 token 构造**临时 push remote URL**:

```bash
# 临时 remote URL 带 token (仅本会话, 不写持久配置)
FORK_URL="https://<token>@github.com/<user>/hanflow.git"
git -C <hanflow_path> remote add contribute-fork "$FORK_URL"
# push 完成后抹除 token (见 §4)
git -C <hanflow_path> remote set-url contribute-fork "https://github.com/<user>/hanflow.git"
```

**技术保证**:
1. token 只在临时 remote URL 里,**绝不**写入 `~/.git-credentials`、`.git/config` 持久字段、
   或任何全局配置
2. push 完成后立即 `git remote set-url` 抹除
3. 脚本用 `trap ... EXIT INT TERM` 保证 Ctrl+C 也抹除
4. CONTRIBUTIONS.md 只记 PR URL,**绝不**记 token

**这是 skill 的默认安全路径**——安全声明针对此路径承诺"零持久化"。

### 路径 B:`gh auth login` 替代路径(贡献者主动选择)

部分贡献者更愿意用 `gh auth login` 走浏览器 OAuth(完全不给 skill 任何 token 字符串)。

**这条路径下 token 由 gh 存入其 credential store**(macOS Keychain / Windows Credential
Manager / `~/.config/gh/hosts.yml`),**这是持久的**。与路径 A 的"零持久化"不同。

**协调方式**(避免与路径 A 的安全承诺冲突):

- skill **不主动推荐** gh auth login(避免与默认路径的安全承诺冲突)
- 仅在贡献者询问或 PAT 不可用时作为替代方案告知
- 贡献者明确选择此方式时,skill **追加打印一行**:

  ```
  ℹ️  你选择 gh auth login,凭证将由 gh 存入本机 credential store(持久)。
      Hanflow 不接触该凭证。如不希望持久化,改用 PAT 路径(默认)。
  ```

- 把持久化的**知情权交给贡献者**,不假装两条路径安全级别一致

### 路径选择流程

```
检测 gh auth status
├─ 已登录 → 询问贡献者:"检测到 gh 已登录,沿用(凭证由 gh 持久存储,路径 B)
│            还是改用 PAT(路径 A,零持久化)?[默认 A]"
└─ 未登录 → 默认走路径 A(PAT),按 §3 引导 PAT 输入 + fork
```

---

## 3. fork 策略(两条凭证路径通用)

两条路径,skill 自动选:

### 路径 1:首选 `gh repo fork`(gh 已登录时最干净)

```bash
gh repo fork xpc1024/hanflow --clone=false --remote
```

gh 自动在贡献者账号下创建 fork并配置 remote。

**remote 命名冲突规避**:hanflow 仓库已配置 `origin`(gitee)和 `github`(xpc1024 SSH)
两个 remote。gh fork 默认命名 remote 为 `origin`,会与既有冲突。故 gh fork 后需:

```bash
# gh 默认把 fork 命名为 origin (与既有冲突), 改名为 contribute-fork
git -C <hanflow_path> remote rename origin contribute-fork
# 或 gh fork 时指定: gh repo fork ... --remote-name contribute-fork (若 gh 版本支持)
```

### 路径 2:回退手动 fork(gh fork 失败或贡献者已有 fork)

提示贡献者:

```
请在 https://github.com/xpc1024/hanflow 点 Fork(若已有 fork 可跳过)。
完成后告诉我你的 fork URL(如 https://github.com/<你的用户名>/hanflow)。
```

skill 读到 fork URL 后:

```bash
# 路径 A (PAT): remote URL 带 token
FORK_URL_WITH_TOKEN="https://<token>@github.com/<user>/hanflow.git"
git -C <hanflow_path> remote add contribute-fork "$FORK_URL_WITH_TOKEN"

# 路径 B (gh auth): 直接用 https URL, gh credential helper 自动认证
git -C <hanflow_path> remote add contribute-fork "https://github.com/<user>/hanflow.git"
```

### 共性

两条路径都不要求贡献者提前 clone 自己的 fork——工作副本就是当前 hanflow 仓库,只是多了
一个指向 fork 的 remote(名 `contribute-fork`)。

---

## 4. token 抹除机制(S4 关键安全步骤)

**仅路径 A(PAT)需要抹除**;路径 B(gh auth)的 token 在 gh credential store,由 gh 管理,
skill 不接触,无需抹除。

路径 A 的抹除:

```bash
# 把 contribute-fork 的 URL 从带 token 改回干净 URL
CLEAN_URL="https://github.com/<user>/hanflow.git"
git -C <hanflow_path> remote set-url contribute-fork "$CLEAN_URL"
```

**可靠抹除保证**:

1. submit 脚本用 `trap ... EXIT INT TERM`,在脚本退出时(正常或 Ctrl+C)执行抹除:

   ```bash
   CLEANUP_DONE=0
   _cleanup_token() {
     if [ "$CLEANUP_DONE" -eq 0 ] && [ -n "${FORK_USER:-}" ]; then
       CLEAN_URL="https://github.com/$FORK_USER/hanflow.git"
       git -C "$HANFLOW_PATH" remote set-url contribute-fork "$CLEAN_URL" 2>/dev/null || true
       CLEANUP_DONE=1
     fi
   }
   trap _cleanup_token EXIT INT TERM
   ```

2. 抹除后**校验**:`git remote get-url contribute-fork` 输出不应含 `@`(token 分隔符)

3. **抹除失败必须显式报告**(spec §8.1 S4 失败决策树):

   ```
   ⚠️  token 抹除失败!安全残留。
       手动清理:git -C <hanflow_path> remote set-url contribute-fork https://github.com/<user>/hanflow.git
       或:git -C <hanflow_path> remote remove contribute-fork
   ```

4. CONTRIBUTIONS.md 只记 PR URL,**绝不**记 token(写入前 grep 校验无 token 格式)

---

## 5. PAT 权限不足的处理

push 时返回 403 时:

```
ERROR: PAT 权限不足。请确认你的 fine-grained PAT:
  - Contents: Read and Write  ✓ 必需
  - Pull requests: Read and Write  ✓ 必需
  - Repository access: 勾选了你的 hanflow fork  ✓ 必需

不重试(权限问题重试无意义)。修好 token 后重跑 /contribute-pr。
```

---

## 6. 安全审计(可选,P0 不强制)

贡献者可自行验证 token 未残留:

```bash
# 1. 检查 git remote URL 不含 token
git -C <hanflow_path> remote -v | grep contribute-fork
# 应输出: contribute-fork  https://github.com/<user>/hanflow.git (fetch/push)
# 不应含 <token>@

# 2. 检查 .git/config 不含 token
grep -r "<你的token前几位>" <hanflow_path>/.git/config  # 应无结果

# 3. 检查 ~/.git-credentials 未被写入
grep "github.com" ~/.git-credentials 2>/dev/null | grep "<user>/hanflow"  # 应无结果
```
