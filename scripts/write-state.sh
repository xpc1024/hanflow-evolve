#!/usr/bin/env bash
# write-state.sh — 原子更新 state.yaml 的单个字段 (spec §8.5)
# 用法: write-state.sh <state.yaml> <key> <yaml_value>
# yaml_value 必须是合法 YAML 值, 如 "scan" 或 '"scan"' 或 '123' 或 'null'
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

if grep -q "^${KEY}:" "$TMP"; then
  sed -i "s|^${KEY}:.*|${KEY}: ${VALUE}|" "$TMP"
else
  echo "${KEY}: ${VALUE}" >> "$TMP"
fi

if ! python -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TMP" 2>/dev/null; then
  echo "ERROR: resulting YAML is invalid, restoring original" >&2
  rm -f "$TMP"
  exit 1
fi

mv "$TMP" "$STATE_FILE"
