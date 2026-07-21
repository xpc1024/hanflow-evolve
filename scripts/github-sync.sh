#!/usr/bin/env bash
# github-sync.sh — RELEASE 阶段: hanflow + evolve + hanflow-site 三仓库同步 (spec §5.4-5.5)
#
# 用法: github-sync.sh <evolve_home>
#
# 三个 Phase:
#   Phase A: hanflow 仓库 — merge feature→main (no-ff) + tag + push
#   Phase B: hanflow-evolve 仓库 — commit cycle 产物 + push (本仓库自身)
#   Phase C: hanflow-site 仓库 — 调用 site-sync.sh 同步版本切换器 + push
#
# Phase A 行为:
#   1. 从 config.yaml 读 hanflow 路径 + merge_strategy
#   2. 从 state.yaml 读 cycle_id + target_version
#   3. FEATURE_BRANCH = "evolve/$CYCLE_ID"
#   4. 前置检查: feature 分支存在; main 工作区干净
#   5. checkout main, merge --no-ff feature
#   6. 打 tag v$TARGET_VERSION
#   7. 遍历所有 remote 逐个 push (main + tag); 允许单个 remote 失败, 全部失败才告警
#
# Phase B 行为 (cycle 2026-W30-1.1.1 起集成进本脚本):
#   - hanflow-evolve 自身 commit (cycle 产物: cycles/, BACKLOG, LEARNINGS, state)
#   - push 到 evolve 的所有 remote
#
# Phase C 行为 (cycle 2026-W30-1.1.1 起集成进本脚本):
#   - 调 scripts/site-sync.sh 同步 hanflow-site (无条件触发, 内部幂等)
#   - 用户偏好: hanflow 版本号变化即同步 (取代原 §5.5 "仅 feat/BREAKING" 规则)
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

# push 到所有 remote (多 remote 容错: 允许单个失败, 全部失败才告警)
# 例如同时推 gitee(origin) + github; 一个挂了另一个成功即视为部分成功
REMOTES=$(git -C "$HANFLOW_PATH" remote 2>/dev/null || true)
if [ -z "$REMOTES" ]; then
  echo "WARN: no git remote configured for $HANFLOW_PATH; skipping push (local-only release)" >&2
else
  PUSH_OK=0
  PUSH_FAIL=0
  while IFS= read -r REMOTE; do
    [ -z "$REMOTE" ] && continue
    echo "[github-sync] pushing main to remote '$REMOTE'"
    if git -C "$HANFLOW_PATH" push "$REMOTE" "$MAIN_BRANCH" 2>&1; then
      PUSH_OK=$((PUSH_OK + 1))
    else
      echo "WARN: push main to '$REMOTE' failed (continuing to next remote)" >&2
      PUSH_FAIL=$((PUSH_FAIL + 1))
      continue  # main 没推上去就不推 tag 到这个 remote, 试下一个
    fi
    if [ -n "$TARGET_VERSION" ]; then
      echo "[github-sync] pushing tag v$TARGET_VERSION to remote '$REMOTE'"
      git -C "$HANFLOW_PATH" push "$REMOTE" "v$TARGET_VERSION" || {
        echo "WARN: push tag v$TARGET_VERSION to '$REMOTE' failed" >&2
      }
    fi
  done <<< "$REMOTES"
  echo "[github-sync] push summary: $PUSH_OK succeeded, $PUSH_FAIL failed"
  if [ "$PUSH_OK" -eq 0 ] && [ "$PUSH_FAIL" -gt 0 ]; then
    echo "WARN: all remotes failed to push; release is local-only (retry github-sync.sh later)" >&2
  fi
fi

echo "OK: Phase A done (hanflow merge=$MERGE_STRATEGY target=$TARGET_VERSION)"

# ============================================================================
# Phase B: hanflow-evolve 仓库自身 commit + push (cycle 2026-W30-1.1.1 起集成)
# ============================================================================
# 注: 调用方 (skill) 通常已在每个 phase commit 过 cycle 产物。Phase B 只做"扫尾
# commit"(把任何漏 commit 的状态变更捕获)+ push。已无 staged 变更时为 no-op。

echo "--- Phase B: evolve repo self-push ---"
EVOLVE_DIRTY=$(git -C "$EVOLVE_HOME" status --porcelain 2>/dev/null || true)
if [ -n "$EVOLVE_DIRTY" ]; then
  echo "[github-sync] Phase B: committing pending evolve changes"
  git -C "$EVOLVE_HOME" add -A
  if ! git -C "$EVOLVE_HOME" diff --cached --quiet; then
    git -C "$EVOLVE_HOME" commit -m "cycle($CYCLE_ID): Phase B evolve repo sync (auto via github-sync.sh)" 2>&1 | tail -2
  fi
else
  echo "[github-sync] Phase B: evolve working tree clean, no commit needed"
fi

EVOLVE_REMOTES=$(git -C "$EVOLVE_HOME" remote 2>/dev/null || true)
if [ -n "$EVOLVE_REMOTES" ]; then
  EVOLVE_BRANCH=$(git -C "$EVOLVE_HOME" branch --show-current 2>/dev/null || echo "main")
  for REMOTE in $EVOLVE_REMOTES; do
    echo "[github-sync] Phase B: pushing evolve to '$REMOTE' ($EVOLVE_BRANCH)"
    git -C "$EVOLVE_HOME" push "$REMOTE" "$EVOLVE_BRANCH" 2>&1 || {
      echo "WARN: Phase B push to $REMOTE failed (continuing to Phase C)" >&2
    }
  done
fi

# ============================================================================
# Phase C: hanflow-site 同步 (cycle 2026-W30-1.1.1 起集成)
# ============================================================================
# 用户偏好 (2026-07-21): hanflow 版本号变化即同步 site, 无条件触发。
# site-sync.sh 内部幂等: 已同步时 exit 0 no-op。

echo "--- Phase C: hanflow-site sync ---"
if [ -f "$EVOLVE_HOME/scripts/site-sync.sh" ]; then
  bash "$EVOLVE_HOME/scripts/site-sync.sh" "$EVOLVE_HOME" || {
    echo "WARN: Phase C site-sync.sh failed (release of hanflow itself is unaffected)" >&2
    echo "      site can be synced manually later: bash scripts/site-sync.sh ." >&2
  }
else
  echo "WARN: scripts/site-sync.sh not found; Phase C skipped" >&2
fi

echo "OK: github-sync complete (Phase A hanflow + Phase B evolve + Phase C site)"
