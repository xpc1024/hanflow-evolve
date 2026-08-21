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

@test "filters completed (strikethrough) LEARNINGS entries" {
  mkdir -p "$BATS_TMPDIR/t4/fake-hanflow/hanflow"
  echo "# clean" > "$BATS_TMPDIR/t4/fake-hanflow/hanflow/clean.py"

  mkdir -p "$BATS_TMPDIR/t4/fake-evolve/cycles/test-cycle4"
  cat > "$BATS_TMPDIR/t4/fake-evolve/LEARNINGS.md" <<'MDEOF'
# LEARNINGS (fixture)

## 下次优先

1. ~~旧 bug 甲~~ ✓ 已修 (2026-W31-1.2.1)
- ~~另一旧账~~ ✓ 已完成 (v1.2.0)
3. **[高] 真实待办甲** —— 需要实现
4. **[高] signal-gather 过滤** —— 混入已完成项 (score-signals bug 已修、mypy 已恢复), 行首无划线的边界待办
5. ~~**[中] 旧账丙**~~ ✓ 已恢复 (2026-W31-1.2.1)

## 失败教训

fixture 下一段, 防段落边界串读。
MDEOF
  cat > "$BATS_TMPDIR/t4/fake-evolve/config.yaml" <<EOF
paths:
  hanflow: "$BATS_TMPDIR/t4/fake-hanflow"
  evolve_home: "$BATS_TMPDIR/t4/fake-evolve"
signals:
  github: {enabled: false}
  source_stubs: {enabled: false}
  learnings: {enabled: true}
  competitor: {enabled: false}
learning:
  learnings_file: "LEARNINGS.md"
EOF

  bash "$SCRIPTS_DIR/signal-gather.sh" "$BATS_TMPDIR/t4/fake-evolve" "test-cycle4"

  result_file="$BATS_TMPDIR/t4/fake-evolve/cycles/test-cycle4/signals.json"
  [ -f "$result_file" ]

  # 5 条中 3 条行首 ~~ (已完成) 应被过滤; 边界条目 (正文含"已修") 不误杀
  LEARN_JSON="$result_file" python - <<'PYEOF'
import json, os
d = json.load(open(os.environ['LEARN_JSON']))
sigs = d['signals']
assert len(sigs) == 2, f"expect 2, got {len(sigs)}: {[s['id'] for s in sigs]}"
assert all(not s['raw']['text'].startswith('~~') for s in sigs), sigs
texts = [s['raw']['text'] for s in sigs]
assert any('signal-gather' in t for t in texts), texts
assert [s['id'] for s in sigs] == ['learning:1', 'learning:2'], sigs
print('filter-ok')
PYEOF
}
