#!/usr/bin/env bats

load 'test-helper'

@test "update-backlog.sh creates BACKLOG with themes sorted by score" {
  mkdir -p "$BATS_TMPDIR/fake-evolve/cycles/test"
  cat > "$BATS_TMPDIR/fake-evolve/cycles/test/scored.json" <<'EOF'
{
  "themes": [
    {"theme_id": "T-cli", "title": "CLI", "member_signals": ["s1"], "affected_modules": ["cli"],
     "theme_score": 78, "version_impact": "minor", "estimated_effort": "medium", "risk": "low", "source": "ai_signal"},
    {"theme_id": "T-llm", "title": "LLM", "member_signals": ["s2"], "affected_modules": ["models"],
     "theme_score": 71, "version_impact": "minor", "estimated_effort": "large", "risk": "medium", "source": "ai_signal"}
  ]
}
EOF
  touch "$BATS_TMPDIR/fake-evolve/BACKLOG.md"

  bash "$SCRIPTS_DIR/update-backlog.sh" "$BATS_TMPDIR/fake-evolve" "test"

  cli_line=$(grep -n "CLI" "$BATS_TMPDIR/fake-evolve/BACKLOG.md" | head -1 | cut -d: -f1)
  llm_line=$(grep -n "LLM" "$BATS_TMPDIR/fake-evolve/BACKLOG.md" | head -1 | cut -d: -f1)
  [ -n "$cli_line" ] && [ -n "$llm_line" ]
  [ "$cli_line" -lt "$llm_line" ]
}

@test "update-backlog.sh places human_override at top regardless of score" {
  mkdir -p "$BATS_TMPDIR/fake-evolve/cycles/test2"
  cat > "$BATS_TMPDIR/fake-evolve/cycles/test2/scored.json" <<'EOF'
{
  "themes": [
    {"theme_id": "T-low-score", "title": "LowScore", "member_signals": [], "affected_modules": [],
     "theme_score": 99, "version_impact": "minor", "estimated_effort": "small", "risk": "low", "source": "ai_signal"},
    {"theme_id": "T-human", "title": "HumanTopic", "member_signals": [], "affected_modules": [],
     "theme_score": 0, "version_impact": "minor", "estimated_effort": "medium", "risk": "low", "source": "human_override"}
  ]
}
EOF
  touch "$BATS_TMPDIR/fake-evolve/BACKLOG.md"

  bash "$SCRIPTS_DIR/update-backlog.sh" "$BATS_TMPDIR/fake-evolve" "test2"

  human_line=$(grep -n "HumanTopic" "$BATS_TMPDIR/fake-evolve/BACKLOG.md" | head -1 | cut -d: -f1)
  low_line=$(grep -n "LowScore" "$BATS_TMPDIR/fake-evolve/BACKLOG.md" | head -1 | cut -d: -f1)
  [ "$human_line" -lt "$low_line" ]
}
