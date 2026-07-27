#!/usr/bin/env bash
# write-contribution.sh — SUBMIT 阶段 S4: 原子追加 CONTRIBUTIONS.md (spec §5.3)
#
# 用法: write-contribution.sh <hanflow_repo>
#
# 架构 (P2 修正): CONTRIBUTIONS.md 放 <hanflow_repo>/.contribute/,
# 不依赖 evolve-home。
set -euo pipefail

HANFLOW_REPO="${1:?Usage: write-contribution.sh <hanflow_repo>}"
[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }

CONTRIB_DIR="$HANFLOW_REPO/.contribute"
CONTRIB_FILE="$CONTRIB_DIR/CONTRIBUTIONS.md"
STATE="$CONTRIB_DIR/state.yaml"
mkdir -p "$CONTRIB_DIR"
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

# 读 state
READ_OUT=$(STATE_FILE="$STATE" python -c "
import yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print(s.get('cycle_id') or '')
print(s.get('target_theme') or '')
submit = s.get('submit') or {}
print(submit.get('pr_code_url') or '-')
print(submit.get('pr_docs_url') or '-')
print(submit.get('quality') or 'null')
" 2>/dev/null || python -c "
import os, yaml
s = yaml.safe_load(open('$STATE', encoding='utf-8'))
print(s.get('cycle_id') or '')
print(s.get('target_theme') or '')
submit = s.get('submit') or {}
print(submit.get('pr_code_url') or '-')
print(submit.get('pr_docs_url') or '-')
print(submit.get('quality') or 'null')
")
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '1p')
TARGET_THEME=$(printf '%s' "$READ_OUT" | sed -n '2p')
PR_CODE=$(printf '%s' "$READ_OUT" | sed -n '3p')
PR_DOCS=$(printf '%s' "$READ_OUT" | sed -n '4p')
QUALITY=$(printf '%s' "$READ_OUT" | sed -n '5p')

[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id empty" >&2; exit 1; }

# 幂等
if [ -f "$CONTRIB_FILE" ] && grep -q "^## $CYCLE_ID ·" "$CONTRIB_FILE" 2>/dev/null; then
  echo "WARN: CONTRIBUTIONS.md 已有 $CYCLE_ID 记录, 不重复追加 (幂等)" >&2
  exit 0
fi

# 取贡献者用户名
USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
[ "$USERNAME" = "unknown" ] && echo "WARN: 无法获取 GitHub 用户名, 记为 unknown" >&2

# 取 affected_modules
BRANCH="evolve/$CYCLE_ID"
AFFECTED="-"
# 找 base 分支
BASE_BRANCH=""
for cand in upstream/main origin/main origin/master main master; do
  if git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>/dev/null || \
     git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/remotes/$cand" >/dev/null 2>/dev/null; then
    BASE_BRANCH="$cand"; break
  fi
done
if [ -n "$BASE_BRANCH" ] && git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  FILES=$(git -C "$HANFLOW_REPO" diff --name-only "$BASE_BRANCH..$BRANCH" 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')
  [ -n "$FILES" ] && AFFECTED="$FILES"
fi

# type + summary
LATEST_MSG=$(git -C "$HANFLOW_REPO" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "")
TYPE=$(printf '%s' "$LATEST_MSG" | sed -nE 's/^([a-z]+)(\(.+\))?!?:.*/\1/p')
[ -z "$TYPE" ] && TYPE="feat"
SUMMARY=$(printf '%s' "$LATEST_MSG" | sed -nE 's/^[a-z]+(\(.+\))?!: *//p')
[ -z "$SUMMARY" ] && SUMMARY="$TARGET_THEME"

TODAY=$(date +%Y-%m-%d)

RECORD=$(cat <<EOF

## $CYCLE_ID · $TYPE: $SUMMARY · @$USERNAME
- status: open
- quality: $QUALITY
- pr_code: $PR_CODE
- pr_docs: $PR_DOCS
- theme: $TARGET_THEME
- affected_modules: $AFFECTED
- created: $TODAY
- merged: -
EOF
)

# 原子追加 (flock)
LOCK_FILE="$CONTRIB_DIR/.contributions.lock"
(
  flock -x 200
  if [ ! -f "$CONTRIB_FILE" ]; then
    cat > "$CONTRIB_FILE" <<'HEADER'
# CONTRIBUTIONS.md — 社区贡献档案 (本机本地)

> 由 contribute-pr skill 自动追加。每条记录一次贡献的全生命周期。
> 用途:(1) 离线去重(gh 不可用时兜底)  (2) 本贡献者自己的历史(本机可见)
>
> 诚实定位:本文件是单机本地档案,不是分布式同步的数据库。
> 跨贡献者去重完全依赖 GitHub PR 查询(spec §5.2)。

---

HEADER
  fi
  TMP="${CONTRIB_FILE}.tmp"
  cp "$CONTRIB_FILE" "$TMP"
  printf '%s\n' "$RECORD" >> "$TMP"
  mv "$TMP" "$CONTRIB_FILE"
) 200>"$LOCK_FILE"

echo "OK: CONTRIBUTIONS.md 已追加 $CYCLE_ID 记录 (status=open, @$USERNAME)"
