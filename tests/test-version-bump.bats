#!/usr/bin/env bats

load 'test-helper'

# setup: 在 BATS_TMPDIR 下搭一个 fake evolve_home + fake hanflow, 包含 4 个版本位置
# 用本文件唯一子目录避免与其它 test 文件 (同样用 BATS_TMPDIR) 并发/串行时互相覆盖。
setup() {
  BASE="$BATS_TMPDIR/vbump"
  EVOLVE="$BASE/evolve"
  HANFLOW="$BASE/hanflow"
  rm -rf "$EVOLVE" "$HANFLOW"
  mkdir -p "$EVOLVE" "$HANFLOW/hanflow" "$HANFLOW/api" "$HANFLOW/web"

  # 1) hanflow/__init__.py  (权威版本源)
  cat > "$HANFLOW/hanflow/__init__.py" <<'EOF'
__version__ = "1.0.0"
EOF

  # 2) api/__init__.py  (FastAPI version=)
  cat > "$HANFLOW/api/__init__.py" <<'EOF'
from fastapi import FastAPI
app = FastAPI(version="1.0.0", title="hanflow")
EOF

  # 3) pyproject.toml  (version = "...")
  cat > "$HANFLOW/pyproject.toml" <<'EOF'
[project]
name = "hanflow"
version = "1.0.0"
description = "hanflow framework"
EOF

  # 4) web/package.json  (version 字段)
  cat > "$HANFLOW/web/package.json" <<'EOF'
{
  "name": "hanflow-web",
  "version": "1.0.0",
  "private": true
}
EOF

  # evolve_home config 指向 fake hanflow
  cat > "$EVOLVE/config.yaml" <<EOF
paths:
  hanflow: "$HANFLOW"
  evolve_home: "$EVOLVE"
versioning:
  baseline: "1.0.0"
  authoritative_source: "hanflow/__init__.py"
EOF
}

@test "updates all 4 version locations" {
  run bash "$SCRIPTS_DIR/version-bump.sh" "$EVOLVE" "1.1.0"
  [ "$status" -eq 0 ]

  init_line=$(grep '__version__' "$HANFLOW/hanflow/__init__.py")
  api_line=$(grep 'version=' "$HANFLOW/api/__init__.py")
  py_line=$(grep '^version' "$HANFLOW/pyproject.toml")
  pkg_line=$(grep '"version"' "$HANFLOW/web/package.json")

  echo "$init_line" | grep "1.1.0"
  echo "$api_line"  | grep "1.1.0"
  echo "$py_line"   | grep "1.1.0"
  echo "$pkg_line"  | grep "1.1.0"
}

@test "creates changelog entry" {
  run bash "$SCRIPTS_DIR/version-bump.sh" "$EVOLVE" "1.1.0"
  [ "$status" -eq 0 ]

  [ -f "$HANFLOW/CHANGELOG.md" ]
  grep -E "^# .*1\.1\.0|^## .*1\.1\.0" "$HANFLOW/CHANGELOG.md"
}

@test "fails on version downgrade" {
  run bash "$SCRIPTS_DIR/version-bump.sh" "$EVOLVE" "0.9.0"
  [ "$status" -ne 0 ]

  # 原版本保持 1.0.0 不变
  grep '"1.0.0"' "$HANFLOW/hanflow/__init__.py"
}
