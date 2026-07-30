#!/usr/bin/env bash
# doc-sync-judge.sh — S6.1: 判断代码改动是否需要文档更新 (spec §3.2)
#
# 用法: doc-sync-judge.sh <hanflow_repo> <cycle_id> <hanflow_home_repo>
#   <hanflow_home_repo> 用于读 lib/versions.ts 的 LATEST_VERSION 替换 <LATEST>
#
# 输出 (key=value 格式, 供 home-sync.sh 读取):
#   DOC_NEEDED=0|1
#   MAPPINGS=id1,id2 (命中的 mapping id)
#   DOCS_ZH=path1 path2 (命中的 zh 文档路径, 已替换 <LATEST>)
#   DOCS_EN=path1 path2 (命中的 en 文档路径, 已替换 <LATEST>)
set -euo pipefail

HANFLOW_REPO="${1:?Usage: doc-sync-judge.sh <hanflow_repo> <cycle_id> <hanflow_home_repo>}"
CYCLE_ID="${2:?Missing cycle_id}"
HANFLOW_HOME_REPO="${3:?Missing hanflow_home_repo}"

BRANCH="evolve/$CYCLE_ID"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAPPING_FILE="$SCRIPT_DIR/../references/doc-mapping.yaml"

[ -f "$MAPPING_FILE" ] || { echo "ERROR: doc-mapping.yaml not found: $MAPPING_FILE" >&2; exit 1; }

# 读 LATEST_VERSION (从 lib/versions.ts)
LATEST=$(grep "LATEST_VERSION" "$HANFLOW_HOME_REPO/lib/versions.ts" 2>/dev/null | sed -nE "s|.*'([^']+)'.*|\1|p" | head -1)
[ -z "$LATEST" ] && LATEST="1.2.0"  # fallback

# 0. 动态找 base 分支 (不写死 main, 兼容 fork 默认分支可能是 master)
BASE_BRANCH=""
for cand in upstream/main origin/main origin/master main master; do
  if git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/heads/$cand" >/dev/null 2>&1 || \
     git -C "$HANFLOW_REPO" rev-parse --verify --quiet "refs/remotes/$cand" >/dev/null 2>&1; then
    BASE_BRANCH="$cand"; break
  fi
done
[ -z "$BASE_BRANCH" ] && { echo "DOC_NEEDED=0"; echo "MAPPINGS="; echo "DOCS_ZH="; echo "DOCS_EN="; exit 0; }

# 1. 获取 diff 文件列表
DIFF_FILES=$(git -C "$HANFLOW_REPO" diff --name-only "$BASE_BRANCH..$BRANCH" 2>/dev/null || true)
[ -z "$DIFF_FILES" ] && { echo "DOC_NEEDED=0"; echo "MAPPINGS="; echo "DOCS_ZH="; echo "DOCS_EN="; exit 0; }

# 2-7. python 做匹配逻辑 (glob + 最长优先 + ignore 排除 + <LATEST> 替换)
OUTPUT=$(DIFF_FILES="$DIFF_FILES" MAPPING_FILE="$MAPPING_FILE" LATEST="$LATEST" python -c "
import os, fnmatch, yaml

diff_files = [f for f in os.environ['DIFF_FILES'].splitlines() if f.strip()]
data = yaml.safe_load(open(os.environ['MAPPING_FILE'], encoding='utf-8'))
mappings = data.get('mappings') or []
ignore_paths = data.get('ignore_paths') or []
latest = os.environ['LATEST']

# 排除 ignore_paths
def is_ignored(f):
    for ig in ignore_paths:
        # glob ** 匹配任意层级
        pattern = ig.replace('**/', '').replace('/**', '')
        if fnmatch.fnmatch(f, ig) or fnmatch.fnmatch(f.split('/')[-1], pattern):
            return True
        if ig.endswith('/**') and f.startswith(ig[:-3]):
            return True
    return False

filtered = [f for f in diff_files if not is_ignored(f)]

# 对每个文件找最长匹配的 mapping
hit_mappings = {}  # id -> mapping dict
for f in filtered:
    best_mapping = None
    best_len = 0
    for m in mappings:
        for tp in (m.get('trigger_paths') or []):
            # glob 匹配 (** 用 fnmatch 通配)
            glob_pat = tp.replace('**', '*')
            if fnmatch.fnmatch(f, glob_pat) or f.startswith(tp.replace('/**', '/')):
                if len(tp) > best_len:
                    best_len = len(tp)
                    best_mapping = m
    if best_mapping:
        hit_mappings[best_mapping['id']] = best_mapping

# 收集 docs 路径 (替换 <LATEST>)
docs_zh = []
docs_en = []
for m in hit_mappings.values():
    d = m.get('docs') or {}
    for p in (d.get('zh') or []) if isinstance(d.get('zh'), list) else [d.get('zh')] if d.get('zh') else []:
        if p: docs_zh.append(p.replace('<LATEST>', latest))
    for p in (d.get('en') or []) if isinstance(d.get('en'), list) else [d.get('en')] if d.get('en') else []:
        if p: docs_en.append(p.replace('<LATEST>', latest))

needed = 1 if hit_mappings else 0
ids = ','.join(hit_mappings.keys())
print(f'DOC_NEEDED={needed}')
print(f'MAPPINGS={ids}')
print(f'DOCS_ZH={\" \".join(docs_zh)}')
print(f'DOCS_EN={\" \".join(docs_en)}')
" 2>/dev/null || echo "DOC_NEEDED=0
MAPPINGS=
DOCS_ZH=
DOCS_EN=")

echo "$OUTPUT"
