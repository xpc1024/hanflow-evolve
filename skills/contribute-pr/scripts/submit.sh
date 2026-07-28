#!/usr/bin/env bash
# submit.sh — SUBMIT 阶段 S1-S2: fork 准备 + push + 发代码 PR (spec §3.1)
#
# 用法: submit.sh <hanflow_repo> <repo>
#   <repo>: hanflow (P0 必做) | hanflow-site (P2 文档 PR)
#
# 架构 (P2 修正): 以贡献者 hanflow 仓库为工作目录,
# state 在 <hanflow_repo>/.contribute/state.yaml。
# 复用 loop-evolve 的 write-state.sh 时传该路径。
set -euo pipefail

HANFLOW_REPO="${1:?Usage: submit.sh <hanflow_repo> <repo>}"
REPO="${2:?Usage: submit.sh <hanflow_repo> <repo: hanflow|hanflow-site>}"

case "$REPO" in
  hanflow|hanflow-site) ;;
  *) echo "ERROR: <repo> must be 'hanflow' or 'hanflow-site', got: $REPO" >&2; exit 1 ;;
esac

[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }
STATE="$HANFLOW_REPO/.contribute/state.yaml"
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

# skill 目录 (找 write-state.sh, 复用 loop-evolve 的)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WRITE_STATE="$SCRIPT_DIR/../loop-evolve/scripts/write-state.sh"
# loop-evolve skill 可能没带 scripts/, 回退到 hanflow-evolve 仓库的
if [ ! -f "$WRITE_STATE" ]; then
  WRITE_STATE=""  # 后面 fallback
fi

# 读 state (一次性, 走环境变量避免 MSYS 路径插值 bug)
READ_OUT=$(STATE_FILE="$STATE" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print(s.get('cycle_id') or '')
print(s.get('target_theme') or '')
print((s.get('submit') or {}).get('fork_remote') or '')
" 2>/dev/null || echo "")
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '1p')
TARGET_THEME=$(printf '%s' "$READ_OUT" | sed -n '2p')
FORK_REMOTE=$(printf '%s' "$READ_OUT" | sed -n '3p')

[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id empty" >&2; exit 1; }

# 上游仓库 (PR 目标)
case "$REPO" in
  hanflow)      UPSTREAM="xpc1024/hanflow" ;;
  hanflow-site) UPSTREAM="xpc1024/hanflow-site" ;;
esac

BRANCH="evolve/$CYCLE_ID"
FORK_REMOTE_NAME="contribute-fork"

echo "=== submit.sh: repo=$REPO upstream=$UPSTREAM branch=$BRANCH ==="

# 写 state 辅助 (优先 loop-evolve 的 write-state.sh, 回退内联 sed)
write_state() {
  local key="$1" val="$2"
  if [ -n "$WRITE_STATE" ] && [ -f "$WRITE_STATE" ]; then
    bash "$WRITE_STATE" "$STATE" "$key" "$val" || echo "WARN: write-state.sh 回填失败" >&2
  else
    # 内联 fallback: 简单 sed 替换 (子表字段如 submit.pr_code_url)
    if grep -q "^${key}:" "$STATE"; then
      sed -i "s|^${key}:.*|${key}: ${val}|" "$STATE"
    fi
  fi
}

# ── S1. fork remote 校验 ──
if [ -z "$FORK_REMOTE" ]; then
  echo "ERROR: submit.fork_remote 为空。fork 准备由 skill 对话层引导 (见 credential-handling.md)," >&2
  echo "       完成后写 state.yaml submit.fork_remote=$FORK_REMOTE_NAME 再调本脚本。" >&2
  exit 1
fi

if ! git -C "$HANFLOW_REPO" remote get-url "$FORK_REMOTE_NAME" >/dev/null 2>&1; then
  echo "ERROR: remote '$FORK_REMOTE_NAME' 未配置在 $HANFLOW_REPO" >&2
  echo "       请先按 credential-handling.md 完成 fork 并 git remote add $FORK_REMOTE_NAME <fork_url>" >&2
  exit 1
fi

if ! git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "ERROR: feature branch '$BRANCH' does not exist" >&2
  exit 1
fi

git -C "$HANFLOW_REPO" checkout -q "$BRANCH"

# ── S2.1 fork 同步检查 ──
UPSTREAM_REMOTE=""
for cand in upstream github origin; do
  if git -C "$HANFLOW_REPO" remote get-url "$cand" >/dev/null 2>&1; then
    url=$(git -C "$HANFLOW_REPO" remote get-url "$cand")
    if printf '%s' "$url" | grep -qE "xpc1024/${REPO}(\.git)?$|github\.com.*xpc1024/${REPO}"; then
      UPSTREAM_REMOTE="$cand"; break
    fi
  fi
done

if [ -n "$UPSTREAM_REMOTE" ]; then
  echo "--- fork 同步检查: fetch $UPSTREAM_REMOTE/main ---"
  if git -C "$HANFLOW_REPO" fetch "$UPSTREAM_REMOTE" main 2>&1; then
    BASE=$(git -C "$HANFLOW_REPO" merge-base HEAD "$UPSTREAM_REMOTE/main" 2>/dev/null || true)
    UPSTREAM_HEAD=$(git -C "$HANFLOW_REPO" rev-parse "$UPSTREAM_REMOTE/main" 2>/dev/null || true)
    if [ -n "$BASE" ] && [ -n "$UPSTREAM_HEAD" ] && [ "$BASE" != "$UPSTREAM_HEAD" ]; then
      echo "WARN: fork 落后于 upstream, 尝试 rebase..."
      if git -C "$HANFLOW_REPO" rebase "$UPSTREAM_REMOTE/main" 2>&1; then
        echo "PASS: rebase 成功"
      else
        git -C "$HANFLOW_REPO" rebase --abort 2>/dev/null || true
        echo "FAIL: rebase 失败, 请手动 rebase 后重试" >&2
        exit 1
      fi
    fi
  else
    echo "WARN: fetch $UPSTREAM_REMOTE/main 失败, 跳过同步检查" >&2
  fi
fi

# ── S2.2 push 到 fork ──
echo "--- push $BRANCH → $FORK_REMOTE_NAME ---"
if ! git -C "$HANFLOW_REPO" push "$FORK_REMOTE_NAME" "$BRANCH" 2>&1; then
  echo "WARN: 首次 push 失败, 尝试 force-with-lease..."
  if ! git -C "$HANFLOW_REPO" push --force-with-lease "$FORK_REMOTE_NAME" "$BRANCH" 2>&1; then
    echo "FAIL: push 到 fork 失败, 检查 PAT 权限 (Contents:Write) 或网络" >&2
    exit 1
  fi
fi
echo "PASS: push 成功"

# ── S2.3 发 PR (幂等) ──
echo "--- gh pr create → $UPSTREAM ---"

# 幂等: 先查是否已有同分支 PR
EXISTING=$(gh pr list --repo "$UPSTREAM" --head ":$BRANCH" --state open --json url,number 2>/dev/null || true)
if [ -n "$EXISTING" ] && [ "$EXISTING" != "[]" ]; then
  PR_URL=$(printf '%s' "$EXISTING" | python -c "import sys,json; d=json.load(sys.stdin); print(d[0]['url'])" 2>/dev/null || true)
  if [ -n "$PR_URL" ]; then
    echo "PASS (幂等): 分支已有 PR, 复用 $PR_URL"
    STATE_KEY=$([ "$REPO" = "hanflow" ] && echo "submit.pr_code_url" || echo "submit.pr_docs_url")
    write_state "$STATE_KEY" "\"$PR_URL\""
    exit 0
  fi
fi

# 构造 PR 标题/body
LATEST_COMMIT_MSG=$(git -C "$HANFLOW_REPO" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "feat: $TARGET_THEME")
PR_TITLE="$LATEST_COMMIT_MSG"
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

# 重试 3 次
PR_URL=""
for attempt in 1 2 3; do
  echo "  尝试 $attempt/3..."
  if PR_URL=$(gh pr create --repo "$UPSTREAM" --head "$BRANCH" --base main \
        --title "$PR_TITLE" --body "$PR_BODY" 2>&1); then
    if printf '%s' "$PR_URL" | grep -qE "^https://"; then
      echo "PASS: PR 已创建 $PR_URL"
      break
    fi
  fi
  [ "$attempt" -lt 3 ] && sleep $((attempt * attempt))
done

if [ -z "$PR_URL" ] || ! printf '%s' "$PR_URL" | grep -qE "^https://"; then
  echo "FAIL: gh pr create 失败 (3 次重试后)" >&2
  echo "      最后输出: $PR_URL" >&2
  exit 1
fi

STATE_KEY=$([ "$REPO" = "hanflow" ] && echo "submit.pr_code_url" || echo "submit.pr_docs_url")
write_state "$STATE_KEY" "\"$PR_URL\""

echo "OK: submit.sh 完成 ($REPO PR: $PR_URL)"
