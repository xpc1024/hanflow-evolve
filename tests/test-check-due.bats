#!/usr/bin/env bats

load 'test-helper'

# 写一个最小 config.yaml (reminder 启用) + state.yaml (可定制 last_cycle/phase)
write_reminder_config() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/config.yaml" <<'EOF'
schedule:
  reminder:
    enabled: true
    interval_days: 7
    suppress_hours: 24
EOF
}

write_state() {
  local dir="$1"
  local last_cycle="$2"
  local phase="$3"
  local last_reminded="${4:-null}"
  cat > "$dir/state.yaml" <<EOF
cycle_id: "2026-W28-1.1.0"
phase: "$phase"
last_cycle_completed: "$last_cycle"
last_reminded: $last_reminded
EOF
}

@test "outputs reminder when interval exceeded" {
  EVOLVE="$BATS_TMPDIR/cdue/ev"
  rm -rf "$EVOLVE"; mkdir -p "$EVOLVE"
  write_reminder_config "$EVOLVE"
  # last_cycle 10 天前 (NOW=2026-07-20, last=2026-07-10), phase=awaiting_next_cycle
  write_state "$EVOLVE" "2026-07-10" "awaiting_next_cycle"

  # NOW_DATE 注入 "今天", 避免依赖系统时钟
  output=$(NOW_DATE="2026-07-20" bash "$SCRIPTS_DIR/check-due.sh" "$EVOLVE")
  echo "$output" | grep "LOOP 提醒"
}

@test "silent when within interval" {
  EVOLVE="$BATS_TMPDIR/cdue/ev"
  rm -rf "$EVOLVE"; mkdir -p "$EVOLVE"
  write_reminder_config "$EVOLVE"
  # last_cycle 2 天前 (NOW=2026-07-12, last=2026-07-10)
  write_state "$EVOLVE" "2026-07-10" "awaiting_next_cycle"

  output=$(NOW_DATE="2026-07-12" bash "$SCRIPTS_DIR/check-due.sh" "$EVOLVE")
  [ -z "$output" ]
}

@test "silent when reminder disabled" {
  EVOLVE="$BATS_TMPDIR/cdue/ev"
  rm -rf "$EVOLVE"; mkdir -p "$EVOLVE"
  # config 关闭 reminder
  cat > "$EVOLVE/config.yaml" <<'EOF'
schedule:
  reminder:
    enabled: false
    interval_days: 7
    suppress_hours: 24
EOF
  write_state "$EVOLVE" "2026-07-10" "awaiting_next_cycle"

  output=$(NOW_DATE="2026-07-20" bash "$SCRIPTS_DIR/check-due.sh" "$EVOLVE")
  [ -z "$output" ]
}

@test "silent when not initialized" {
  EVOLVE="$BATS_TMPDIR/cdue/ev"
  rm -rf "$EVOLVE"; mkdir -p "$EVOLVE"
  write_reminder_config "$EVOLVE"
  # 没有 state.yaml
  output=$(NOW_DATE="2026-07-20" bash "$SCRIPTS_DIR/check-due.sh" "$EVOLVE")
  [ -z "$output" ]
}
