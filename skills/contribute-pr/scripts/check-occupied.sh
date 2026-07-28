#!/usr/bin/env bash
# check-occupied.sh — 选题阶段去重钩子 Level 1 (spec §5.1, §5.2)
#
# 用法: check-occupied.sh <hanflow_repo>
#
# 架构 (P2 修正): state/CONTRIBUTIONS 在 <hanflow_repo>/.contribute/。
set -euo pipefail

HANFLOW_REPO="${1:?Usage: check-occupied.sh <hanflow_repo>}"
[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }

CONTRIB_DIR="$HANFLOW_REPO/.contribute"
CONTRIB_FILE="$CONTRIB_DIR/CONTRIBUTIONS.md"
STATE="$CONTRIB_DIR/state.yaml"

echo "=== check-occupied (Level 1) ==="

GH_AVAILABLE=1
gh auth status >/dev/null 2>&1 || GH_AVAILABLE=0

TMP_PR=$(mktemp)
trap 'rm -f "$TMP_PR" "$CANDIDATES_TMP"' EXIT
CANDIDATES_TMP=$(mktemp)

if [ "$GH_AVAILABLE" -eq 1 ]; then
  echo "数据源: GitHub PR"
  gh pr list --repo xpc1024/hanflow --state all --limit 200 \
    --json number,title,headRefName,state 2>/dev/null >> "$TMP_PR" || true
  echo "" >> "$TMP_PR"
  gh pr list --repo xpc1024/hanflow-site --state all --limit 200 \
    --json number,title,headRefName,state 2>/dev/null >> "$TMP_PR" || true
else
  echo "WARN: gh 未认证, 未查上游 GitHub, 去重不完整(跨贡献者去重失效)。" >&2
  echo "      建议先 gh auth login 或提供 PAT。本机档案去重仍生效。" >&2
fi

# 候选主题: 从 state.artifacts.signals 读 (若有效)
# 路径走环境变量, 不插值进 python -c (MSYS 兼容, 对齐 signal-gather.sh 约定)
SIGNALS_FILE=""
if [ -f "$STATE" ]; then
  SIGNALS_FILE=$(STATE_FILE="$STATE" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((s.get('artifacts') or {}).get('signals') or '')
" 2>/dev/null || echo "")
fi

# 拼接绝对路径 (SIGNALS_FILE 是相对 hanflow_repo 的)
SCORED_ABS="$HANFLOW_REPO/$SIGNALS_FILE"
if [ -n "$SIGNALS_FILE" ] && [ -f "$SCORED_ABS" ]; then
  SCORED_FILE="$SCORED_ABS" python -c "
import json, os
d = json.load(open(os.environ['SCORED_FILE'], encoding='utf-8'))
themes = d.get('themes') or d.get('candidates') or []
if isinstance(themes, list):
    for t in themes:
        print(f\"{t.get('theme_id') or t.get('id') or ''}\t{','.join(t.get('affected_modules') or [])}\")
elif isinstance(themes, dict):
    for tid, t in themes.items():
        print(f\"{tid}\t{','.join(t.get('affected_modules') or [])}\")
" 2>/dev/null > "$CANDIDATES_TMP" || true
fi

if [ ! -s "$CANDIDATES_TMP" ]; then
  echo "INFO: 无候选主题(可能尚未跑 scan/prioritize)。check-occupied 跳过。" >&2
  exit 0
fi

CAND_COUNT=$(wc -l < "$CANDIDATES_TMP" | tr -d ' ')
echo "候选主题: $CAND_COUNT 个"
echo ""
echo "候选主题检查:"

OCCUPIED_COUNT=0; MERGED_COUNT=0; FREE_COUNT=0

while IFS=$'\t' read -r THEME_ID MODULES; do
  [ -z "$THEME_ID" ] && continue
  STATUS_HINT=""; CONFLICT_REF=""

  # 查 GitHub PR
  if [ -s "$TMP_PR" ]; then
    PR_INFO=$(PR_FILE="$TMP_PR" THEME="$THEME_ID" python -c "
import json, os, re
content = open(os.environ['PR_FILE'], encoding='utf-8').read()
theme = os.environ['THEME']
chunks = [c for c in re.split(r'\n\s*\n', content) if c.strip()]
for chunk in chunks:
    try:
        items = json.loads(chunk)
        if not isinstance(items, list): continue
        for it in items:
            head = (it.get('headRefName') or ''); title = (it.get('title') or '')
            if theme in head or theme in title:
                print(f\"{it.get('state','')}#{it.get('number','')}\"); break
    except: pass
" 2>/dev/null || echo "")
    if [ -n "$PR_INFO" ]; then
      PR_STATE=$(printf '%s' "$PR_INFO" | cut -d'#' -f1)
      PR_NUM=$(printf '%s' "$PR_INFO" | cut -d'#' -f2)
      CONFLICT_REF="PR #$PR_NUM"
      case "$PR_STATE" in
        OPEN|open) STATUS_HINT="OCCUPIED" ;;
        MERGED|merged) STATUS_HINT="merged" ;;
        CLOSED|closed) STATUS_HINT="closed" ;;
      esac
    fi
  fi

  # 查本地 CONTRIBUTIONS.md
  if [ -z "$STATUS_HINT" ] && [ -f "$CONTRIB_FILE" ]; then
    CONTRIB_STATUS=$(awk -v tid="$THEME_ID" '
      /^## / { block=""; match_theme=0 }
      { block = block $0 "\n" }
      $0 ~ ("- theme: " tid) { match_theme=1 }
      /^- status: / && match_theme { gsub(/^- status: /, "", $0); gsub(/[^a-zA-Z]/, "", $0); print; exit }
    ' "$CONTRIB_FILE" 2>/dev/null || true)
    case "$CONTRIB_STATUS" in
      open) STATUS_HINT="OCCUPIED"; CONFLICT_REF="本地 CONTRIBUTIONS.md (open)" ;;
      merged) STATUS_HINT="merged"; CONFLICT_REF="本地 CONTRIBUTIONS.md (merged)" ;;
      closed) STATUS_HINT="closed"; CONFLICT_REF="本地 CONTRIBUTIONS.md (closed)" ;;
    esac
  fi

  if [ -z "$STATUS_HINT" ]; then
    echo "  [$THEME_ID] → 空闲"; FREE_COUNT=$((FREE_COUNT + 1))
  elif [ "$STATUS_HINT" = "OCCUPIED" ]; then
    echo "  [$THEME_ID] → OCCUPIED (活跃 PR: $CONFLICT_REF) [硬 skip]"; OCCUPIED_COUNT=$((OCCUPIED_COUNT + 1))
  elif [ "$STATUS_HINT" = "merged" ]; then
    echo "  [$THEME_ID] → 已 merged ($CONFLICT_REF), 可做增强版 [降权+提示]"; MERGED_COUNT=$((MERGED_COUNT + 1))
  elif [ "$STATUS_HINT" = "closed" ]; then
    echo "  [$THEME_ID] → closed/已拒 ($CONFLICT_REF) [降权+提示]"; MERGED_COUNT=$((MERGED_COUNT + 1))
  fi
done < "$CANDIDATES_TMP"

echo ""
echo "=== 汇总 ==="
echo "  空闲(可选): $FREE_COUNT"
echo "  已交付/closed(可增量,需提示): $MERGED_COUNT"
echo "  OCCUPIED(硬 skip): $OCCUPIED_COUNT"
echo "OK: check-occupied 完成 (Level 1)"
