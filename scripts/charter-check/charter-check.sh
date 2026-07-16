#!/usr/bin/env bash
# charter-check.sh — charter-check 总入口（spec §4.1）
#
# 用法:
#   charter-check.sh [--diff|--full] [--only errors|layering|registry|async|pydantic]
#   charter-check.sh --doc <doc.md>
#
# 模式:
#   --diff   只查 git diff 改动文件（P7 verify 用）
#   --full   查整个 hanflow 代码库（P8 release 用）
#   --doc    扫描设计文档的"架构变更信号"，命中却无 ADR 引用 → WARN（非 FAIL）
#
# 退出: 0=全过/WARN-only; 1=有 FAIL 违规; 2=配置错误。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVOLVE_HOME="${HANFLOW_EVOLVE_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ADR_DIR="$EVOLVE_HOME/docs/adr"

# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"

# 默认参数
MODE="diff"
ONLY=""
DOC=""

# 解析参数
while [ $# -gt 0 ]; do
  case "$1" in
    --diff) MODE="diff"; shift ;;
    --full) MODE="full"; shift ;;
    --doc) MODE="doc"; DOC="${2:?--doc requires a path}"; shift 2 ;;
    --only) ONLY="${2:?--only requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0"
      exit 0
      ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

# ---- --doc 模式：文档变更信号检测（只 WARN）----
if [ "$MODE" = "doc" ]; then
  [ -n "$DOC" ] || { echo "ERROR: --doc requires a path" >&2; exit 2; }
  [ -f "$DOC" ] || { echo "ERROR: doc not found: $DOC" >&2; exit 2; }
  # 架构变更关键词
  if grep -qE '(新增|删除|迁移|替换|重构).*(模块|包|层|依赖)|换.*运行时|替换.*LangGraph|CLI.*(增|删).*命令|SDK.*签名|DSL.*schema' "$DOC"; then
    # 检查是否有 ADR 引用
    if grep -qE 'ADR-[0-9]{4}|docs/adr/' "$DOC"; then
      echo "OK: doc references architecture change(s) WITH ADR linkage"
      exit 0
    else
      echo "WARN: doc mentions architecture change(s) but cites NO ADR — AUDIT Layer-2 (E类) should verify if ADR is required"
      exit 0  # WARN 非 FAIL
    fi
  fi
  echo "OK: doc has no architecture-change signals"
  exit 0
fi

# ---- --diff / --full 模式：跑 5 条代码检查 ----
# 解析 hanflow 路径
HANFLOW_PATH=$(resolve_hanflow_path "$EVOLVE_HOME")
[ -d "$HANFLOW_PATH" ] || { echo "ERROR: hanflow path not found: $HANFLOW_PATH" >&2; exit 2; }

ALL_CHECKS="errors registry pydantic-data async-api layering"
[ -n "$ONLY" ] && ALL_CHECKS="$ONLY"

echo "=== charter-check (mode=$MODE, hanflow=$HANFLOW_PATH) ==="
overall=0
for check in $ALL_CHECKS; do
  script="$SCRIPT_DIR/${check}.sh"
  [ -f "$script" ] || { echo "ERROR: check script not found: $script" >&2; exit 2; }
  echo "--- $check ---"
  if ! bash "$script" "$HANFLOW_PATH" "$MODE" "$ADR_DIR"; then
    overall=1
  fi
done

echo "=== charter-check: exit $overall ==="
exit "$overall"
