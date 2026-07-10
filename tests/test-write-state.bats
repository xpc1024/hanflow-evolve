#!/usr/bin/env bats

load 'test-helper'

@test "write-state.sh updates a single field atomically" {
  cp "$TEST_FIXTURES/state-initial.yaml" "$BATS_TMPDIR/state.yaml"
  bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/state.yaml" cycle_id '"2026-W28-1.1.0"'
  result=$(grep '^cycle_id:' "$BATS_TMPDIR/state.yaml" | head -1)
  [ "$result" = "cycle_id: \"2026-W28-1.1.0\"" ]
}

@test "write-state.sh leaves other fields unchanged" {
  cp "$TEST_FIXTURES/state-initial.yaml" "$BATS_TMPDIR/state.yaml"
  bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/state.yaml" phase '"scan"'
  result=$(grep '^current_version:' "$BATS_TMPDIR/state.yaml" | head -1)
  [ "$result" = "current_version: \"1.0.0\"" ]
}

@test "write-state.sh rejects invalid YAML and restores original" {
  cp "$TEST_FIXTURES/state-initial.yaml" "$BATS_TMPDIR/state.yaml"
  cp "$BATS_TMPDIR/state.yaml" "$BATS_TMPDIR/state.yaml.backup"
  run bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/state.yaml" phase '": : broken'
  [ "$status" -ne 0 ]
  diff "$BATS_TMPDIR/state.yaml.backup" "$BATS_TMPDIR/state.yaml"
}

@test "write-state.sh fails when state file does not exist" {
  run bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/nonexistent.yaml" phase '"scan"'
  [ "$status" -ne 0 ]
}
