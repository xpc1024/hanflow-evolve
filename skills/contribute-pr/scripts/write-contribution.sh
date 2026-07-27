#!/usr/bin/env bash
# write-contribution.sh — SUBMIT 阶段 S4: 原子追加 CONTRIBUTIONS.md 一条记录 (spec §5.3)
#
# 用法: write-contribution.sh <evolve_home>
#
# 行为:
#   1. 从 state-contribute.yaml 读 cycle_id/target_theme/submit.*/target_theme 等
#   2. 从 hanflow 仓库的 feature 分支提取 affected_modules (git diff 的文件列表)
#   3. 取贡献者 GitHub 用户名 (gh api user)
#   4. 追加一条记录到 hanflow-evolve/CONTRIBUTIONS.md (flock 防并发, 不删已有记录)
#
# 记录格式见 spec §5.3。
#
# 幂等: 若 CONTRIBUTIONS.md 已有同 cycle_id 的记录, 不重复追加 (warn)
#
# 返回: 0=成功, 非 0=失败 (PR 已发, 仅档案没写, 下次 refresh-status 从 GitHub 反向补全)
set -euo pipefail

EVOLVE_HOME="${1:?Usage: write-contribution.sh <evolve_home>}"
if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state-contribute.yaml"
for f in "$CONFIG" "$STATE"; do
  [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

CONTRIB_FILE="$EVOLVE_HOME/CONTRIBUTIONS.md"

# 读 state 关键字段
READ_OUT=$(STATE_FILE="$STATE" CONFIG_FILE="$CONFIG" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
print(s.get('cycle_id') or '')
print(s.get('target_theme') or '')
submit = s.get('submit') or {}
print(submit.get('pr_code_url') or '-')
print(submit.get('pr_docs_url') or '-')
print(submit.get('quality') or 'null')
print((c.get('paths') or {}).get('hanflow') or '')
")
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '1p')
TARGET_THEME=$(printf '%s' "$READ_OUT" | sed -n '2p')
PR_CODE=$(printf '%s' "$READ_OUT" | sed -n '3p')
PR_DOCS=$(printf '%s' "$READ_OUT" | sed -n '4p')
QUALITY=$(printf '%s' "$READ_OUT" | sed -n '5p')
HANFLOW_PATH=$(printf '%s' "$READ_OUT" | sed -n '6p')

[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id empty" >&2; exit 1; }

# 幂等: 检查是否已有同 cycle_id 记录
if [ -f "$CONTRIB_FILE" ] && grep -q "^## $CYCLE_ID ·" "$CONTRIB_FILE" 2>/dev/null; then
  echo "WARN: CONTRIBUTIONS.md 已有 $CYCLE_ID 记录, 不重复追加 (幂等)" >&2
  exit 0
fi

# 取贡献者用户名 (gh api user)
USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
if [ "$USERNAME" = "unknown" ]; then
  echo "WARN: 无法获取 GitHub 用户名 (gh 未登录?), 记为 unknown" >&2
fi

# 取 affected_modules (feature 分支相对 main 的文件列表)
BRANCH="evolve/$CYCLE_ID"
AFFECTED="-"
if [ -n "$HANFLOW_PATH" ] && [ -d "$HANFLOW_PATH" ] && \
   git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null && \
   git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/main" >/dev/null; then
  FILES=$(git -C "$HANFLOW_PATH" diff --name-only main.."$BRANCH" 2>/dev/null | head -10 | tr '\n' ',' | sed 's/,$//')
  [ -n "$FILES" ] && AFFECTED="$FILES"
fi

# 取 type + summary (最新提交消息: feat: xxx → type=feat, summary=xxx)
LATEST_MSG=$(git -C "$HANFLOW_PATH" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "")
TYPE=$(printf '%s' "$LATEST_MSG" | sed -nE 's/^([a-z]+)(\(.+\))?!?:.*/\1/p')
[ -z "$TYPE" ] && TYPE="feat"
SUMMARY=$(printf '%s' "$LATEST_MSG" | sed -nE 's/^[a-z]+(\(.+\))?!: *//p')
[ -z "$SUMMARY" ] && SUMMARY="$TARGET_THEME"

TODAY=$(date +%Y-%m-%d)

# 构造记录块
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

# 原子追加 (flock 防并发, 临时文件 + mv)
LOCK_FILE="$EVOLVE_HOME/.contributions.lock"
(
  flock -x 200

  # 若文件不存在, 写头
  if [ ! -f "$CONTRIB_FILE" ]; then
    cat > "$CONTRIB_FILE" <<'HEADER'
# CONTRIBUTIONS.md — 社区贡献档案

> 由 contribute-pr skill 自动追加。每条记录一次贡献的全生命周期。
> 用途:(1) 离线去重(gh 不可用时兜底)  (2) 本贡献者自己的历史(本机可见)
>
> 诚实定位:CONTRIBUTIONS.md 是单机本地档案,不是分布式同步的数据库。
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
