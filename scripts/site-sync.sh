#!/usr/bin/env bash
# site-sync.sh — RELEASE Phase C: 同步 hanflow-home (大版本线模型)
#
# 用法: site-sync.sh <evolve_home>
#
# 行为 (大版本线模型, spec 2026-07-30):
#   从 state.yaml current_version 读 LATEST (精确 semver, 如 1.2.1)。
#   计算 MAJOR_LINE = "<major>.x" (如 1.x)。
#   - minor/patch bump: 在 content/<MAJOR_LINE>/ 原地更新 (不建文件夹, 不动 versions.ts)。
#   - major bump: 若 content/<MAJOR_LINE>/ 不存在, cp -r content/<旧major>.x/ → 新线。
#   versions.ts 由 gen-versions.mjs 在 build 时生成, 本脚本不手写。
#
#   1. 从 config.yaml paths.hanflow_home 读 site 路径; state.yaml current_version 读 LATEST
#   2. 校验 site 仓库存在 + 分支干净
#   3. 幂等检查: content/<MAJOR_LINE>/ 存在 且 package.json version == LATEST → 已同步, 退出 0
#   4. major bump: cp -r content/<prev_major>.x/ → content/<MAJOR_LINE>/ (若不存在)
#   5. 改 package.json version = LATEST (gen-versions 从此读 LATEST_SEMVER)
#   6. npm run build (含 prebuild gen-versions → versions.ts 自动更新)
#   7. git add -A && git commit && git push
#
# 注: content/<line>/core-concepts/dsl-syntax.mdx 的 frontmatter version: 字段经核实
# 无任何代码消费 (readDoc 只读 raw, 不解析 frontmatter), 不再写入/维护。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: site-sync.sh <evolve_home>}"
[ -d "$EVOLVE_HOME" ] || { echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2; exit 1; }

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state.yaml"
for f in "$CONFIG" "$STATE"; do
  [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# 读 site 路径 + LATEST
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((c.get('paths') or {}).get('hanflow_home') or '')
print(s.get('current_version') or '')
")
SITE_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
LATEST=$(printf '%s' "$READ_OUT" | sed -n '2p')

[ -n "$SITE_PATH" ] || { echo "ERROR: config.yaml paths.hanflow_home is empty" >&2; exit 1; }
[ -n "$LATEST" ] || { echo "ERROR: state.yaml current_version is empty" >&2; exit 1; }
[ -d "$SITE_PATH" ] || { echo "ERROR: hanflow-home path not found: $SITE_PATH" >&2; exit 1; }

# 校验 LATEST 是合法 semver (避免 state.yaml 写歪导致 MAJOR_LINE=".x" 之类)
[[ "$LATEST" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: LATEST not semver: $LATEST" >&2; exit 1; }

# 大版本线: 1.2.1 → 1.x (仅假设正向 major bump; 不处理反向重开旧线)
MAJOR=$(printf '%s' "$LATEST" | sed -nE 's|^([0-9]+)\..*|\1|p')
MAJOR_LINE="${MAJOR}.x"

echo "[site-sync] site=$SITE_PATH target=v$LATEST line=$MAJOR_LINE"

# 校验 site 干净 (允许 content/<major>.x/ untracked)
PORCELAIN=$(git -C "$SITE_PATH" status --porcelain 2>/dev/null || true)
DIRTY=$(printf '%s\n' "$PORCELAIN" | grep -v -E '^\?\? content/[0-9]+\.x(/|$)' || true)
[ -z "$DIRTY" ] || { echo "ERROR: site repo unexpected changes:" >&2; printf '%s\n' "$DIRTY" >&2; exit 1; }

REMOTES=$(git -C "$SITE_PATH" remote 2>/dev/null || true)

# 幂等: content/<MAJOR_LINE>/ 存在 且 package.json version 已是 LATEST → 跳过
# 注: 路径走环境变量传 python (MSYS 安全, 与文件其余处一致), 不插值进 python -c 字符串
PkgVer=$(SITE_PKG="$SITE_PATH/package.json" python -c "import json,os;print(json.load(open(os.environ['SITE_PKG'],encoding='utf-8')).get('version',''))" 2>/dev/null || echo "")
if [ -d "$SITE_PATH/content/$MAJOR_LINE" ] && [ "$PkgVer" = "$LATEST" ]; then
  echo "[site-sync] already synced to v$LATEST ($MAJOR_LINE) — idempotent skip"
  echo "OK: site-sync no-op"
  exit 0
fi

# major bump: 新线不存在 → 从最近的旧线 cp -r
if [ ! -d "$SITE_PATH/content/$MAJOR_LINE" ]; then
  PREV=$(ls -1 "$SITE_PATH/content/" 2>/dev/null | grep -E '^[0-9]+\.x$' | sort -rV | head -1 || true)
  [ -n "$PREV" ] || { echo "ERROR: no existing content/<major>.x/ to copy from" >&2; exit 1; }
  echo "[site-sync] major bump: cp -r content/$PREV content/$MAJOR_LINE"
  cp -r "$SITE_PATH/content/$PREV" "$SITE_PATH/content/$MAJOR_LINE"
fi

# 改 package.json (LATEST_SEMVER 来源; gen-versions 从此读取)
echo "[site-sync] updating package.json for $MAJOR_LINE"
SITE_PATH_ENV="$SITE_PATH" TARGET_VERSION_ENV="$LATEST" python <<'PYEOF'
import json, os

site = os.environ['SITE_PATH_ENV']
latest = os.environ['TARGET_VERSION_ENV']

p = os.path.join(site, 'package.json')
data = json.load(open(p, encoding='utf-8'))
old = data.get('version')
data['version'] = latest
with open(p, 'w', encoding='utf-8', newline='\n') as fh:
    json.dump(data, fh, indent=2); fh.write('\n')
print(f"  package.json: version {old} -> {latest}")
PYEOF

# versions.ts 不手写: prebuild(gen-versions.mjs) 会从 content/ + package.json 生成。
echo "[site-sync] versions.ts left to prebuild gen-versions.mjs (data-driven)"
# 注: dsl-syntax.mdx frontmatter version 字段无代码消费, 不再写入。

# npm run build (prebuild 先生成 versions.ts; build 内含类型检查)
echo "[site-sync] npm run build"
cd "$SITE_PATH"
if ! npm run build 2>&1 | tail -20; then
  echo "ERROR: npm run build failed in site repo" >&2
  exit 1
fi

# commit + push
cd "$SITE_PATH"
git add -A
if git diff --cached --quiet; then
  echo "[site-sync] no net changes (idempotent)"; echo "OK: site-sync no-op"; exit 0
fi

git commit -m "feat: sync site to v$LATEST ($MAJOR_LINE) [major-line model]

Auto-synced by hanflow-evolve/scripts/site-sync.sh. versions.ts is now
generated by scripts/gen-versions.mjs at prebuild (data-driven). Minor/patch
bumps merge into content/$MAJOR_LINE/ in place; major bumps open a new line." 2>&1 | tail -3

if [ -n "$REMOTES" ]; then
  PUSHED=0
  for REMOTE in $REMOTES; do
    echo "[site-sync] pushing to '$REMOTE'"
    if git push "$REMOTE" main 2>&1; then PUSHED=1; break; fi
  done
  [ "$PUSHED" -eq 0 ] && echo "WARN: all remotes failed; commit local-only" >&2
else
  echo "[site-sync] no remote; local commit only"
fi
echo "OK: site-sync done (v$LATEST / $MAJOR_LINE)"
