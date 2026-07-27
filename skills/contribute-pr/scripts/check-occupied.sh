#!/usr/bin/env bash
# check-occupied.sh — 选题阶段去重钩子 Level 1 (spec §5.1, §5.2)
#
# 用法: check-occupied.sh <evolve_home>
#
# 行为 (Level 1 精确匹配, P1 实现; Level 2 语义近似留 P2):
#   1. 查上游 GitHub PR (hanflow + hanflow-site) 取分支名/标题/state
#   2. 读本地 CONTRIBUTIONS.md 取 status/theme 字段
#   3. 对候选主题(从 state-contribute.yaml.artifacts.signals 或 BACKLOG 读)做精确匹配
#   4. 输出每个候选的占用状态: OCCUPIED / merged(可增量) / closed(已拒) / 空闲
#
# gh 不可用时降级: 只读本地 CONTRIBUTIONS.md + WARN, 不阻断
#
# 返回: 0=检查完成(无论是否有冲突, 由调用方/skill 决定如何处理), 非0=脚本本身错误
set -euo pipefail

EVOLVE_HOME="${1:?Usage: check-occupied.sh <evolve_home>}"
if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONTRIB_FILE="$EVOLVE_HOME/CONTRIBUTIONS.md"
STATE="$EVOLVE_HOME/state-contribute.yaml"

# ── 1. 收集占用数据源 ──
echo "=== check-occupied (Level 1) ==="

GH_AVAILABLE=1
gh auth status >/dev/null 2>&1 || GH_AVAILABLE=0

# 上游 PR 列表 (分支名 + 标题 + state), 存临时文件
TMP_PR=$(mktemp)
trap 'rm -f "$TMP_PR"' EXIT

if [ "$GH_AVAILABLE" -eq 1 ]; then
  echo "数据源: GitHub PR"
  # hanflow PR
  gh pr list --repo xpc1024/hanflow --state all --limit 200 \
    --json number,title,headRefName,state 2>/dev/null >> "$TMP_PR" || true
  # hanflow-site PR (追加, 用分隔)
  echo "" >> "$TMP_PR"
  gh pr list --repo xpc1024/hanflow-site --state all --limit 200 \
    --json number,title,headRefName,state 2>/dev/null >> "$TMP_PR" || true
else
  echo "WARN: gh 未认证, 未查上游 GitHub, 去重不完整(跨贡献者去重失效)。" >&2
  echo "      建议先 gh auth login 或提供 PAT。本机档案去重仍生效。" >&2
fi

# ── 2. 收集候选主题 ──
# 优先从 state-contribute.yaml.artifacts.signals 读候选; 若无则提示从 BACKLOG 读
CANDIDATES_TMP=$(mktemp)
trap 'rm -f "$TMP_PR" "$CANDIDATES_TMP"' EXIT

# 候选主题提取: 从 signals.json 的 theme_id 字段 (若 artifacts.signals 指向有效文件)
SIGNALS_FILE=""
if [ -f "$STATE" ]; then
  SIGNALS_FILE=$(python -c "
import yaml
s = yaml.safe_load(open('$STATE', encoding='utf-8'))
arts = s.get('artifacts') or {}
print(arts.get('signals') or '')
" 2>/dev/null || echo "")
fi

if [ -n "$SIGNALS_FILE" ] && [ -f "$EVOLVE_HOME/$SIGNALS_FILE" ]; then
  # 从 signals.json 提取 theme_id + affected_modules
  python -c "
import json
d = json.load(open('$EVOLVE_HOME/$SIGNALS_FILE', encoding='utf-8'))
themes = d.get('themes') or d.get('candidates') or []
if isinstance(themes, list):
    for t in themes:
        tid = t.get('theme_id') or t.get('id') or ''
        mods = ','.join(t.get('affected_modules') or [])
        print(f'{tid}\t{mods}')
elif isinstance(themes, dict):
    for tid, t in themes.items():
        mods = ','.join(t.get('affected_modules') or [])
        print(f'{tid}\t{mods}')
" 2>/dev/null > "$CANDIDATES_TMP" || true
fi

if [ ! -s "$CANDIDATES_TMP" ]; then
  echo "INFO: 无候选主题(可能尚未跑 scan/prioritize, 或 signals.json 格式不同)。" >&2
  echo "      check-occupied 跳过(无候选可查)。" >&2
  exit 0
fi

CAND_COUNT=$(wc -l < "$CANDIDATES_TMP" | tr -d ' ')
echo "候选主题: $CAND_COUNT 个"

# ── 3. Level 1 精确匹配 ──
echo ""
echo "候选主题检查:"

OCCUPIED_COUNT=0
MERGED_COUNT=0
FREE_COUNT=0

while IFS=$'\t' read -r THEME_ID MODULES; do
  [ -z "$THEME_ID" ] && continue

  STATUS_HINT=""
  CONFLICT_REF=""

  # 3a. 查 GitHub PR 的分支名/标题是否含 theme_id
  if [ -s "$TMP_PR" ]; then
    # 匹配 PR (headRefName 含 theme_id, 或 title 含 theme_id)
    PR_MATCH=$(grep -iE "\"(headRefName|title)\".*\"[^\"]*${THEME_ID}[^\"]*\"" "$TMP_PR" 2>/dev/null | head -1 || true)
    if [ -n "$PR_MATCH" ]; then
      # 提取该 PR 的 state 和 number
      PR_STATE=$(printf '%s' "$PR_MATCH" | python -c "
import sys, json, re
line = sys.stdin.read()
# 从 grep 到的行附近找 state (简化: 整个 TMP_PR 解析)
" 2>/dev/null || echo "")
      # 简化处理: 重新查该 theme 在 PR json 里的 state
      PR_INFO=$(python -c "
import json, re
content = open('$TMP_PR', encoding='utf-8').read()
# 尝试解析多个 json 数组 (hanflow + hanflow-site 拼接)
chunks = [c for c in re.split(r'\n\s*\n', content) if c.strip()]
for chunk in chunks:
    try:
        items = json.loads(chunk)
        if not isinstance(items, list): continue
        for it in items:
            head = (it.get('headRefName') or '')
            title = (it.get('title') or '')
            if '${THEME_ID}' in head or '${THEME_ID}' in title:
                print(f\"{it.get('state','')}#{it.get('number','')}\")
                break
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
  fi

  # 3b. 查本地 CONTRIBUTIONS.md (status + theme)
  if [ -z "$STATUS_HINT" ] && [ -f "$CONTRIB_FILE" ]; then
    # 找包含该 theme 的记录块
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

  # 3c. 输出
  if [ -z "$STATUS_HINT" ]; then
    echo "  [$THEME_ID] → 空闲"
    FREE_COUNT=$((FREE_COUNT + 1))
  elif [ "$STATUS_HINT" = "OCCUPIED" ]; then
    echo "  [$THEME_ID] → OCCUPIED (活跃 PR: $CONFLICT_REF) [硬 skip]"
    OCCUPIED_COUNT=$((OCCUPIED_COUNT + 1))
  elif [ "$STATUS_HINT" = "merged" ]; then
    echo "  [$THEME_ID] → 已 merged ($CONFLICT_REF), 可做增强版 [降权+提示]"
    MERGED_COUNT=$((MERGED_COUNT + 1))
  elif [ "$STATUS_HINT" = "closed" ]; then
    echo "  [$THEME_ID] → closed/已拒 ($CONFLICT_REF), 查看原因后再决定 [降权+提示]"
    MERGED_COUNT=$((MERGED_COUNT + 1))
  fi
done < "$CANDIDATES_TMP"

# ── 4. 汇总 ──
echo ""
echo "=== 汇总 ==="
echo "  空闲(可选): $FREE_COUNT"
echo "  已交付/closed(可增量,需提示): $MERGED_COUNT"
echo "  OCCUPIED(硬 skip): $OCCUPIED_COUNT"
echo ""
if [ "$FREE_COUNT" -gt 0 ]; then
  echo "建议: 优先选空闲主题; merged/closed 的可做增量但需向贡献者说明上下文。"
else
  echo "WARN: 无空闲主题。考虑用 /contribute-pr topic <描述> 直接指定主题。" >&2
fi

echo "OK: check-occupied 完成 (Level 1)"
