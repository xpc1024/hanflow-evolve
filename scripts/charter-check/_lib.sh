#!/usr/bin/env bash
# _lib.sh — charter-check 共享辅助库
#
# 提供：
#   - resolve_hanflow_path：从 config.yaml 读 paths.hanflow，解析 MSYS→Win
#   - list_py_files：按 --diff/--full 模式列出待查 .py 文件
#   - report_ok / report_fail：统一报告格式
#   - in_whitelist：检查违规是否被 ADR 白名单精确覆盖
#
# 设计：被各子检查 `source`，不直接执行。

set -euo pipefail

# resolve_hanflow_path <evolve_home>
# 输出 hanflow 代码库的 Windows 风格路径到 stdout；失败 exit 1。
resolve_hanflow_path() {
  local evolve_home="${1:?Usage: resolve_hanflow_path <evolve_home>}"
  local config="$evolve_home/config.yaml"
  [ -f "$config" ] || { echo "ERROR: config.yaml not found: $config" >&2; exit 2; }

  # 从 config 读 paths.hanflow（复用 smoke-test.sh 的 python 解析模式）
  local msys_path
  msys_path=$(CONFIG_FILE="$config" python -c "import os,yaml; c=yaml.safe_load(open(os.environ['CONFIG_FILE'],encoding='utf-8')); print((c.get('paths') or {}).get('hanflow') or '')")
  [ -n "$msys_path" ] || { echo "ERROR: config.yaml paths.hanflow is empty" >&2; exit 2; }

  # MSYS→Windows 路径解析（native Windows python/grep 兼容）
  local win_path
  win_path=$(HANFLOW_MSYS="$msys_path" python -c "
import os, subprocess, sys
p = os.environ['HANFLOW_MSYS']
if os.path.isdir(p):
    print(p); sys.exit(0)
if os.name == 'nt':
    try:
        r = subprocess.run(['cygpath','-w',p], capture_output=True, text=True, check=True)
        print(r.stdout.strip()); sys.exit(0)
    except Exception:
        pass
print(p)
")
  echo "$win_path"
}

# list_py_files <hanflow_path> <mode: diff|full>
# --diff：列 git diff 改动的 .py（相对 hanflow 仓库）；--full：列全部 .py
# 输出绝对路径，每行一个。
list_py_files() {
  local hanflow_path="$1" mode="$2"
  case "$mode" in
    full)
      find "$hanflow_path/hanflow" -name '*.py' -not -path '*/__pycache__/*' 2>/dev/null || true
      ;;
    diff)
      # git diff 改动的 .py（已暂存 + 未暂存 + 新增），相对 hanflow 仓库根
      git -C "$hanflow_path" diff --name-only --relative HEAD 2>/dev/null | grep -E '^hanflow/.*\.py$' | sed "s|^|$hanflow_path/|" || true
      ;;
    *)
      echo "ERROR: unknown mode '$mode' (expected diff|full)" >&2; exit 2
      ;;
  esac
}

# report_ok <check_name> <count>
report_ok() {
  echo "OK: $1 passed (scanned $2 files)"
}

# report_fail <check_name> <count>
# 后续逐条违规由调用方直接 echo 到 stdout。
report_fail() {
  echo "FAIL: $1 found $2 violation(s):"
}

# in_whitelist <check> <violation_path> <adr_dir>
# 检查是否有 allow-<check>-* 的 accepted ADR 精确覆盖该违规路径。
# 返回 0=放行（命中白名单），1=未覆盖。
in_whitelist() {
  local check="$1" violation_path="$2" adr_dir="$3"
  [ -d "$adr_dir" ] || return 1
  # 找 allow-<check>-*.md 且状态 accepted
  local adr
  for adr in "$adr_dir"/allow-"${check}"-*.md; do
    [ -f "$adr" ] || continue
    # 状态须为 accepted（排除 deprecated/superseded）
    grep -Eq '^- 状态:\s*accepted' "$adr" || continue
    # 必须有 清零截止 字段（无则不放行，逼写计划）
    grep -Eq '^- 清零截止:\s*\S+' "$adr" || continue
    # "引入的合规豁免" 须精确列出该违规路径
    if grep -Eq "引入的合规豁免:.*${violation_path}" "$adr"; then
      return 0
    fi
  done
  return 1
}
