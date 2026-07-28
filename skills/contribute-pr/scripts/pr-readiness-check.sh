#!/usr/bin/env bash
# pr-readiness-check.sh — SUBMIT 阶段 S0: 提交前质量门 (spec §3.1)
#
# 用法: pr-readiness-check.sh <hanflow_repo>
#
# 架构 (P2 修正): 以贡献者 clone 的 hanflow 仓库为工作目录,
# state 在 <hanflow_repo>/.contribute/state.yaml,
# charter-check 从 skill 自带目录调 (install.sh 已打包)。
#
# 定位: verify(P12) 已覆盖测试+smoke+auto-fix; S0 不重复测试,
#       只补 verify 不覆盖的"提交就绪性"检查。
#
# 检查项:
#   1. charter-check 子检查复核 (直接调 errors/async-api/pydantic-data/registry/layering)
#   2. lint (ruff check + ruff format --check)
#   3. 提交历史合规 (conventional commits, 无 WIP/草稿提交)
#   4. 文档同步检查 — P2 才补 (依赖 S3 文档 PR)
set -euo pipefail

HANFLOW_REPO="${1:?Usage: pr-readiness-check.sh <hanflow_repo>}"
[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }

STATE="$HANFLOW_REPO/.contribute/state.yaml"
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

# skill 自带 charter-check 目录 (install.sh 打包到 scripts/charter-check/)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHARTER_CHECK_DIR="$SCRIPT_DIR/charter-check"

# 读 cycle_id (state 字段名与 loop-evolve 同构; 走环境变量避免 MSYS 路径插值)
CYCLE_ID=$(STATE_FILE="$STATE" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print(s.get('cycle_id') or '')
" 2>/dev/null || echo "")
[ -z "$CYCLE_ID" ] && { echo "ERROR: state.yaml cycle_id is empty" >&2; exit 1; }

BRANCH="evolve/$CYCLE_ID"
FAIL_COUNT=0

echo "=== S0 就绪检查: hanflow=$HANFLOW_REPO branch=$BRANCH ==="

# 切到 feature 分支
if ! git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "FAIL: feature branch '$BRANCH' does not exist in $HANFLOW_REPO" >&2
  echo "      先在 code 阶段创建并提交该分支" >&2
  exit 1
fi
git -C "$HANFLOW_REPO" checkout -q "$BRANCH"

# ── 检查 1: charter-check 子检查复核 (直接调, 绕过依赖 config 的入口) ──
echo "--- [1/3] charter-check 复核 ---"
# ADR_DIR: 从 skill 安装的 charter-check 同级找不到 docs/adr, 用空目录降级
# (ADR 白名单主要给维护者用; 贡献者场景无 ADR, 违规即真违规)
ADR_DIR="$HANFLOW_REPO/.contribute/adr"
mkdir -p "$ADR_DIR"  # 空目录, in_whitelist 会返回 false (无白名单)

if [ ! -d "$CHARTER_CHECK_DIR" ]; then
  echo "WARN: charter-check 未打包到 $CHARTER_CHECK_DIR, 跳过 (重跑 install.sh 修复)" >&2
  echo "PASS [1/3] charter-check (skipped, not installed)"
else
  # 注意: charter-check 各子检查在 --full 模式 (扫全仓 ~110 文件) 下会挂起
  # (in_whitelist 循环 + glob 组合)。S0 用 --diff (只扫改动文件), 正常几秒完成。
  # 但贡献者改动巨大时 --diff 也可能变慢, 加 timeout 120 防止极端情况卡死。
  CHARTER_OK=1
  for check in errors registry pydantic-data async-api layering; do
    check_script="$CHARTER_CHECK_DIR/${check}.sh"
    if [ ! -f "$check_script" ]; then
      echo "  WARN: $check.sh 不存在, 跳过" >&2
      continue
    fi
    # timeout 124=超时 (视为该项失败但不阻塞整体, 避免 skill 挂死)
    if timeout 120 bash "$check_script" "$HANFLOW_REPO" "diff" "$ADR_DIR" 2>&1 | sed 's/^/    /'; then
      : # 该项通过
    else
      rc=$?
      if [ "$rc" -eq 124 ]; then
        echo "    WARN: $check 超时 (>120s), 视为该项失败 (改动可能过大, 考虑拆分 PR)" >&2
      fi
      CHARTER_OK=0
    fi
  done
  if [ "$CHARTER_OK" -eq 1 ]; then
    echo "PASS [1/3] charter-check 全部通过"
  else
    echo "FAIL [1/3] charter-check 有违规或超时 (见上方输出)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

# ── 检查 2: lint (ruff check + ruff format --check) ──
echo "--- [2/3] lint (ruff check + format --check) ---"
LINT_OK=1
( cd "$HANFLOW_REPO" && uv run ruff check . ) || LINT_OK=0
( cd "$HANFLOW_REPO" && uv run ruff format --check . ) || LINT_OK=0
if [ "$LINT_OK" -eq 1 ]; then
  echo "PASS [2/3] lint 零告警"
else
  echo "FAIL [2/3] lint 有告警, 请修复后再提交" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ── 检查 3: 提交历史合规 ──
echo "--- [3/3] 提交历史合规 (conventional commits) ---"
MAIN_BRANCH="main"
# 找 base 分支 (上游 main 或 fork 的 main)
BASE_BRANCH=""
for cand in upstream/main origin/main main; do
  if git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>/dev/null || \
     git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/remotes/$cand" >/dev/null 2>/dev/null; then
    BASE_BRANCH="$cand"
    break
  fi
done

if [ -z "$BASE_BRANCH" ]; then
  echo "WARN: 未找到 base 分支 (main), 跳过提交历史检查" >&2
  echo "PASS [3/3] commit-history (skipped, no base)"
else
  # 规范化分支名 (refs/remotes/origin/main → 用 git log 直接比较)
  COMMITS=$(git -C "$HANFLOW_REPO" log --format='%s' "$BASE_BRANCH..$BRANCH" 2>/dev/null || true)
  if [ -z "$COMMITS" ]; then
    echo "FAIL [3/3] feature 分支相对 $BASE_BRANCH 无提交, 无法发 PR" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    BAD_COMMITS=$(printf '%s\n' "$COMMITS" | grep -vE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+' || true)
    WIP_COMMITS=$(printf '%s\n' "$COMMITS" | grep -iE 'WIP|TODO|草稿|draft|fixme' || true)
    if [ -n "$BAD_COMMITS" ]; then
      echo "FAIL [3/3] 以下提交不符合 conventional commits:" >&2
      printf '%s\n' "$BAD_COMMITS" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    elif [ -n "$WIP_COMMITS" ]; then
      echo "FAIL [3/3] 发现 WIP/草稿提交, 请 rebase 整理:" >&2
      printf '%s\n' "$WIP_COMMITS" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      echo "PASS [3/3] 提交历史合规 (base=$BASE_BRANCH)"
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
