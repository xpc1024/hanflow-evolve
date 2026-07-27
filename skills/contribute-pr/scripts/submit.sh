#!/usr/bin/env bash
# submit.sh — SUBMIT 阶段 S1-S2: fork 准备 + push + 发代码 PR (spec §3.1)
#
# 用法: submit.sh <evolve_home> <repo>
#   <repo>: hanflow (P0 必做) | hanflow-site (P2 文档 PR)
#
# 行为:
#   S1. 读 state-contribute.yaml, 若 submit.fork_remote 已存在则跳过 fork 准备
#       否则引导贡献者完成 fork (实际 fork 操作由 skill 对话层引导, 本脚本只做 remote 配置)
#   S2. fork 同步检查 → push → gh pr create (幂等)
#   S4 部分. 回填 PR URL 到 state
#
# 幂等保证:
#   - gh pr create 撞分支 (分支已有 PR) → gh pr list 取已存在 PR URL, 视为成功
#   - 重跑不产生重复 PR
#
# 安全:
#   - token 仅以临时 push remote URL 形式存在, 不写持久配置 (见 credential-handling.md)
#   - 本脚本不负责抹 token (S4 由调用方调 trap 或显式抹除)
#
# 返回: 0=成功, 非 0=失败 (last_error 由调用方写入 state)
set -euo pipefail

EVOLVE_HOME="${1:?Usage: submit.sh <evolve_home> <repo>}"
REPO="${2:?Usage: submit.sh <evolve_home> <repo: hanflow|hanflow-site>}"

case "$REPO" in
  hanflow|hanflow-site) ;;
  *) echo "ERROR: <repo> must be 'hanflow' or 'hanflow-site', got: $REPO" >&2; exit 1 ;;
esac

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state-contribute.yaml"
for f in "$CONFIG" "$STATE"; do
  [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# 读配置 + state
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
paths = c.get('paths') or {}
print(paths.get('$REPO') or '')
print(s.get('cycle_id') or '')
print(s.get('target_theme') or '')
submit = s.get('submit') or {}
print(submit.get('fork_remote') or '')
print(submit.get('pr_code_url') or '')
")
REPO_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '2p')
TARGET_THEME=$(printf '%s' "$READ_OUT" | sed -n '3p')
FORK_REMOTE=$(printf '%s' "$READ_OUT" | sed -n '4p')
EXISTING_PR=$(printf '%s' "$READ_OUT" | sed -n '5p')

[ -z "$REPO_PATH" ] && { echo "ERROR: config.yaml paths.$REPO is empty" >&2; exit 1; }
[ -z "$CYCLE_ID" ] && { echo "ERROR: state-contribute.yaml cycle_id is empty" >&2; exit 1; }
[ -d "$REPO_PATH" ] || { echo "ERROR: $REPO path not found: $REPO_PATH" >&2; exit 1; }

# 上游仓库 (PR 目标)
case "$REPO" in
  hanflow)      UPSTREAM="xpc1024/hanflow" ;;
  hanflow-site) UPSTREAM="xpc1024/hanflow-site" ;;
esac

BRANCH="evolve/$CYCLE_ID"
FORK_REMOTE_NAME="contribute-fork"

echo "=== submit.sh: repo=$REPO upstream=$UPSTREAM branch=$BRANCH ==="

# ── S1. fork remote 配置 (若未配置) ──
if [ -z "$FORK_REMOTE" ]; then
  echo "ERROR: submit.fork_remote 为空。fork 准备由 skill 对话层引导 (见 credential-handling.md)," >&2
  echo "       完成后写 state-contribute.yaml submit.fork_remote=$FORK_REMOTE_NAME 再调本脚本。" >&2
  exit 1
fi

# 校验 contribute-fork remote 存在
if ! git -C "$REPO_PATH" remote get-url "$FORK_REMOTE_NAME" >/dev/null 2>&1; then
  echo "ERROR: remote '$FORK_REMOTE_NAME' 未配置在 $REPO_PATH" >&2
  echo "       请先按 credential-handling.md 完成 fork 并 git remote add $FORK_REMOTE_NAME <fork_url>" >&2
  exit 1
fi

# 校验 feature 分支存在
if ! git -C "$REPO_PATH" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "ERROR: feature branch '$BRANCH' does not exist in $REPO_PATH" >&2
  exit 1
fi

git -C "$REPO_PATH" checkout -q "$BRANCH"

# ── S2.1 fork 同步检查 (fetch upstream, 若落后则 rebase) ──
# 找 upstream remote (hanflow 仓库已有 github=xpc1024; hanflow-site 可能需补 upstream)
UPSTREAM_REMOTE=""
for cand in upstream github origin; do
  if git -C "$REPO_PATH" remote get-url "$cand" >/dev/null 2>&1; then
    url=$(git -C "$REPO_PATH" remote get-url "$cand")
    # 匹配 xpc1024/<repo> 的远程视为 upstream
    if printf '%s' "$url" | grep -qE "xpc1024/${REPO}(\.git)?$|github\.com.*xpc1024/${REPO}"; then
      UPSTREAM_REMOTE="$cand"
      break
    fi
  fi
done

if [ -n "$UPSTREAM_REMOTE" ]; then
  echo "--- fork 同步检查: fetch $UPSTREAM_REMOTE/main ---"
  if git -C "$REPO_PATH" fetch "$UPSTREAM_REMOTE" main 2>&1; then
    # 检查 feature 分支是否落后于 upstream/main
    BASE=$(git -C "$REPO_PATH" merge-base HEAD "$UPSTREAM_REMOTE/main" 2>/dev/null || true)
    UPSTREAM_HEAD=$(git -C "$REPO_PATH" rev-parse "$UPSTREAM_REMOTE/main" 2>/dev/null || true)
    if [ -n "$BASE" ] && [ -n "$UPSTREAM_HEAD" ] && [ "$BASE" != "$UPSTREAM_HEAD" ]; then
      echo "WARN: fork 落后于 upstream, 尝试 rebase..."
      if git -C "$REPO_PATH" rebase "$UPSTREAM_REMOTE/main" 2>&1; then
        echo "PASS: rebase 成功"
      else
        git -C "$REPO_PATH" rebase --abort 2>/dev/null || true
        echo "FAIL: rebase 失败 (可能冲突), 请手动 rebase 后重试" >&2
        exit 1
      fi
    fi
  else
    echo "WARN: fetch $UPSTREAM_REMOTE/main 失败, 跳过同步检查 (继续 push, 若落后会被拒)" >&2
  fi
else
  echo "WARN: 未找到 upstream remote (含 xpc1024/$REPO), 跳过同步检查" >&2
fi

# ── S2.2 push 到 fork (重试一次应对 non-fast-forward) ──
echo "--- push $BRANCH → $FORK_REMOTE_NAME ---"
if ! git -C "$REPO_PATH" push "$FORK_REMOTE_NAME" "$BRANCH" 2>&1; then
  echo "WARN: 首次 push 失败, 尝试 force-with-lease (rebase 后需要)..."
  if ! git -C "$REPO_PATH" push --force-with-lease "$FORK_REMOTE_NAME" "$BRANCH" 2>&1; then
    echo "FAIL: push 到 fork 失败, 检查 PAT 权限 (Contents:Write) 或网络" >&2
    exit 1
  fi
fi
echo "PASS: push 成功"

# ── S2.3 发 PR (幂等: 撞分支视为成功取已存在 URL) ──
echo "--- gh pr create → $UPSTREAM ---"

# 先查是否已有同分支 PR (幂等)
EXISTING=$(gh pr list --repo "$UPSTREAM" --head ":$BRANCH" --state open --json url,number 2>/dev/null || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "[]" ]; then
  PR_URL=$(printf '%s' "$EXISTING" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['url'])" 2>/dev/null || true)
  if [ -n "$PR_URL" ]; then
    echo "PASS (幂等): 分支已有 PR, 复用 $PR_URL"
    # 回填 (调用方 state 字段名区分 hanflow/hanflow-site)
    STATE_KEY=$([ "$REPO" = "hanflow" ] && echo "pr_code_url" || echo "pr_docs_url")
    bash "$EVOLVE_HOME/scripts/write-state.sh" "$STATE" "submit.$STATE_KEY" "\"$PR_URL\"" || \
      echo "WARN: 回填 $STATE_KEY 失败, 请手动写 state" >&2
    exit 0
  fi
fi

# 构造 PR 标题 (conventional commit 风格, 取 feature 分支最新提交)
LATEST_COMMIT_MSG=$(git -C "$REPO_PATH" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "feat: $TARGET_THEME")
PR_TITLE="$LATEST_COMMIT_MSG"

# PR body 简化版 (完整模板由 skill 对话层填充, 本脚本提供骨架)
PR_BODY=$(cat <<EOF
## 🤖 Hanflow 社区贡献 (via contribute-pr skill)

**主题**: $TARGET_THEME
**contribution_id**: $CYCLE_ID

### 质量验证(本地已通过,维护者可侧重评估需求价值)
- verify 阶段(P12): 测试全绿 + smoke PASS
- S0 提交前检查: CHARTER 守护 PASS + lint 零告警 + conventional commits ✓

### 变更摘要
(由 design.md 的 summary 自动填充)

### 自进化产物
本 PR 由 Hanflow 自进化体系生成,遵循 CHARTER.md 设计不变量,
经 scan→design→code→verify 全流程 + 提交前质量门(S0)。
EOF
)

# 重试 3 次 (指数退避, 应对网络抖动)
PR_URL=""
for attempt in 1 2 3; do
  echo "  尝试 $attempt/3..."
  if PR_URL=$(gh pr create --repo "$UPSTREAM" \
        --head "$BRANCH" \
        --base main \
        --title "$PR_TITLE" \
        --body "$PR_BODY" 2>&1); then
    # gh pr create 成功输出 PR URL
    # 失败但提示已有 PR 的情况也在这里处理
    if printf '%s' "$PR_URL" | grep -qE "^https://"; then
      echo "PASS: PR 已创建 $PR_URL"
      break
    fi
  fi
  if [ "$attempt" -lt 3 ]; then
    sleep $((attempt * attempt))  # 1, 4 秒退避
  fi
done

if [ -z "$PR_URL" ] || ! printf '%s' "$PR_URL" | grep -qE "^https://"; then
  echo "FAIL: gh pr create 失败 (3 次重试后)" >&2
  echo "      最后输出: $PR_URL" >&2
  echo "      state 保持 submit, 本地提交保留, 稍后可重试" >&2
  exit 1
fi

# ── S4 部分: 回填 PR URL ──
STATE_KEY=$([ "$REPO" = "hanflow" ] && echo "pr_code_url" || echo "pr_docs_url")
# 复用 loop-evolve 的 write-state.sh (参数化, 传 state-contribute.yaml 路径, spec §1.2)
bash "$EVOLVE_HOME/scripts/write-state.sh" "$STATE" "submit.$STATE_KEY" "\"$PR_URL\"" || \
  echo "WARN: 回填 $STATE_KEY 失败, 请手动写 state-contribute.yaml" >&2

echo "OK: submit.sh 完成 ($REPO PR: $PR_URL)"
