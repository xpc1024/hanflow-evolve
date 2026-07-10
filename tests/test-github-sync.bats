#!/usr/bin/env bats

load 'test-helper'

# setup: 在 BATS_TMPDIR 下搭一个 fake evolve_home + 一个真实本地 git fake hanflow
# 用本文件唯一子目录避免与其它 test 文件并发/串行时互相覆盖。
setup() {
  BASE="$BATS_TMPDIR/ghsync"
  EVOLVE="$BASE/evolve"
  HANFLOW="$BASE/hanflow"
  rm -rf "$EVOLVE" "$HANFLOW"
  mkdir -p "$EVOLVE" "$HANFLOW"

  # 把 fake hanflow 初始化为 git 仓库, 默认分支 main, 有一个基线 commit
  git -C "$HANFLOW" init -q -b main
  git -C "$HANFLOW" config user.email "test@example.com"
  git -C "$HANFLOW" config user.name "Test"
  echo "baseline" > "$HANFLOW/README.md"
  git -C "$HANFLOW" add -A
  git -C "$HANFLOW" commit -q -m "baseline"

  # evolve_home config + state
  cat > "$EVOLVE/config.yaml" <<EOF
paths:
  hanflow: "$HANFLOW"
  evolve_home: "$EVOLVE"
release:
  merge_strategy: "no-ff"
EOF

  cat > "$EVOLVE/state.yaml" <<'EOF'
cycle_id: "2026-W28-1.1.0"
target_version: "1.1.0"
phase: "release"
EOF
}

@test "aborts when feature branch does not exist" {
  # 没有 evolve/2026-W28-1.1.0 分支
  run bash "$SCRIPTS_DIR/github-sync.sh" "$EVOLVE"
  [ "$status" -ne 0 ]
  # 应提到分支名
  echo "$output" | grep "evolve/2026-W28-1.1.0"
}

@test "merges feature branch to main with no-ff" {
  # 在 fake hanflow 创建 evolve/2026-W28-1.1.0 分支并加一个 commit
  git -C "$HANFLOW" checkout -q -b "evolve/2026-W28-1.1.0"
  echo "feature work" > "$HANFLOW/FEATURE.md"
  git -C "$HANFLOW" add -A
  git -C "$HANFLOW" commit -q -m "feat: feature work"
  git -C "$HANFLOW" checkout -q main

  run bash "$SCRIPTS_DIR/github-sync.sh" "$EVOLVE"
  [ "$status" -eq 0 ]

  # main 上应能看到 FEATURE.md (no-ff 合并后内容进 main)
  [ -f "$HANFLOW/FEATURE.md" ]

  # main 的 log 应包含 feature commit 信息 (no-ff 会带 merge commit + 原 commit)
  git -C "$HANFLOW" log --oneline main | grep "feature work"

  # 应打了 tag v1.1.0
  git -C "$HANFLOW" tag --list | grep "v1.1.0"
}
