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

@test "update-backlog.sh preserves existing Done entries (regression: W34/W37 wiped Done)" {
  mkdir -p "$BATS_TMPDIR/t3/fake-evolve/cycles/test3"
  cat > "$BATS_TMPDIR/t3/fake-evolve/cycles/test3/scored.json" <<'EOF'
{
  "themes": [
    {"theme_id": "T-a", "title": "Alpha", "member_signals": ["s1"], "affected_modules": [],
     "theme_score": 50, "version_impact": "patch", "estimated_effort": "small", "risk": "low", "source": "ai_signal"}
  ]
}
EOF
  cat > "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md" <<'EOF'
# BACKLOG.md — 旧内容 (将被全量重生成)

## 待实现 (Pending)

(旧 pending, 应被替换)

---

## 已完成 (Done)

> 已合并到 main 并 release 的主题。保留简短记录 (cycle_id / 版本 / 主题 / 日期)。

- `2026-W32-1.2.2` · v1.2.3 · docker-provisioner-real-contract-tests(human_override) · 2026-08-04
  — DockerProvisioner 真实测试 CI 可见性加固。
- `2026-W31-1.2.1` · v1.2.1 · clear-preexisting-tech-debt-s0-gates(human_override) · 2026-07-29
  — 清零 S0 三道门。

---

## 暂缓 (Deferred)

(空)
EOF

  bash "$SCRIPTS_DIR/update-backlog.sh" "$BATS_TMPDIR/t3/fake-evolve" "test3"

  # Done 历史条目必须在重生成后保留
  grep -q "2026-W32-1.2.2" "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md"
  grep -q "2026-W31-1.2.1" "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md"
  # 新主题也正常渲染
  grep -q "Alpha" "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md"
  # Done 段不再是无脑 (空): W32 条目所在行位于 Done 标题之后
  done_line=$(grep -n "^## 已完成 (Done)" "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md" | cut -d: -f1)
  entry_line=$(grep -n "2026-W32-1.2.2" "$BATS_TMPDIR/t3/fake-evolve/BACKLOG.md" | cut -d: -f1)
  [ -n "$done_line" ] && [ -n "$entry_line" ]
  [ "$done_line" -lt "$entry_line" ]
}

@test "update-backlog.sh keeps Done empty when no prior entries" {
  mkdir -p "$BATS_TMPDIR/t4/fake-evolve/cycles/test4"
  cat > "$BATS_TMPDIR/t4/fake-evolve/cycles/test4/scored.json" <<'EOF'
{
  "themes": [
    {"theme_id": "T-b", "title": "Beta", "member_signals": [], "affected_modules": [],
     "theme_score": 10, "version_impact": "patch", "estimated_effort": "small", "risk": "low", "source": "ai_signal"}
  ]
}
EOF
  printf '# BACKLOG 旧文件无 Done 条目\n\n## 已完成 (Done)\n\n(空)\n' > "$BATS_TMPDIR/t4/fake-evolve/BACKLOG.md"

  bash "$SCRIPTS_DIR/update-backlog.sh" "$BATS_TMPDIR/t4/fake-evolve" "test4"

  # 无历史时 Done 段仍为 (空), 不误造内容 (只看 Done 标题之后, 避开 In Progress 的占位行)
  done_line=$(grep -n "^## 已完成 (Done)" "$BATS_TMPDIR/t4/fake-evolve/BACKLOG.md" | cut -d: -f1)
  empty_line=$(tail -n +"$((done_line + 1))" "$BATS_TMPDIR/t4/fake-evolve/BACKLOG.md" | grep -n "^(空)" | head -1 | cut -d: -f1)
  [ -n "$done_line" ] && [ -n "$empty_line" ]
}
