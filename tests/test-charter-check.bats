#!/usr/bin/env bats

load 'test-helper'

# errors.sh 需要两个参数：<hanflow_path> <mode> <adr_dir>
# 退出 0=通过，1=有违规

@test "errors.sh passes when all Errors inherit HanflowError" {
  # 用一个全合规的 fixture
  fix="$TEST_FIXTURES/charter-ok"
  mkdir -p "$fix/hanflow/core"
  cat > "$fix/hanflow/core/errors.py" <<'EOF'
class HanflowError(Exception):
    code: str = "HANFLOW_ERROR"
EOF
  mkdir -p "$fix/hanflow/atoms"
  cat > "$fix/hanflow/atoms/good.py" <<'EOF'
from hanflow.core.errors import HanflowError
class GoodError(HanflowError):
    pass
EOF
  touch "$fix/hanflow/__init__.py" "$fix/hanflow/core/__init__.py" "$fix/hanflow/atoms/__init__.py"

  run bash "$SCRIPTS_DIR/charter-check/errors.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^OK: errors"
}

@test "errors.sh fails when an Error does not inherit HanflowError" {
  fix="$TEST_FIXTURES/charter-fail"
  # fixture 已在 Step1 创建，含 atoms/bad.py 的 BadError(Exception)

  run bash "$SCRIPTS_DIR/charter-check/errors.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "BadError"
  echo "$output" | grep -q "HanflowError"
}

@test "registry.sh passes when using registry lookup" {
  fix="$TEST_FIXTURES/charter-ok"
  mkdir -p "$fix/hanflow/orchestration"
  cat > "$fix/hanflow/orchestration/good_compiler.py" <<'EOF'
def compile(node):
    executor = registry.get(node.type)  # 合规：走 registry
    return executor.run(node)
EOF
  touch "$fix/hanflow/__init__.py" "$fix/hanflow/orchestration/__init__.py"

  run bash "$SCRIPTS_DIR/charter-check/registry.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^OK: registry"
}

@test "registry.sh fails on if/elif node.type dispatch" {
  fix="$TEST_FIXTURES/charter-fail"
  run bash "$SCRIPTS_DIR/charter-check/registry.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE '\.type\s*=='
  echo "$output" | grep -q "bad_compiler"
}
