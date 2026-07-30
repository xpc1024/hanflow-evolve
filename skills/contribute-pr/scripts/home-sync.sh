#!/usr/bin/env bash
# home-sync.sh — submit 阶段: hanflow-home 单一 PR (S5名录 + S6文档 + 版本同步)
#
# 用法: home-sync.sh <hanflow_repo> <hanflow_home_repo> [new_version]
#   new_version: S0.5 算的新版本号 (可选, 若提供则更新版本切换器)
#
# 替代 honor-submit.sh (职责扩展: 名录 → 名录+文档+版本)
# spec: 2026-07-29-doc-sync-s6-design.md
set -euo pipefail

HANFLOW_REPO="${1:?Usage: home-sync.sh <hanflow_repo> <hanflow_home_repo> [new_version]}"
HANFLOW_HOME_REPO="${2:?Usage: home-sync.sh <hanflow_repo> <hanflow_home_repo> [new_version]}"
NEW_VERSION="${3:-}"  # S0.5 算的, 可空(docs 子命令不传)

STATE="$HANFLOW_REPO/.contribute/state.yaml"
CONTRIB_JSON="$HANFLOW_HOME_REPO/data/contributors.json"
FORK_REMOTE="contribute-fork-home"
UPSTREAM="xpc1024/hanflow-home"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 前置: 目录存在性校验 ──
[ -d "$HANFLOW_REPO" ] || { echo "ERROR: hanflow_repo not found: $HANFLOW_REPO" >&2; exit 1; }
[ -d "$HANFLOW_HOME_REPO" ] || { echo "ERROR: hanflow_home_repo not found: $HANFLOW_HOME_REPO" >&2; exit 1; }
[ -f "$STATE" ] || { echo "ERROR: state.yaml not found: $STATE" >&2; exit 1; }

# ── S0. 校验 fork remote ──
if ! git -C "$HANFLOW_HOME_REPO" remote get-url "$FORK_REMOTE" >/dev/null 2>&1; then
  echo "ERROR: remote '$FORK_REMOTE' 未配置在 $HANFLOW_HOME_REPO" >&2
  echo "       请先 fork xpc1024/hanflow-home, 然后:" >&2
  echo "       git -C $HANFLOW_HOME_REPO remote add $FORK_REMOTE <你的 fork URL>" >&2
  exit 1
fi

# ── 读 cycle_id + 贡献信息 (从 honor-submit.sh 继承的逻辑) ──
READ_OUT=$(STATE_FILE="$STATE" HANFLOW_DIR="$HANFLOW_REPO" python -c "
import os, yaml, re
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
hdir = os.environ['HANFLOW_DIR']
cid = s.get('cycle_id') or ''
submit = s.get('submit') or {}
pr_code = submit.get('pr_code_url') or ''
pr_docs = submit.get('pr_docs_url') or ''
pr_url = pr_code or pr_docs or ''
version = 'unknown'
init_path = os.path.join(hdir, 'hanflow', '__init__.py')
try:
    txt = open(init_path, encoding='utf-8').read()
    m = re.search(r'__version__\s*=\s*[\"\\']([^\"\\']+)', txt)
    if m: version = m.group(1)
except: pass
print(cid); print(pr_url); print(version)
" 2>/dev/null || echo "")
CYCLE_ID=$(printf '%s' "$READ_OUT" | sed -n '1p')
PR_URL=$(printf '%s' "$READ_OUT" | sed -n '2p')
VERSION=$(printf '%s' "$READ_OUT" | sed -n '3p')

[ -z "$CYCLE_ID" ] && { echo "ERROR: cycle_id empty" >&2; exit 1; }
[ -z "$PR_URL" ] && { echo "ERROR: 无 PR URL, S5 需要 S2/docs 已发 PR" >&2; exit 1; }

BRANCH="evolve/$CYCLE_ID"
FIRST_MSG=$(git -C "$HANFLOW_REPO" log -1 --format='%s' "$BRANCH" 2>/dev/null || echo "$CYCLE_ID")
TYPE=$(printf '%s' "$FIRST_MSG" | sed -nE 's/^([a-z]+)(\(.+\))?!?:.*/\1/p')
[ -z "$TYPE" ] && TYPE="other"
SUMMARY=$(printf '%s' "$FIRST_MSG" | sed -nE 's/^[a-z]+(\(.+\))?!: *//p')
[ -z "$SUMMARY" ] && SUMMARY="$CYCLE_ID"

USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "")
if [ -z "$USERNAME" ]; then
  FORK_URL=$(git -C "$HANFLOW_REPO" remote get-url contribute-fork 2>/dev/null || echo "")
  USERNAME=$(printf '%s' "$FORK_URL" | sed -nE 's|.*github\.com[:/]([^/]+)/hanflow.*|\1|p')
  [ -z "$USERNAME" ] && USERNAME="unknown"
fi
AVATAR="https://github.com/${USERNAME}.png"
USER_URL="https://github.com/${USERNAME}"
TODAY=$(date +%Y-%m-%d)

echo "=== home-sync: @$USERNAME / $TYPE: $SUMMARY / v$VERSION ==="

# ── S6.1 判断: 调 doc-sync-judge.sh ──
JUDGE_OUT=$(bash "$SCRIPT_DIR/doc-sync-judge.sh" "$HANFLOW_REPO" "$CYCLE_ID" "$HANFLOW_HOME_REPO" 2>/dev/null || echo "DOC_NEEDED=0")
DOC_NEEDED=$(echo "$JUDGE_OUT" | grep "^DOC_NEEDED=" | cut -d= -f2 || echo "0")
DOCS_ZH=$(echo "$JUDGE_OUT" | grep "^DOCS_ZH=" | cut -d= -f2 || echo "")
DOCS_EN=$(echo "$JUDGE_OUT" | grep "^DOCS_EN=" | cut -d= -f2 || echo "")
MAPPINGS=$(echo "$JUDGE_OUT" | grep "^MAPPINGS=" | cut -d= -f2 || echo "")

echo "  S6 判断: DOC_NEEDED=$DOC_NEEDED MAPPINGS=$MAPPINGS"

# ── 切分支 (基于 fork 最新 main) ──
git -C "$HANFLOW_HOME_REPO" fetch "$FORK_REMOTE" main 2>/dev/null || true
HOME_BRANCH="home/$CYCLE_ID"
git -C "$HANFLOW_HOME_REPO" checkout -B "$HOME_BRANCH" "$FORK_REMOTE/main" 2>&1 | tail -1

# ── S5 名录登记 (无条件, 幂等) ──
EXISTS=$(python -c "
import json, sys
try:
    d = json.load(open('$CONTRIB_JSON', encoding='utf-8'))
    sys.exit(0 if '$CYCLE_ID' in [c.get('id') for c in (d.get('contributions') or [])] else 1)
except: sys.exit(1)
" 2>/dev/null && echo yes || echo no)

if [ "$EXISTS" = "no" ]; then
  NEW_RECORD=$(cat <<EOF
{
  "id": "$CYCLE_ID",
  "github_user": "$USERNAME",
  "github_user_url": "$USER_URL",
  "avatar_url": "$AVATAR",
  "date": "$TODAY",
  "version": "$VERSION",
  "type": "$TYPE",
  "summary": "$SUMMARY",
  "pr_url": "$PR_URL",
  "pr_status": "open",
  "merged_at": null
}
EOF
)
  RECORD="$NEW_RECORD" JSON_FILE="$CONTRIB_JSON" python -c "
import json, os
rec = json.loads(os.environ['RECORD'])
data = json.load(open(os.environ['JSON_FILE'], encoding='utf-8'))
contribs = data.get('contributions') or []
contribs.insert(0, rec)
data['contributions'] = contribs
with open(os.environ['JSON_FILE'], 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write('\n')
"
  echo "  S5: contributors.json 已追加"
else
  echo "  S5: contributors.json 已有 $CYCLE_ID (幂等跳过)"
fi

# ── 版本同步 (大版本线模型, 若有 NEW_VERSION) ──
# versions.ts 由 gen-versions.mjs 在 build 时生成, 这里不手写。
# minor/patch: 只更新 package.json (LATEST_SEMVER 来源); 不建文件夹。
# major: cp -r content/<旧major>.x/ → content/<新major>.x/。
if [ -n "$NEW_VERSION" ]; then
  NEW_MAJOR=$(printf '%s' "$NEW_VERSION" | sed -nE 's|^([0-9]+)\..*|\1|p')
  NEW_LINE="${NEW_MAJOR}.x"
  # 幂等: package.json version 已是 NEW_VERSION 则不改写 (避免重跑产生空 diff)
  CUR_VER=$(PKG="$HANFLOW_HOME_REPO/package.json" python -c "import json,os;print(json.load(open(os.environ['PKG'],encoding='utf-8')).get('version',''))" 2>/dev/null || echo "")
  if [ "$CUR_VER" != "$NEW_VERSION" ]; then
    # package.json version = 精确 semver (gen-versions 从此读 LATEST_SEMVER)
    # 单 handle + newline='\n' 保证 Windows 下统一 LF (避免 two-open 的 CRLF/LF 混杂)
    PKG="$HANFLOW_HOME_REPO/package.json" VER="$NEW_VERSION" python -c "
import json,os
p=os.environ['PKG']
d=json.load(open(p,encoding='utf-8')); d['version']=os.environ['VER']
with open(p,'w',encoding='utf-8',newline='\n') as fh:
    json.dump(d,fh,indent=2,ensure_ascii=False); fh.write('\n')
"
    echo "  版本: package.json -> v$NEW_VERSION"
  else
    echo "  版本: package.json 已是 v$NEW_VERSION (幂等跳过)"
  fi
  # major bump: 新线不存在才 cp -r
  if [ ! -d "$HANFLOW_HOME_REPO/content/$NEW_LINE" ]; then
    PREV=$(ls -1 "$HANFLOW_HOME_REPO/content/" 2>/dev/null | grep -E '^[0-9]+\.x$' | sort -rV | head -1 || true)
    if [ -n "$PREV" ]; then
      cp -r "$HANFLOW_HOME_REPO/content/$PREV" "$HANFLOW_HOME_REPO/content/$NEW_LINE"
      echo "  版本: major bump → content/$NEW_LINE 已创建 (从 $PREV 复制)"
    else
      echo "  WARN: 无旧线可复制, content/$NEW_LINE 需手动创建" >&2
    fi
  else
    echo "  版本: minor/patch → 原地合并到 content/$NEW_LINE (不建文件夹)"
  fi
  echo "  版本: versions.ts 由 prebuild gen-versions.mjs 自动更新 (数据驱动)"
fi

# ── S6.2-S6.3 文档生成 (若 DOC_NEEDED=1, SKILL.md 指导 AI 对话式完成) ──
# 注: 这一步由 SKILL.md 接管 (AI 读代码 diff + 现有文档 → 改 MDX → 贡献者 review)
# home-sync.sh 只负责判断 + 提示, 不做 AI 生成
if [ "$DOC_NEEDED" = "1" ]; then
  echo ""
  echo "  ⚠️ S6: 检测到 user-facing 改动 ($MAPPINGS), 需要更新文档:"
  echo "    ZH: $DOCS_ZH"
  echo "    EN: $DOCS_EN"
  echo "    (SKILL.md 将指导 AI 生成文档草稿, 贡献者 git diff review 后继续)"
  echo ""
  echo "  AI 生成文档后, 贡献者 review 满意, 再运行以下命令发 PR:"
else
  echo "  S6: 非 user-facing, 无文档更新"
fi

# ── 提示发 PR (不自动发, 因为 S6.2 AI 生成是异步对话) ──
echo ""
echo "=== home-sync 准备就绪 ==="
echo "  分支: $HOME_BRANCH (在 $HANFLOW_HOME_REPO)"
echo "  名录: contributors.json 已更新"
if [ -n "$NEW_VERSION" ]; then
  echo "  版本: package.json=v$NEW_VERSION content/$NEW_LINE (versions.ts 由 build 生成)"
fi
[ "$DOC_NEEDED" = "1" ] && echo "  文档: 待 AI 生成 + review 后 commit"
echo ""
echo "  下一步 (SKILL.md 指导):"
[ "$DOC_NEEDED" = "1" ] && echo "    1. AI 生成文档草稿 (改 $DOCS_ZH $DOCS_EN)"
[ "$DOC_NEEDED" = "1" ] && echo "    2. 贡献者 git diff review"
echo "    $([ "$DOC_NEEDED" = "1" ] && echo 3 || echo 1). cd $HANFLOW_HOME_REPO && git add -A && git commit"
echo "    $([ "$DOC_NEEDED" = "1" ] && echo 4 || echo 2). git push $FORK_REMOTE $HOME_BRANCH"
echo "    $([ "$DOC_NEEDED" = "1" ] && echo 5 || echo 3). gh pr create --repo $UPSTREAM --head $HOME_BRANCH --base main"

# PR 标题/body 根据 DOC_NEEDED + NEW_VERSION 区分
if [ "$DOC_NEEDED" = "1" ] && [ -n "$NEW_VERSION" ]; then
  TITLE="honor+docs+version(contributors): @$USERNAME + sync docs + v$NEW_VERSION"
elif [ "$DOC_NEEDED" = "1" ]; then
  TITLE="honor+docs(contributors): @$USERNAME + sync docs"
elif [ -n "$NEW_VERSION" ]; then
  TITLE="honor+version(contributors): @$USERNAME + v$NEW_VERSION"
else
  TITLE="honor(contributors): register @$USERNAME for $TYPE: $SUMMARY"
fi
echo ""
echo "  PR 标题: $TITLE"
