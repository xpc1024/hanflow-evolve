#!/usr/bin/env bash
# refresh-status.sh — 刷新 CONTRIBUTIONS.md 中 open 记录的状态 (spec §5.4)
#
# 用法: refresh-status.sh <hanflow_repo>
#
# 架构 (P2 修正): CONTRIBUTIONS.md 在 <hanflow_repo>/.contribute/。
set -euo pipefail

HANFLOW_REPO="${1:?Usage: refresh-status.sh <hanflow_repo>}"
[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }

CONTRIB_DIR="$HANFLOW_REPO/.contribute"
CONTRIB_FILE="$CONTRIB_DIR/CONTRIBUTIONS.md"

if [ ! -f "$CONTRIB_FILE" ]; then
  echo "INFO: CONTRIBUTIONS.md 不存在, 无记录可刷新" >&2
  exit 0
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "WARN: gh 未认证, 无法刷新状态 (跳过)" >&2
  exit 0
fi

OPEN_RECORDS=$(python -c "
import re
content = open('$CONTRIB_FILE', encoding='utf-8').read()
blocks = re.split(r'\n(?=## )', content)
for block in blocks:
    m_id = re.search(r'^## ([^\s·]+)', block)
    m_status = re.search(r'^- status:\s*(\w+)', block, re.M)
    m_pr = re.search(r'^- pr_code:\s*(\S+)', block, re.M)
    if m_id and m_status and m_status.group(1) == 'open':
        cid = m_id.group(1)
        pr = m_pr.group(1) if m_pr and m_pr.group(1) != '-' else ''
        print(f'{cid}\t{pr}')
" 2>/dev/null || true)

if [ -z "$OPEN_RECORDS" ]; then
  echo "INFO: 无 status=open 记录, 无需刷新"
  exit 0
fi

OPEN_COUNT=$(printf '%s\n' "$OPEN_RECORDS" | wc -l | tr -d ' ')
echo "=== refresh-status: $OPEN_COUNT 条 open 记录 ==="

UPDATES_TMP=$(mktemp)
trap 'rm -f "$UPDATES_TMP"' EXIT
UPDATED=0; FAILED=0

while IFS=$'\t' read -r CYCLE_ID PR_URL; do
  [ -z "$CYCLE_ID" ] && continue
  [ -z "$PR_URL" ] && { echo "  [$CYCLE_ID] 无 pr_code URL, 跳过"; continue; }
  echo "  [$CYCLE_ID] 查询 $PR_URL ..."
  PR_INFO=$(gh pr view "$PR_URL" --json state,mergedAt 2>/dev/null || echo "")
  if [ -z "$PR_INFO" ]; then
    echo "    WARN: 查询失败, 保留 open" >&2; FAILED=$((FAILED + 1)); continue
  fi
  PARSED=$(printf '%s' "$PR_INFO" | python -c "
import sys, json
d = json.load(sys.stdin)
state = d.get('state', ''); merged_at = d.get('mergedAt') or ''
if merged_at: print(f'merged\t{merged_at[:10]}')
elif state.upper() == 'CLOSED': print('closed\t-')
else: print('open\t-')
" 2>/dev/null || echo "open\t-")
  NEW_STATUS=$(printf '%s' "$PARSED" | cut -f1)
  MERGED_DATE=$(printf '%s' "$PARSED" | cut -f2)
  if [ "$NEW_STATUS" != "open" ]; then
    echo "$CYCLE_ID|$NEW_STATUS|$MERGED_DATE" >> "$UPDATES_TMP"
    echo "    → $NEW_STATUS ($MERGED_DATE)"; UPDATED=$((UPDATED + 1))
  else
    echo "    → 仍 open"
  fi
done <<< "$OPEN_RECORDS"

if [ -s "$UPDATES_TMP" ]; then
  echo ""
  echo "应用 $UPDATED 条更新..."
  TMP_FILE="${CONTRIB_FILE}.tmp"
  cp "$CONTRIB_FILE" "$TMP_FILE"
  python -c "
import re
updates = {}
for line in open('$UPDATES_TMP', encoding='utf-8'):
    parts = line.strip().split('|')
    if len(parts) == 3: updates[parts[0]] = (parts[1], parts[2])
content = open('$TMP_FILE', encoding='utf-8').read()
blocks = re.split(r'(\n## )', content)
out = []
for b in blocks:
    if b == '\n## ' or b.startswith('## '):
        m = re.match(r'## ([^\s·]+)', b.lstrip())
        if m and m.group(1) in updates:
            new_status, merged_date = updates[m.group(1)]
            b = re.sub(r'^- status:\s*\w+', f'- status: {new_status}', b, flags=re.M)
            b = re.sub(r'^- merged:\s*\S+', f'- merged: {merged_date}', b, flags=re.M)
    out.append(b)
open('$TMP_FILE', 'w', encoding='utf-8').write(''.join(out))
" 2>&1 || { echo "ERROR: 更新失败, 保留原文件" >&2; rm -f "$TMP_FILE"; exit 1; }
  mv "$TMP_FILE" "$CONTRIB_FILE"
  echo "OK: CONTRIBUTIONS.md 已更新 $UPDATED 条"
else
  echo "无状态变更"
fi
