#!/usr/bin/env bash
# write-state.sh — 原子更新 state.yaml 的单个字段 (spec §8.5)
# 用法: write-state.sh <state.yaml> <key> <yaml_value>
# yaml_value 必须是合法 YAML 值, 如 "scan" 或 '"scan"' 或 '123' 或 'null'
#
# 支持两种 key 形式:
#   - 顶层 key (如 phase / cycle_id): 走 sed 快路径, 精确匹配 ^key: 行。
#   - 点号嵌套 key (如 submit.pr_code_url / artifacts.signals): 走 Python 路径,
#     正确处理嵌套映射表与缩进; 父表不存在时自动创建。避免把
#     submit.pr_code_url 写成顶层字面 key (旧 bug,曾导致 contribute-pr 的
#     PR URL 回填静默失败)。
set -euo pipefail

STATE_FILE="${1:?Usage: write-state.sh <state.yaml> <key> <yaml_value>}"
KEY="${2:?Missing key}"
VALUE="${3:?Missing value}"

if [ ! -f "$STATE_FILE" ]; then
  echo "ERROR: state file not found: $STATE_FILE" >&2
  exit 1
fi

TMP="${STATE_FILE}.tmp"
cp "$STATE_FILE" "$TMP"

if printf '%s' "$KEY" | grep -qv '\.'; then
  # 顶层 key: 维持原 sed 行为 (快路径, 保持既有调用方与测试不变)
  if grep -q "^${KEY}:" "$TMP"; then
    sed -i "s|^${KEY}:.*|${KEY}: ${VALUE}|" "$TMP"
  else
    echo "${KEY}: ${VALUE}" >> "$TMP"
  fi
else
  # 嵌套 key: 用 Python 做结构感知写入 (按点拆分逐层下钻, 父表缺失则建)
  TMP_PATH="$TMP" NESTED_KEY="$KEY" NESTED_VALUE="$VALUE" python - <<'PYEOF'
import os

import yaml

path = os.environ["TMP_PATH"]
key = os.environ["NESTED_KEY"]
raw_val = os.environ["NESTED_VALUE"]

with open(path, encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)
if doc is None:
    doc = {}

# raw_val 是调用方传入的 "YAML 值文本" (如 '"scan"' / '123' / 'null')。
# 用 yaml.safe_load 解析回 Python 对象, 保证与文件内既有值的类型一致。
value = yaml.safe_load(raw_val)

parts = key.split(".")
cursor = doc
for part in parts[:-1]:
    nxt = cursor.get(part)
    if not isinstance(nxt, dict):
        # 父段缺失或不是映射: 建空表覆盖 (与 write-state 语义一致: 单字段写入)
        nxt = {}
        cursor[part] = nxt
    cursor = nxt
cursor[parts[-1]] = value

with open(path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(doc, fh, allow_unicode=True, sort_keys=False, default_flow_style=False)
PYEOF
fi

if ! python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP" 2>/dev/null; then
  echo "ERROR: resulting YAML is invalid, restoring original" >&2
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$STATE_FILE"
