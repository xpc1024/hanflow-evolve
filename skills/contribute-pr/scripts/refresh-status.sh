#!/usr/bin/env bash
# refresh-status.sh — 刷新 CONTRIBUTIONS.md 中 open 记录的状态 (spec §5.4)
#
# 用法: refresh-status.sh <evolve_home>
#
# 三层触发 (由调用方/SKILL.md 决定何时调本脚本):
#   1. submit 成功后立即刷新 (S4 归档时, 校验刚发 PR 的 URL 可达)
#   2. 每次 contribute-pr 启动时 (acquire-lock 后, scan 前)
#   3. 手动 /contribute-pr refresh
#
# 行为:
#   遍历 CONTRIBUTIONS.md 中 status: open 的记录, 对每条:
#   - gh pr view <pr_code_url> --json state,mergedAt
#   - merged → status: merged, merged: <date>
#   - closed → status: closed (未合并)
#   - 网络失败 → 保留 open + WARN, 不阻断
#
# 写入用就地替换 (非追加), 原子模式 (cp → 临时 → 校验 → mv)
#
# 返回: 0=刷新完成(部分失败也返回0, 仅 WARN), 非0=脚本本身错误
set -euo pipefail

EVOLVE_HOME="${1:?Usage: refresh-status.sh <evolve_home>}"
if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONTRIB_FILE="$EVOLVE_HOME/CONTRIBUTIONS.md"

if [ ! -f "$CONTRIB_FILE" ]; then
  echo "INFO: CONTRIBUTIONS.md 不存在, 无记录可刷新" >&2
  exit 0
fi

# gh 可用性
if ! gh auth status >/dev/null 2>&1; then
  echo "WARN: gh 未认证, 无法刷新状态 (跳过 refresh-status)" >&2
  echo "      建议先 gh auth login, 再 /contribute-pr refresh" >&2
  exit 0
fi

# 提取所有 status: open 的记录 (cycle_id + pr_code_url)
# 用 python 解析 markdown 记录块 (比 awk/grep 可靠)
OPEN_RECORDS=$(python -c "
import re
content = open('$CONTRIB_FILE', encoding='utf-8').read()
# 按 '## ' 分块
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
  echo "INFO: CONTRIBUTIONS.md 无 status=open 记录, 无需刷新"
  exit 0
fi

OPEN_COUNT=$(printf '%s\n' "$OPEN_RECORDS" | wc -l | tr -d ' ')
echo "=== refresh-status: $OPEN_COUNT 条 open 记录 ==="

# 收集每条记录的新状态
UPDATES_TMP=$(mktemp)
trap 'rm -f "$UPDATES_TMP"' EXIT

UPDATED=0
FAILED=0

while IFS=$'\t' read -r CYCLE_ID PR_URL; do
  [ -z "$CYCLE_ID" ] && continue
  [ -z "$PR_URL" ] && { echo "  [$CYCLE_ID] 无 pr_code URL, 跳过"; continue; }

  echo "  [$CYCLE_ID] 查询 $PR_URL ..."
  # gh pr view 取 state + mergedAt
  PR_INFO=$(gh pr view "$PR_URL" --json state,mergedAt 2>/dev/null || echo "")
  if [ -z "$PR_INFO" ]; then
    echo "    WARN: 查询失败 (网络/权限), 保留 open" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  # 解析 state + mergedAt
  PARSED=$(printf '%s' "$PR_INFO" | python -c "
import sys, json
d = json.load(sys.stdin)
state = d.get('state', '')
merged_at = d.get('mergedAt') or ''
# mergedAt 非空 = 已合并, 取日期部分
if merged_at:
    print(f'merged\t{merged_at[:10]}')
elif state.upper() == 'CLOSED':
    print('closed\t-')
else:
    print('open\t-')
" 2>/dev/null || echo "open\t-")

  NEW_STATUS=$(printf '%s' "$PARSED" | cut -f1)
  MERGED_DATE=$(printf '%s' "$PARSED" | cut -f2)

  if [ "$NEW_STATUS" != "open" ]; then
    echo "$CYCLE_ID|$NEW_STATUS|$MERGED_DATE" >> "$UPDATES_TMP"
    echo "    → $NEW_STATUS ($MERGED_DATE)"
    UPDATED=$((UPDATED + 1))
  else
    echo "    → 仍 open"
  fi
done <<< "$OPEN_RECORDS"

# ── 原子应用更新 (就地替换 status/merged 行) ──
if [ -s "$UPDATES_TMP" ]; then
  echo ""
  echo "应用 $UPDATED 条更新到 CONTRIBUTIONS.md ..."
  TMP_FILE="${CONTRIB_FILE}.tmp"
  cp "$CONTRIB_FILE" "$TMP_FILE"

  # 用 python 就地替换每条记录的 status/merged 行
  UPDATES_FILE="$UPDATES_TMP"
  python -c "
import re, sys
updates = {}
for line in open('$UPDATES_FILE', encoding='utf-8'):
    parts = line.strip().split('|')
    if len(parts) == 3:
        updates[parts[0]] = (parts[1], parts[2])

content = open('$TMP_FILE', encoding='utf-8').read()
blocks = re.split(r'(\n## )', content)
out = []
for i, b in enumerate(blocks):
    if b == '\n## ' or b.startswith('## '):
        # 取 cycle_id
        m = re.match(r'## ([^\s·]+)', b.lstrip())
        if m and m.group(1) in updates:
            new_status, merged_date = updates[m.group(1)]
            # 替换 status 行
            b = re.sub(r'^- status:\s*\w+', f'- status: {new_status}', b, flags=re.M)
            # 替换 merged 行
            b = re.sub(r'^- merged:\s*\S+', f'- merged: {merged_date}', b, flags=re.M)
    out.append(b)
open('$TMP_FILE', 'w', encoding='utf-8').write(''.join(out))
" 2>&1 || { echo "ERROR: 更新应用失败, 保留原文件" >&2; rm -f "$TMP_FILE"; exit 1; }

  mv "$TMP_FILE" "$CONTRIB_FILE"
  echo "OK: CONTRIBUTIONS.md 已更新 $UPDATED 条记录"
else
  echo "无状态变更 (所有 open 记录仍 open)"
fi

echo ""
echo "=== refresh-status 汇总 ==="
echo "  更新: $UPDATED"
echo "  仍 open: $((OPEN_COUNT - UPDATED - FAILED))"
echo "  查询失败: $FAILED"
