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

# 嵌套 key 支持 (submit.pr_code_url 等): 必须写入 submit: 表内, 而非顶层字面 key。
# 回归保护: 旧版本会把 submit.pr_code_url 当顶层 key, 导致 contribute-pr 的
# PR URL 回填静默失败 (state 里出现字面 "submit.pr_code_url:" 顶层行)。
@test "write-state.sh writes nested dot-key into its parent table" {
  cp "$TEST_FIXTURES/state-initial.yaml" "$BATS_TMPDIR/state-nested.yaml"
  # 先种一个 submit: 父表 (模拟 contribute-pr state 形态)
  printf 'submit:\n  fork_remote: "origin"\n' >> "$BATS_TMPDIR/state-nested.yaml"

  bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/state-nested.yaml" \
    submit.pr_code_url '"https://github.com/x/pull/1"'

  # 语义断言: 解析 YAML 后 submit.pr_code_url 应等于该 URL (而非顶层字面 key)
  result=$(STATE_FILE="$BATS_TMPDIR/state-nested.yaml" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((s.get('submit') or {}).get('pr_code_url') or '')
")
  [ "$result" = "https://github.com/x/pull/1" ]

  # 反向断言: 文件里绝不能出现顶层字面 'submit.pr_code_url:' 行
  ! grep -q '^submit\.pr_code_url:' "$BATS_TMPDIR/state-nested.yaml"
}

@test "write-state.sh auto-creates missing parent table for nested key" {
  cp "$TEST_FIXTURES/state-initial.yaml" "$BATS_TMPDIR/state-autocreate.yaml"

  bash "$SCRIPTS_DIR/write-state.sh" "$BATS_TMPDIR/state-autocreate.yaml" \
    submit.pr_docs_url '"https://github.com/x/pull/2"'

  result=$(STATE_FILE="$BATS_TMPDIR/state-autocreate.yaml" python -c "
import os, yaml
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((s.get('submit') or {}).get('pr_docs_url') or '')
")
  [ "$result" = "https://github.com/x/pull/2" ]
}
