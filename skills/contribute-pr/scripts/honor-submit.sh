#!/usr/bin/env bash
# honor-submit.sh — SUBMIT 阶段 S5: 贡献者名录登记 (spec 2026-07-29 §2)
#
# 用法: honor-submit.sh <hanflow_repo> <hanflow_home_repo>
#
# 行为:
#   S5.0 校验 hanflow-home 的 contribute-fork-home remote (无则提示 fork)
#   S5.1 从 hanflow_repo/.contribute/state.yaml 读贡献信息
#   S5.2 追加一条到 hanflow_home_repo/data/contributors.json (幂等)
#   S5.3 在 hanflow-home 发 honor/<cycle_id> PR
#
# 无条件必做 (贡献行为本身值得记录, 无论是否 user-facing)。
set -euo pipefail

HANFLOW_REPO="${1:?Usage: honor-submit.sh <hanflow_repo> <hanflow_home_repo>}"
HANFLOW_HOME_REPO="${2:?Usage: honor-submit.sh <hanflow_repo> <hanflow_home_repo>}"

[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }
[ -d "$HANFLOW_HOME_REPO" ] || { echo "ERROR: hanflow_home_repo not found: $HANFLOW_HOME_REPO" >&2; exit 1; }

STATE="$HANFLOW_REPO/.contribute/state.yaml"
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

CONTRIB_JSON="$HANFLOW_HOME_REPO/data/contributors.json"
FORK_REMOTE="contribute-fork-home"
UPSTREAM="xpc1024/hanflow-home"

# ── S5.0 校验 hanflow-home 的 fork remote ──
if ! git -C "$HANFLOW_HOME_REPO" remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
  echo "ERROR: remote '$FORK_REMOTE' 未配置在 $HANFLOW_HOME_REPO" >&2
  echo "       请先 fork xpc1024/hanflow-home, 然后:" >&2
  echo "       git -C $HANFLOW_HOME_REPO remote add $FORK_REMOTE <你的 fork URL>" >&2
  exit 1
fi

# ── S5.1 读贡献信息 ──
READ_OUT=$(STATE_FILE="$STATE" HANFLOW_DIR="$HANFLOW_REPO" python -c "
import os, yaml, re, subprocess
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
hdir = os.environ['HANFLOW_DIR']
cid = s.get('cycle_id') or ''
submit = s.get('submit') or {}
pr_code = submit.get('pr_code_url') or ''
pr_docs = submit.get('pr_docs_url') or ''
pr_url = pr_code or pr_docs or ''
# version from hanflow/__init__.py
version = 'unknown'
init_path = os.path.join(hdir, 'hanflow', '__init__.py')
try:
    txt = open(init_path, encoding='utf-8').read()
    m = re.search(r'__version__\s*=\s*[\"\\']([^\"\\']+)', txt)
    if m: version = m.group(1)
except: pass
print(cid); print(pr_url); print(version)
" 2>/dev/null || echo "")
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '1p')
PR_URL=$(printf '%s' "$READ_OUT" | sed -n '2p')
VERSION=$(printf '%s' "$READ_OUT" | sed -n '3p')

[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id empty" >&2; exit 1; }
[ -z "$PR_URL" ] && { echo "ERROR: 无 PR URL (pr_code_url/pr_docs_url 都空), S5 需要 S2/docs 已发 PR" >&2; exit 1; }

# type + summary 从 feature 分支首个 commit
BRANCH="evolve/$CYCLE_ID"
FIRST_MSG=$(git -C "$HANFLOW_REPO" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "$CYCLE_ID")
TYPE=$(printf '%s' "$FIRST_MSG" | sed -nE 's/^([a-z]+)(\(.+\))?!?:.*/\1/p')
[ -z "$TYPE" ] && TYPE="other"
SUMMARY=$(printf '%s' "$FIRST_MSG" | sed -nE 's/^[a-z]+(\(.+\))?!: *//p')
[ -z "$SUMMARY" ] && SUMMARY="$CYCLE_ID"

# github_user + avatar (gh 优先, PAT 兜底)
USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
if [ -z "$USERNAME" ]; then
  # PAT 路径: 从 fork remote URL 提取用户名
  FORK_URL=$(git -C "$HANFLOW_REPO" remote get-url contribute-fork 2>/dev/null || echo "")
  USERNAME=$(printf '%s' "$FORK_URL" | sed -nE 's|.*github\.com[:/]([^/]+)/hanflow.*|\1|p')
  [ -z "$USERNAME" ] && USERNAME="unknown"
fi
AVATAR="https://github.com/${USERNAME}.png"
USER_URL="https://github.com/${USERNAME}"
TODAY=$(date +%Y-%m-%d)

echo "=== honor-submit: @$USERNAME / $TYPE: $SUMMARY / v$VERSION ==="

# ── S5.2 追加 contributors.json (幂等) ──
git -C "$HANFLOW_HOME_REPO" fetch "$FORK_REMOTE" main 2>/dev/null || true
HONOR_BRANCH="honor/$CYCLE_ID"
# 基于最新 main 切分支
git -C "$HANFLOW_HOME_REPO" checkout -B "$HONOR_BRANCH" "$FORK_REMOTE/main" 2>&1 | tail -1

# 幂等: 检查是否已有同 id
EXISTS=$(python -c "
import json, sys
try:
    d = json.load(open('$CONTRIB_JSON', encoding='utf-8'))
    ids = [c.get('id') for c in (d.get('contributions') or [])]
    sys.exit(0 if '$CYCLE_ID' in ids else 1)
except: sys.exit(1)
" 2>/dev/null && echo yes || echo no)
if [ "$EXISTS" = "yes" ]; then
  echo "WARN: contributors.json 已有 $CYCLE_ID 记录, 不重复追加 (幂等)"
  git -C "$HANFLOW_HOME_REPO" checkout main 2>/dev/null || true
  exit 0
fi

# 头部插入新记录 (用 python 保证 JSON 合法)
NEW_RECORD=$(cat <<EOF
{
  "id": "$CYCLE_ID",
  "github_user": "$USERNAME",
  "github_user_url": "$USER_URL",
  "avatar_url": "$AVATAR",
  "date": "$TODAY",
  "version": "$VERSION",
  "type": "$TYPE",
  "summary": "$SUMMARY",
  "pr_url": "$PR_URL",
  "pr_status": "open",
  "merged_at": null
}
EOF
)
RECORD="$NEW_RECORD" JSON_FILE="$CONTRIB_JSON" python -c "
import json, os
rec = json.loads(os.environ['RECORD'])
data = json.load(open(os.environ['JSON_FILE'], encoding='utf-8'))
contribs = data.get('contributions') or []
contribs.insert(0, rec)  # 头部插入 (最新在上)
data['contributions'] = contribs
with open(os.environ['JSON_FILE'], 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
"
echo "PASS: contributors.json 已追加 $CYCLE_ID"

git -C "$HANFLOW_HOME_REPO" add data/contributors.json
git -C "$HANFLOW_HOME_REPO" commit -m "honor(contributors): register @$USERNAME for $TYPE: $SUMMARY" 2>&1 | tail -1
git -C "$HANFLOW_HOME_REPO" push "$FORK_REMOTE" "$HONOR_BRANCH" 2>&1 | tail -1

# ── S5.3 发 PR ──
GH="/c/Program Files/GitHub CLI/gh.exe"
PR_BODY=$(cat <<EOF
## 🏆 贡献者名录登记 (via contribute-pr S5)

**贡献者**: @$USERNAME
**贡献类型**: $TYPE
**简述**: $SUMMARY
**关联 PR**: $PR_URL
**contribution_id**: $CYCLE_ID

### 变更
追加一条记录到 \`data/contributors.json\`:
- date: $TODAY
- version: v$VERSION
- pr_status: open

---
本 PR 由 contribute-pr skill 自动生成 (S5 贡献者名录登记)。
无论关联 PR 是否合并, 此登记都保留。
EOF
)
HONOR_PR=$(HTTPS_PROXY="${HTTPS_PROXY:-}" "$GH" pr create --repo "$UPSTREAM" \
  --head "$HONOR_BRANCH" --base main \
  --title "honor(contributors): register @$USERNAME for $TYPE: $SUMMARY" \
  --body "$PR_BODY" 2>&1 | grep -oE 'https://github.com/[^ ]+' | head -1 || echo "")
echo "OK: 贡献者名录登记 PR: $HONOR_PR"
