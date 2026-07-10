#!/usr/bin/env bats

load 'test-helper'

@test "signal-gather.sh collects NotImplementedError stubs from hanflow source" {
  mkdir -p "$BATS_TMPDIR/t1/fake-hanflow/hanflow/cli"
  cat > "$BATS_TMPDIR/t1/fake-hanflow/hanflow/cli/main.py" <<'PYEOF'
def resume():
    raise NotImplementedError("delegates to SDK")

def run():
    print("real")
PYEOF
  cat > "$BATS_TMPDIR/t1/fake-hanflow/hanflow/stub.py" <<'PYEOF'
# deferred to Phase 17: wire real Redis
pass
PYEOF

  mkdir -p "$BATS_TMPDIR/t1/fake-evolve/cycles/test-cycle"
  cat > "$BATS_TMPDIR/t1/fake-evolve/config.yaml" <<EOF
paths:
  hanflow: "$BATS_TMPDIR/t1/fake-hanflow"
  evolve_home: "$BATS_TMPDIR/t1/fake-evolve"
signals:
  github:
    enabled: false
  source_stubs:
    enabled: true
    patterns: ["NotImplementedError", "deferred to Phase"]
  learnings:
    enabled: false
  competitor:
    enabled: false
EOF

  bash "$SCRIPTS_DIR/signal-gather.sh" "$BATS_TMPDIR/t1/fake-evolve" "test-cycle"

  result_file="$BATS_TMPDIR/t1/fake-evolve/cycles/test-cycle/signals.json"
  [ -f "$result_file" ]

  # 路径经环境变量传入 python (native Windows python 无法 open 被
  # 插值进 -c 字符串的 MSYS 路径如 /tmp/...)
  count=$(SIGNALS_JSON="$result_file" python -c "import json,os; d=json.load(open(os.environ['SIGNALS_JSON'])); print(len(d['signals']))")
  [ "$count" -eq 2 ]
}

@test "signal-gather.sh marks degraded when github disabled" {
  mkdir -p "$BATS_TMPDIR/t2/fake-hanflow/hanflow"
  echo "# clean file" > "$BATS_TMPDIR/t2/fake-hanflow/hanflow/clean.py"

  mkdir -p "$BATS_TMPDIR/t2/fake-evolve/cycles/test-cycle2"
  cat > "$BATS_TMPDIR/t2/fake-evolve/config.yaml" <<EOF
paths:
  hanflow: "$BATS_TMPDIR/t2/fake-hanflow"
  evolve_home: "$BATS_TMPDIR/t2/fake-evolve"
signals:
  github: {enabled: false}
  source_stubs: {enabled: true, patterns: ["NotImplementedError"]}
  learnings: {enabled: false}
  competitor: {enabled: false}
EOF

  bash "$SCRIPTS_DIR/signal-gather.sh" "$BATS_TMPDIR/t2/fake-evolve" "test-cycle2"
  degraded=$(SIGNALS_JSON="$BATS_TMPDIR/t2/fake-evolve/cycles/test-cycle2/signals.json" python -c "import json,os; d=json.load(open(os.environ['SIGNALS_JSON'])); print(d['degraded']['gh'])")
  [ "$degraded" = "disabled_by_config" ]
}

@test "signal-gather.sh produces valid JSON even when no signals found" {
  mkdir -p "$BATS_TMPDIR/t3/fake-hanflow/hanflow"
  echo "# clean" > "$BATS_TMPDIR/t3/fake-hanflow/hanflow/clean.py"
  mkdir -p "$BATS_TMPDIR/t3/fake-evolve/cycles/test-cycle3"
  cat > "$BATS_TMPDIR/t3/fake-evolve/config.yaml" <<EOF
paths:
  hanflow: "$BATS_TMPDIR/t3/fake-hanflow"
  evolve_home: "$BATS_TMPDIR/t3/fake-evolve"
signals:
  github: {enabled: false}
  source_stubs: {enabled: true, patterns: ["NotImplementedError"]}
  learnings: {enabled: false}
  competitor: {enabled: false}
EOF

  bash "$SCRIPTS_DIR/signal-gather.sh" "$BATS_TMPDIR/t3/fake-evolve" "test-cycle3"
  SIGNALS_JSON="$BATS_TMPDIR/t3/fake-evolve/cycles/test-cycle3/signals.json" python -c "import json,os; d=json.load(open(os.environ['SIGNALS_JSON'])); assert d['signals'] == []; print('valid empty')"
}
