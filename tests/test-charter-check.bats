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

@test "pydantic-data.sh passes when Config uses BaseModel" {
  fix="$TEST_FIXTURES/charter-ok"
  mkdir -p "$fix/hanflow/models"
  cat > "$fix/hanflow/models/good_config.py" <<'EOF'
from pydantic import BaseModel

class RouterConfig(BaseModel):  # 合规
    model: str
EOF
  touch "$fix/hanflow/__init__.py" "$fix/hanflow/models/__init__.py"

  run bash "$SCRIPTS_DIR/charter-check/pydantic-data.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 0 ]
}

@test "pydantic-data.sh fails when Config class uses @dataclass" {
  fix="$TEST_FIXTURES/charter-fail"
  run bash "$SCRIPTS_DIR/charter-check/pydantic-data.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "RouterConfig"
  echo "$output" | grep -q "dataclass"
}

@test "async-api.sh passes when IO methods are async" {
  fix="$TEST_FIXTURES/charter-ok"
  mkdir -p "$fix/hanflow/models"
  cat > "$fix/hanflow/models/good_router.py" <<'EOF'
async def complete(prompt):  # 合规
    return ""


def estimate_cost(model):  # 合规（不在 IO 方法名模式内）
    return 0.0
EOF
  touch "$fix/hanflow/__init__.py" "$fix/hanflow/models/__init__.py"

  run bash "$SCRIPTS_DIR/charter-check/async-api.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 0 ]
}

@test "async-api.sh fails when IO method is sync def" {
  fix="$TEST_FIXTURES/charter-fail"
  run bash "$SCRIPTS_DIR/charter-check/async-api.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "complete"
}

@test "layering.sh passes when deps respect matrix" {
  fix="$TEST_FIXTURES/charter-ok"
  mkdir -p "$fix/hanflow/atoms" "$fix/hanflow/core"
  cat > "$fix/hanflow/core/errors.py" <<'EOF'
class HanflowError(Exception):
    code: str = "HANFLOW_ERROR"
EOF
  cat > "$fix/hanflow/atoms/good_dep.py" <<'EOF'
from hanflow.core.errors import HanflowError  # 合规：atoms 可依赖 core
EOF
  touch "$fix/hanflow/__init__.py" "$fix/hanflow/core/__init__.py" "$fix/hanflow/atoms/__init__.py"

  run bash "$SCRIPTS_DIR/charter-check/layering.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^OK: layering"
}

@test "layering.sh fails on illegal cross-layer dependency" {
  fix="$TEST_FIXTURES/charter-fail"
  run bash "$SCRIPTS_DIR/charter-check/layering.sh" "$fix" full "$SCRIPTS_DIR/../docs/adr"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "atoms"
  echo "$output" | grep -q "models"
}

@test "charter-check.sh --doc WARNs on architecture change without ADR" {
  doc="$BATS_TMPDIR/design-no-adr.md"
  cat > "$doc" <<'EOF'
# 设计：新增 retrieval 模块
## 组件分解
新增 hanflow/retrieval 包。
EOF
  run bash "$SCRIPTS_DIR/charter-check/charter-check.sh" --doc "$doc"
  [ "$status" -eq 0 ]  # WARN 非 FAIL
  echo "$output" | grep -q "WARN"
}

@test "charter-check.sh --doc OK when architecture change has ADR link" {
  doc="$BATS_TMPDIR/design-with-adr.md"
  cat > "$doc" <<'EOF'
# 设计：迁移 memory 模块
本次迁移见 ADR-0007。
EOF
  run bash "$SCRIPTS_DIR/charter-check/charter-check.sh" --doc "$doc"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "charter-check.sh --full --only errors runs single check" {
  # 在真实代码库上 errors 会发现 ExprError violation (exit 1)，
  # 但这里只验证聚合入口能正确调度单条检查（不崩、有输出）
  run bash "$SCRIPTS_DIR/charter-check/charter-check.sh" --full --only errors
  # errors 在真实库有 1 个违规 → exit 1；验证它确实跑了 errors 检查
  echo "$output" | grep -q "errors"
  echo "$output" | grep -q "ExprError"
}
