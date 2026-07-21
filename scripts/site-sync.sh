#!/usr/bin/env bash
# site-sync.sh — RELEASE Phase C: 同步 hanflow-site 到最新 hanflow 版本 (spec §5.5)
#
# 用法: site-sync.sh <evolve_home>
#
# 触发条件 (用户 2026-07-21 反馈, 取代 spec §5.5 原 "仅 feat/BREAKING" 规则):
#   **hanflow 版本号变化即同步**。本脚本无条件触发, 内部幂等。
#
# 行为:
#   1. 从 config.yaml paths.hanflow_site 读 site 仓库路径
#   2. 从 state.yaml current_version 读 LATEST (权威源)
#   3. 校验: site 仓库存在; main 分支干净 (允许 content/<version>/ untracked); remote 已配
#   4. 若 content/<LATEST>/ 已存在 且 lib/versions.ts LATEST 已对 → 视为已同步, 退出 0
#   5. cp -r content/<prev>/ content/<LATEST>/ (若不存在; placeholder 内容)
#   6. 改 lib/versions.ts (VERSIONS 追加 + LATEST 更新)
#   7. 改 tests/versions.test.ts (LATEST 期望值)
#   8. 改 package.json version 字段
#   9. 改 content/<LATEST>/{en,zh}/core-concepts/dsl-syntax.mdx frontmatter
#   10. npm run test (vitest 必须过)
#   11. git add -A && git commit && git push (vercel 自动重建)
#
# 幂等性: 已同步时退出 0 (不视为错误), P10 重复跑或版本未变化时不产生空 commit。
#
# Windows/MSYS 兼容: 路径经环境变量传 python, 不插值进 python -c 字符串。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: site-sync.sh <evolve_home>}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state.yaml"
for f in "$CONFIG" "$STATE"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: missing $f" >&2
    exit 1
  fi
done

# 一次性把 site 路径 + LATEST 版本读出来 (走环境变量)
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
paths = c.get('paths') or {}
print(paths.get('hanflow_site') or '')
print(s.get('current_version') or '')
")
SITE_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
LATEST=$(printf '%s' "$READ_OUT" | sed -n '2p')

if [ -z "$SITE_PATH" ]; then
  echo "ERROR: config.yaml paths.hanflow_site is empty" >&2
  exit 1
fi
if [ -z "$LATEST" ]; then
  echo "ERROR: state.yaml current_version is empty" >&2
  exit 1
fi
if [ ! -d "$SITE_PATH" ]; then
  echo "ERROR: hanflow-site path not found: $SITE_PATH" >&2
  exit 1
fi

echo "[site-sync] site=$SITE_PATH target=v$LATEST"

# 校验 site 仓库干净 (允许 content/<version>/ 形式的 untracked, 那是脚本中间产物)
PORCELAIN=$(git -C "$SITE_PATH" status --porcelain 2>/dev/null || true)
DIRTY=$(printf '%s\n' "$PORCELAIN" | grep -v -E '^\?\? content/[0-9]+\.[0-9]+\.[0-9]+(/|$)' || true)
if [ -n "$DIRTY" ]; then
  echo "ERROR: site repo has unexpected uncommitted changes:" >&2
  printf '%s\n' "$DIRTY" >&2
  exit 1
fi

# git remote (允许无 remote, 仅本地 commit)
REMOTES=$(git -C "$SITE_PATH" remote 2>/dev/null || true)

# === 幂等检查 ===
VERSIONS_TS="$SITE_PATH/lib/versions.ts"
if [ -d "$SITE_PATH/content/$LATEST" ] && \
   grep -q "LATEST_VERSION: Version = '$LATEST'" "$VERSIONS_TS" 2>/dev/null; then
  echo "[site-sync] already synced to v$LATEST (idempotent skip)"
  echo "OK: site-sync no-op"
  exit 0
fi

# === cp content/<prev>/ → content/<LATEST>/ (若不存在) ===
if [ ! -d "$SITE_PATH/content/$LATEST" ]; then
  PREV=$(ls -1 "$SITE_PATH/content/" 2>/dev/null | sort -rV | head -1 || true)
  if [ -z "$PREV" ]; then
    echo "ERROR: no existing content/<version>/ to use as template" >&2
    exit 1
  fi
  echo "[site-sync] cp -r content/$PREV content/$LATEST"
  cp -r "$SITE_PATH/content/$PREV" "$SITE_PATH/content/$LATEST"
fi

# === 改 lib/versions.ts + tests/versions.test.ts + package.json + dsl-syntax frontmatter ===
# 一次 python heredoc 做完所有 Python 可处理的文件改写, 减少重复
echo "[site-sync] updating lib/versions.ts + tests + package.json + dsl-syntax frontmatter"
SITE_PATH_ENV="$SITE_PATH" TARGET_VERSION_ENV="$LATEST" python <<'PYEOF'
import json
import os
import re

site = os.environ['SITE_PATH_ENV']
latest = os.environ['TARGET_VERSION_ENV']

# --- lib/versions.ts ---
p = os.path.join(site, 'lib', 'versions.ts')
with open(p, encoding='utf-8') as fh:
    src = fh.read()
m = re.search(r"export const VERSIONS = \[([^\]]*)\]", src)
if not m:
    raise SystemExit(f"ERROR: VERSIONS array not found in {p}")
existing = re.findall(r"'([^']+)'", m.group(1))
if latest not in existing:
    existing.append(latest)
new_inner = ', '.join(f"'{v}'" for v in existing)
# 替换整个 VERSIONS 语句 (含可选 'as const'), 避免重复 'as const'
src = re.sub(
    r"export const VERSIONS = \[[^\]]*\](\s+as\s+const)?",
    f"export const VERSIONS = [{new_inner}] as const;",
    src,
)
src = re.sub(
    r"export const LATEST_VERSION: Version = '[^']+';",
    f"export const LATEST_VERSION: Version = '{latest}';",
    src,
)
with open(p, 'w', encoding='utf-8', newline='\n') as fh:
    fh.write(src)
print(f"  lib/versions.ts: VERSIONS=[{new_inner}] LATEST='{latest}'")

# --- tests/versions.test.ts ---
# cycle 2026-W30-1.1.1 之后, test 文件不再硬编码 LATEST 字符串,
# 而是从 lib/versions.ts 引用常量。site-sync 不需要改 test 文件,
# 只跑 npm test 验证 (下面 Step F)。
p = os.path.join(site, 'tests', 'versions.test.ts')
if os.path.isfile(p):
    print(f"  tests/versions.test.ts: uses LATEST_VERSION const, no edit needed")

# --- package.json ---
p = os.path.join(site, 'package.json')
with open(p, encoding='utf-8') as fh:
    data = json.load(fh)
old = data.get('version')
data['version'] = latest
with open(p, 'w', encoding='utf-8', newline='\n') as fh:
    json.dump(data, fh, indent=2)
    fh.write('\n')
print(f"  package.json: version {old} -> {latest}")

# --- content/<LATEST>/{en,zh}/core-concepts/dsl-syntax.mdx frontmatter ---
for locale in ('en', 'zh'):
    p = os.path.join(site, 'content', latest, locale, 'core-concepts', 'dsl-syntax.mdx')
    if not os.path.isfile(p):
        continue
    with open(p, encoding='utf-8') as fh:
        lines = fh.readlines()
    changed = False
    for i, line in enumerate(lines):
        if line.startswith('version: '):
            lines[i] = f'version: "{latest}"\n'
            changed = True
    if changed:
        with open(p, 'w', encoding='utf-8', newline='\n') as fh:
            fh.writelines(lines)
        print(f"  content/{latest}/{locale}/core-concepts/dsl-syntax.mdx frontmatter -> {latest}")
PYEOF

# === npm run test ===
echo "[site-sync] npm run test"
cd "$SITE_PATH"
if ! npm run test 2>&1 | tail -15; then
  echo "ERROR: npm run test failed in site repo" >&2
  exit 1
fi

# === git commit + push ===
cd "$SITE_PATH"
git add -A
if git diff --cached --quiet; then
  echo "[site-sync] no net changes (idempotent)"
  echo "OK: site-sync no-op"
  exit 0
fi

git commit -m "feat: sync site to v$LATEST (auto via LOOP site-sync.sh)

Auto-synced by hanflow-evolve/scripts/site-sync.sh during release phase.
Version switcher updated to v$LATEST. Content for new features is a
placeholder copied from previous version; actual mdx regeneration is a
separate content cycle." 2>&1 | tail -3

if [ -n "$REMOTES" ]; then
  PUSHED=0
  for REMOTE in $REMOTES; do
    echo "[site-sync] pushing to remote '$REMOTE'"
    if git push "$REMOTE" main 2>&1; then
      echo "[site-sync] pushed to $REMOTE (vercel auto-rebuilds)"
      PUSHED=1
      break
    else
      echo "WARN: push to $REMOTE failed" >&2
    fi
  done
  if [ "$PUSHED" -eq 0 ]; then
    echo "WARN: all remotes failed; commit is local-only" >&2
  fi
else
  echo "[site-sync] no remote configured; local commit only"
fi

echo "OK: site-sync done (v$LATEST)"
