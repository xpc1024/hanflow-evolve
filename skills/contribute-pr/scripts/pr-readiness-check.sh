#!/usr/bin/env bash
# pr-readiness-check.sh — SUBMIT 阶段 S0: 提交前质量门 (spec §3.1)
#
# 用法: pr-readiness-check.sh <evolve_home>
#
# 定位: verify(P12) 已覆盖测试+smoke+auto-fix; S0 不重复测试,
#       只补 verify 不覆盖的"提交就绪性"检查。
#
# 检查项:
#   1. charter-check 全量复核 (verify 用 --diff 增量, S0 用全量做双保险)
#   2. lint (ruff check + ruff format --check) — verify 已跑, S0 复核
#   3. 提交历史合规 (conventional commits, 无 WIP/草稿提交)
#   4. 文档同步检查 — P2 才补 (依赖 S3 文档 PR; P1 补会产生"该发文档PR但P1发不了"的尴尬)
#
# 返回:
#   0 = 全部通过, 可进入 S1
#   非 0 = 有失败, 回 code 阶段修复
#
# 输出: 每项 PASS/FAIL, 最后汇总。FAIL 时输出具体原因。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: pr-readiness-check.sh <evolve_home>}"
if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state-contribute.yaml"
for f in "$CONFIG" "$STATE"; do
  [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# 读 hanflow 路径 + cycle_id
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((c.get('paths') or {}).get('hanflow') or '')
print(s.get('cycle_id') or '')
")
HANFLOW_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '2p')

[ -z "$HANFLOW_PATH" ] && { echo "ERROR: config.yaml paths.hanflow is empty" >&2; exit 1; }
[ -z "$CYCLE_ID" ] && { echo "ERROR: state-contribute.yaml cycle_id is empty" >&2; exit 1; }
[ -d "$HANFLOW_PATH" ] || { echo "ERROR: hanflow path not found: $HANFLOW_PATH" >&2; exit 1; }

BRANCH="evolve/$CYCLE_ID"
FAIL_COUNT=0

echo "=== S0 就绪检查: hanflow=$HANFLOW_PATH branch=$BRANCH ==="

# 切到 feature 分支 (确保检查的是贡献分支而非 main)
if ! git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "FAIL: feature branch '$BRANCH' does not exist in $HANFLOW_PATH" >&2
  echo "      先在 code 阶段创建并提交该分支" >&2
  exit 1
fi
git -C "$HANFLOW_PATH" checkout -q "$BRANCH"

# ── 检查 1: charter-check 全量复核 ──
echo "--- [1/3] charter-check 全量复核 ---"
CHARTER_CHECK="$EVOLVE_HOME/scripts/charter-check/charter-check.sh"
if [ ! -f "$CHARTER_CHECK" ]; then
  echo "WARN: charter-check.sh not found at $CHARTER_CHECK, 跳过 (P0 容错)" >&2
  echo "PASS [1/3] charter-check (skipped, script missing)"
else
  if bash "$CHARTER_CHECK.sh" "$EVOLVE_HOME" 2>&1; then
    echo "PASS [1/3] charter-check 全量通过"
  else
    echo "FAIL [1/3] charter-check 有违反不变量 (见上方输出)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

# ── 检查 2: lint (ruff check + ruff format --check) ──
echo "--- [2/3] lint (ruff check + format --check) ---"
LINT_OK=1
( cd "$HANFLOW_PATH" && uv run ruff check . ) || LINT_OK=0
( cd "$HANFLOW_PATH" && uv run ruff format --check . ) || LINT_OK=0
if [ "$LINT_OK" -eq 1 ]; then
  echo "PASS [2/3] lint 零告警"
else
  echo "FAIL [2/3] lint 有告警, 请修复后再提交" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 检查 3: 提交历史合规 (conventional commits) ──
echo "--- [3/3] 提交历史合规 (conventional commits) ---"
# 取 feature 分支相对 main 的提交
MAIN_BRANCH="main"
if ! git -C "$HANFLOW_PATH" rev-parse --verify --quiet "refs/heads/$MAIN_BRANCH" >/dev/null; then
  echo "WARN: main branch not found, 跳过提交历史检查" >&2
  echo "PASS [3/3] commit-history (skipped, no main)"
else
  COMMITS=$(git -C "$HANFLOW_PATH" log --format='%s' "$MAIN_BRANCH..$BRANCH" 2>/dev/null || true)
  if [ -z "$COMMITS" ]; then
    echo "FAIL [3/3] feature 分支相对 main 无提交, 无法发 PR" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    # conventional commit 正则: ^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+
    BAD_COMMITS=$(printf '%s\n' "$COMMITS" | grep -vE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+' || true)
    # 检查 WIP/草稿标记
    WIP_COMMITS=$(printf '%s\n' "$COMMITS" | grep -iE 'WIP|TODO|草稿|draft|fixme' || true)
    if [ -n "$BAD_COMMITS" ]; then
      echo "FAIL [3/3] 以下提交不符合 conventional commits 格式:" >&2
      printf '%s\n' "$BAD_COMMITS" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ -n "$WIP_COMMITS" ]; then
      echo "FAIL [3/3] 发现 WIP/草稿提交, 请 rebase 整理后再发 PR:" >&2
      printf '%s\n' "$WIP_COMMITS" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      echo "PASS [3/3] 提交历史合规"
    fi
  fi
fi

# ── 汇总 ──
echo ""
echo "=== S0 汇总: $((3 - FAIL_COUNT))/3 通过 ==="
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL: S0 有 $FAIL_COUNT 项未通过, 回 code 阶段修复后再 submit" >&2
  exit 1
fi
echo "OK: S0 全部通过, 可进入 S1 (凭证与 fork 准备)"
