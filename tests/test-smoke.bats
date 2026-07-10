#!/usr/bin/env bats

load 'test-helper'

@test "exists and is executable" {
  [ -f "$SCRIPTS_DIR/smoke-test.sh" ]
  [ -x "$SCRIPTS_DIR/smoke-test.sh" ]
}

@test "fails when hanflow not found" {
  EVOLVE="$BATS_TMPDIR/smoke/ev"
  rm -rf "$EVOLVE"; mkdir -p "$EVOLVE"
  # config 指向一个不存在的 hanflow 路径
  cat > "$EVOLVE/config.yaml" <<EOF
paths:
  hanflow: "$BATS_TMPDIR/does-not-exist"
  evolve_home: "$EVOLVE"
EOF

  run bash "$SCRIPTS_DIR/smoke-test.sh" "$EVOLVE"
  [ "$status" -ne 0 ]
  # 应提示 hanflow 不可用 / not found
  echo "$output" | grep -i "not found\|FAIL\|hanflow"
}
