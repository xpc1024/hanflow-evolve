#!/usr/bin/env bash
# pr-readiness-check-docs.sh — 文档贡献的 S0 (docs 子命令专用, spec §6.4)
#
# 用法: pr-readiness-check-docs.sh <hanflow_home_repo>
#
# 定位: 纯文档贡献 (修错别字/补示例) 不需要代码质量门 (charter/lint/mypy)。
#       本脚本只做文档构建校验 + 提交规范, 比代码 S0 轻量。
#
# 检查项:
#   1. npm run build (Next.js 构建, 确保改动的 MDX/导航不破站点)
#   2. 提交历史合规 (conventional commits)
#
# ⚠️ MDX 链接规范提醒 (LEARNINGS 有效实践):
#   MDX 正文里的文档间链接请写 /docs/xxx (不带 locale 前缀),
#   渲染层 (MDXRenderer) 会自动加当前 locale 前缀 (/zh/docs/xxx 或 /en/docs/xxx)。
#   不要手写 /zh/docs/ 或 /en/docs/ — 会写死语言, 切换 locale 时跨语言跳转。
#   外链 (https://...) 不受影响, 照常写。
set -euo pipefail

HANFLOW_HOME_REPO="${1:?Usage: pr-readiness-check-docs.sh <hanflow_home_repo>}"
[ -d "$HANFLOW_HOME_REPO" ] || { echo "ERROR: hanflow_home_repo not found: $HANFLOW_HOME_REPO" >&2; exit 1; }

STATE="$HANFLOW_HOME_REPO/.contribute/state.yaml"
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

CYCLE_ID=$(STATE_FILE="$STATE" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print(s.get('cycle_id') or '')
" 2>/dev/null || echo "")
[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id is empty" >&2; exit 1; }

BRANCH="evolve/$CYCLE_ID"
FAIL_COUNT=0

echo "=== S0 (docs) 就绪检查: hanflow-home=$HANFLOW_HOME_REPO branch=$BRANCH ==="

# 切到 feature 分支
if ! git -C "$HANFLOW_HOME_REPO" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  echo "FAIL: feature branch '$BRANCH' does not exist in $HANFLOW_HOME_REPO" >&2
  echo "      先创建该分支并提交文档改动" >&2
  exit 1
fi
git -C "$HANFLOW_HOME_REPO" checkout -q "$BRANCH"

# ── 检查 1: npm run build (Next.js 构建) ──
echo "--- [1/2] npm run build (Next.js 文档构建) ---"
if [ ! -f "$HANFLOW_HOME_REPO/package.json" ]; then
  echo "WARN: package.json 不存在, 跳过 build 校验 (非 Next.js 仓库?)" >&2
  echo "PASS [1/2] build (skipped, no package.json)"
else
  if ( cd "$HANFLOW_HOME_REPO" && npm run build ) 2>&1 | tail -20; then
    echo "PASS [1/2] npm run build 通过"
  else
    echo "FAIL [1/2] npm run build 失败 (文档/导航改动破坏构建, 见上方输出)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

# ── 检查 2: 提交历史合规 ──
echo "--- [2/2] 提交历史合规 (conventional commits) ---"
BASE_BRANCH=""
for cand in upstream/main origin/main main; do
  if git -C "$HANFLOW_HOME_REPO" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>/dev/null || \
     git -C "$HANFLOW_HOME_REPO" rev-parse --verify --quiet "refs/remotes/$cand" >/dev/null 2>/dev/null; then
    BASE_BRANCH="$cand"; break
  fi
done

if [ -z "$BASE_BRANCH" ]; then
  echo "WARN: 未找到 base 分支, 跳过提交历史检查" >&2
  echo "PASS [2/2] commit-history (skipped, no base)"
else
  COMMITS=$(git -C "$HANFLOW_HOME_REPO" log --format='%s' "$BASE_BRANCH..$BRANCH" 2>/dev/null || true)
  if [ -z "$COMMITS" ]; then
    echo "FAIL [2/2] feature 分支相对 $BASE_BRANCH 无提交" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    BAD_COMMITS=$(printf '%s\n' "$COMMITS" | grep -vE '^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+' || true)
    if [ -n "$BAD_COMMITS" ]; then
      echo "FAIL [2/2] 以下提交不符合 conventional commits:" >&2
      printf '%s\n' "$BAD_COMMITS" >&2
      FAIL_COUNT=$((FAIL_COUNT + 1))
    else
      echo "PASS [2/2] 提交历史合规 (base=$BASE_BRANCH)"
    fi
  fi
fi

# ── 汇总 ──
echo ""
echo "=== S0 (docs) 汇总: $((2 - FAIL_COUNT))/2 通过 ==="
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "FAIL: S0 有 $FAIL_COUNT 项未通过, 修复后再 submit" >&2
  exit 1
fi
echo "OK: S0 (docs) 全部通过, 可进入 submit"
