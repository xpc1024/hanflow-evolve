#!/usr/bin/env bash
# github-sync.sh — RELEASE 阶段 Phase A: hanflow 仓库 merge + tag + push (spec §5.4)
#
# 用法: github-sync.sh <evolve_home>
#
# 行为:
#   1. 从 config.yaml 读 hanflow 路径 + merge_strategy
#   2. 从 state.yaml 读 cycle_id + target_version
#   3. FEATURE_BRANCH = "evolve/$CYCLE_ID"
#   4. 前置检查: feature 分支存在; main 工作区干净
#   5. checkout main, merge --no-ff feature
#   6. 打 tag v$TARGET_VERSION
#   7. 若配置了 remote 则 push (main + tag); 无 remote 仅告警, 不失败
#
# Phase B (evolve 仓库 cycle 产物 commit) 由调用方 (skill) 在外部触发;
# 本脚本专注 hanflow 仓库。
#
# Windows/MSYS 兼容: 路径经环境变量传给 python, 不插值进 python -c 字符串。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: github-sync.sh <evolve_home>}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state.yaml"
for f in "$CONFIG" "$STATE"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing $f" >&2
    exit 1
  fi
done

# 一次性把 config + state 关键字段读出来 (走环境变量, 不插值)
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
paths = c.get('paths') or {}
release = c.get('release') or {}
print(paths.get('hanflow') or '')
print(release.get('merge_strategy') or 'no-ff')
print(s.get('cycle_id') or '')
print(s.get('target_version') or '')
")
HANFLOW_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
MERGE_STRATEGY=$(printf '%s' "$READ_OUT" | sed -n '2p')
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '3p')
TARGET_VERSION=$(printf '%s' "$READ_OUT" | sed -n '4p')

if [ -z "$HANFLOW_PATH" ]; then
  echo "ERROR: config.yaml paths.hanflow is empty" >&2
  exit 1
fi
if [ -z "$CYCLE_ID" ]; then
  echo "ERROR: state.yaml cycle_id is empty" >&2
  exit 1
fi

FEATURE_BRANCH="evolve/$CYCLE_ID"
MAIN_BRANCH="main"

echo "[github-sync] hanflow=$HANFLOW_PATH feature=$FEATURE_BRANCH target=$TARGET_VERSION strategy=$MERGE_STRATEGY"

# 校验 feature 分支存在
if ! git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/$FEATURE_BRANCH" >/dev/null; then
  echo "ERROR: feature branch '$FEATURE_BRANCH' does not exist in $HANFLOW_PATH" >&2
  echo "       先在 code/verify 阶段创建并提交该分支, 再运行 release。" >&2
  exit 1
fi

# 校验 main 分支存在
if ! git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/$MAIN_BRANCH" >/dev/null; then
  echo "ERROR: main branch does not exist in $HANFLOW_PATH" >&2
  exit 1
fi

# 校验 main 工作区干净 (忽略 CRLF 换行告警噪音: 用 --porcelain 不读 stderr)
PORCELAIN=$(git -C "$HANFLOW_PATH" status --porcelain 2>/dev/null || true)
if [ -n "$PORCELAIN" ]; then
  echo "ERROR: main branch has uncommitted changes in $HANFLOW_PATH; 请先提交或 stash:" >&2
  echo "$PORCELAIN" >&2
  exit 1
fi

# 切到 main
git -C "$HANFLOW_PATH" checkout -q "$MAIN_BRANCH"

# 合并 (默认 no-ff)
case "$MERGE_STRATEGY" in
  no-ff|no_ff)
    git -C "$HANFLOW_PATH" merge --no-ff -m "Merge $FEATURE_BRANCH into $MAIN_BRANCH (release $TARGET_VERSION)" "$FEATURE_BRANCH"
    ;;
  ff-only|ff_only)
    git -C "$HANFLOW_PATH" merge --ff-only "$FEATURE_BRANCH"
    ;;
  *)
    echo "WARN: unknown merge_strategy '$MERGE_STRATEGY', falling back to --no-ff" >&2
    git -C "$HANFLOW_PATH" merge --no-ff -m "Merge $FEATURE_BRANCH into $MAIN_BRANCH (release $TARGET_VERSION)" "$FEATURE_BRANCH"
    ;;
esac

# 打 tag
if [ -n "$TARGET_VERSION" ]; then
  TAG="v$TARGET_VERSION"
  if git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "WARN: tag $TAG already exists, skipping tag creation" >&2
  else
    git -C "$HANFLOW_PATH" tag -a "$TAG" -m "Release $TARGET_VERSION"
    echo "[github-sync] tagged $TAG"
  fi
fi

# push (有 remote 才推, 无 remote 仅告警)
REMOTE=$(git -C "$HANFLOW_PATH" remote 2>/dev/null | head -1 || true)
if [ -n "$REMOTE" ]; then
  echo "[github-sync] pushing to remote '$REMOTE'"
  git -C "$HANFLOW_PATH" push "$REMOTE" "$MAIN_BRANCH" || {
    echo "WARN: push main failed (continuing; tag below)" >&2
  }
  if [ -n "$TARGET_VERSION" ]; then
    git -C "$HANFLOW_PATH" push "$REMOTE" "v$TARGET_VERSION" || {
      echo "WARN: push tag v$TARGET_VERSION failed" >&2
    }
  fi
else
  echo "WARN: no git remote configured for $HANFLOW_PATH; skipping push (local-only release)" >&2
fi

echo "OK: github-sync done (merge=$MERGE_STRATEGY target=$TARGET_VERSION)"
