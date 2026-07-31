#!/usr/bin/env bash
# preflight-sync.sh — 启动时强制拉取三仓库 main 最新代码
#
# 用法:
#   preflight-sync.sh loop                              # loop-evolve 模式: 读 config.yaml 三仓库
#   preflight-sync.sh contrib <repo_path> [repo_path...] # contribute-pr 模式: 传入要同步的仓库
#
# 行为:
#   loop 模式 —— 智能 WIP 保护:
#     仅当仓库当前在 main 分支 且 工作区干净 时, fetch + reset --hard <upstream>/main。
#     否则(在 evolve/<cycle> 分支 或 有未提交改动) 跳过该仓库并警告, 绝不毁掉进行中的工作。
#   contrib 模式 —— 上游 → 本地 main → 推 fork:
#     fetch upstream main; 本地 main ff-only 合并(分叉则 merge, 保留 fork 独有提交);
#     若配置了 fork remote(contribute-fork / contribute-fork-home), 把同步后的 main 推到 fork。
#
# upstream remote 识别(复用 submit.sh 已验证逻辑, 不写死):
#   按候选顺序 upstream | github | origin, 取 URL 含 xpc1024/<repo_short> 的第一个。
#
# 失败不阻断: 网络问题/remote 找不到 → 警告并继续(离线可用), exit 0。
set -uo pipefail

MODE="${1:?Usage: preflight-sync.sh loop | contrib <repo_path>...}"
shift || true

# ── 仓库短名 (用于 upstream URL 匹配) ──
_repo_short() {
  case "$(basename "$1")" in
    hanflow-evolve) echo "hanflow-evolve" ;;
    hanflow-home)   echo "hanflow-home" ;;
    hanflow|hanflow) echo "hanflow" ;;
    *) basename "$1" ;;
  esac
}

# ── 找 upstream remote: URL 含 xpc1024/<repo_short> 的第一个候选 ──
# 输出 remote 名到 stdout; 找不到输出空串。
_find_upstream_remote() {
  local repo_path="$1" repo_short="$2" cand url
  for cand in upstream github origin; do
    if url=$(git -C "$repo_path" remote get-url "$cand" 2>/dev/null); then
      if printf '%s' "$url" | grep -qE "xpc1024/${repo_short}(\.git)?$|github\.com[/:]xpc1024/${repo_short}"; then
        printf '%s' "$cand"; return 0
      fi
    fi
  done
  return 0
}

# ── 找 fork remote (contrib 模式推 fork 用) ──
_find_fork_remote() {
  local repo_path="$1" cand
  for cand in contribute-fork contribute-fork-home; do
    if git -C "$repo_path" remote get-url "$cand" >/dev/null 2>&1; then
      printf '%s' "$cand"; return 0
    fi
  done
  return 0
}

# ── loop 模式: 智能 WIP 保护 ──
_sync_loop_repo() {
  local repo_path="$1"
  [ -d "$repo_path/.git" ] || { echo "[preflight] 跳过 $(basename "$repo_path"): 不是 git 仓库 ($repo_path)"; return 0; }
  local name short upstream branch dirty
  name="$(basename "$repo_path")"
  short="$(_repo_short "$repo_path")"
  upstream="$(_find_upstream_remote "$repo_path" "$short")"
  [ -n "$upstream" ] || { echo "[preflight] 跳过 $name: 未找到 xpc1024/${short} 的 upstream remote (候选 upstream/github/origin 均不匹配)"; return 0; }

  branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  # 仅看 tracked 改动 (排除 ?? untracked 文件: reset --hard 不动 untracked, 故 .idea/ 等无碍)
  dirty="$(git -C "$repo_path" status --porcelain 2>/dev/null | grep -v '^??' || true)"

  # WIP 保护: 非 main 分支 或 有 tracked 未提交改动 → 跳过
  if [ "$branch" != "main" ]; then
    echo "[preflight] 跳过 $name: 当前在分支 '$branch' (非 main), 避免毁掉进行中的周期工作"
    return 0
  fi
  if [ -n "$dirty" ]; then
    echo "[preflight] 跳过 $name: 工作区有未提交的 tracked 改动, 避免丢失 (先 commit/stash 再启动)"
    return 0
  fi

  echo "[preflight] $name: fetch $upstream/main → reset --hard"
  if ! git -C "$repo_path" fetch "$upstream" main 2>&1 | sed 's/^/    /'; then
    echo "[preflight] WARN: $name fetch $upstream/main 失败, 跳过 (网络?)" >&2
    return 0
  fi
  if ! git -C "$repo_path" reset --hard "$upstream/main" 2>&1 | sed 's/^/    /'; then
    echo "[preflight] WARN: $name reset --hard 失败" >&2
    return 0
  fi
}

# ── contrib 模式: 上游 → 本地 main → 推 fork ──
_sync_contrib_repo() {
  local repo_path="$1"
  [ -d "$repo_path/.git" ] || { echo "[preflight] 跳过 $(basename "$repo_path"): 不是 git 仓库 ($repo_path)"; return 0; }
  local name short upstream fork orig_branch
  name="$(basename "$repo_path")"
  short="$(_repo_short "$repo_path")"
  upstream="$(_find_upstream_remote "$repo_path" "$short")"
  [ -n "$upstream" ] || { echo "[preflight] 跳过 $name: 未找到 xpc1024/${short} 的 upstream remote"; return 0; }

  orig_branch="$(git -C "$repo_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"

  # WIP 保护: 当前分支有 tracked 未提交改动 → 跳过 (checkout main 会把改动带过去/或被拒)
  # 与 loop 模式对齐, 绝不毁掉贡献者 feature 分支的进行中工作。
  local dirty
  dirty="$(git -C "$repo_path" status --porcelain 2>/dev/null | grep -v '^??' || true)"
  if [ -n "$dirty" ]; then
    echo "[preflight] 跳过 $name: 当前分支 '$orig_branch' 有未提交的 tracked 改动, 避免丢失 (先 commit/stash 再启动)"
    return 0
  fi

  echo "[preflight] $name: fetch $upstream/main"
  if ! git -C "$repo_path" fetch "$upstream" main 2>&1 | sed 's/^/    /'; then
    echo "[preflight] WARN: $name fetch $upstream/main 失败, 跳过 (网络?)" >&2
    return 0
  fi

  # 切到 main 同步 (切回 orig_branch 在最后)
  # 本地 main 不存在则基于 upstream/main 创建
  if ! git -C "$repo_path" rev-parse --verify --quiet refs/heads/main >/dev/null; then
    git -C "$repo_path" branch main "$upstream/main" 2>/dev/null || true
  fi
  if ! git -C "$repo_path" checkout main 2>&1 | sed 's/^/    /'; then
    echo "[preflight] WARN: $name 无法切到 main, 跳过 main 同步" >&2
    return 0
  fi

  # ff-only 优先; 分叉(本地 main 有 fork 独有提交)则 merge 保留
  if git -C "$repo_path" merge --ff-only "$upstream/main" 2>&1 | sed 's/^/    /'; then
    : # ff 成功
  else
    echo "[preflight] $name: 本地 main 与上游分叉, 执行 merge (保留 fork 独有提交)..."
    if ! git -C "$repo_path" merge "$upstream/main" --no-edit 2>&1 | sed 's/^/    /'; then
      echo "[preflight] WARN: $name merge upstream/main 冲突, 中止 merge, 留给人工处理" >&2
      git -C "$repo_path" merge --abort 2>/dev/null || true
      # 切回原分支再返回
      [ -n "$orig_branch" ] && git -C "$repo_path" checkout "$orig_branch" 2>/dev/null || true
      return 0
    fi
  fi

  # 推到 fork (若有 fork remote), 保证 fork 不滞后
  fork="$(_find_fork_remote "$repo_path")"
  if [ -n "$fork" ]; then
    echo "[preflight] $name: push main → $fork (同步 fork)"
    if ! git -C "$repo_path" push "$fork" main 2>&1 | sed 's/^/    /'; then
      echo "[preflight] WARN: $name 推 fork ($fork) 失败, 跳过 (权限? 网络?)" >&2
    fi
  else
    echo "[preflight] $name: 未配置 fork remote (contribute-fork*), 跳过推 fork"
  fi

  # 切回原分支 (若有)
  if [ -n "$orig_branch" ] && [ "$orig_branch" != "main" ]; then
    git -C "$repo_path" checkout "$orig_branch" 2>/dev/null || true
  fi
}

# ── 路由 ──
case "$MODE" in
  loop)
    # 读 config.yaml paths: 三仓库 (可用 PREFLIGHT_CONFIG 覆盖, 默认 $EVOLVE_HOME/config.yaml)
    EVOLVE_HOME="$(cd "$(dirname "$0")/.." && pwd)"
    CONFIG="${PREFLIGHT_CONFIG:-$EVOLVE_HOME/config.yaml}"
    [ -f "$CONFIG" ] || { echo "[preflight] ERROR: config.yaml not found: $CONFIG" >&2; exit 0; }
    REPOS=$(CONFIG_FILE="$CONFIG" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
p = c.get('paths') or {}
for k in ('hanflow', 'hanflow_home', 'evolve_home'):
    v = p.get(k)
    if v: print(v)
" 2>/dev/null | tr -d '\r' || true)
    [ -n "$REPOS" ] || { echo "[preflight] WARN: config.yaml paths 为空, 无可同步仓库" >&2; exit 0; }
    echo "=== preflight-sync (loop 模式: 智能 WIP 保护) ==="
    while IFS= read -r r; do
      [ -n "$r" ] && _sync_loop_repo "$r"
    done <<<"$REPOS"
    ;;
  contrib)
    [ "$#" -ge 1 ] || { echo "[preflight] ERROR: contrib 模式需至少一个仓库路径" >&2; exit 0; }
    echo "=== preflight-sync (contrib 模式: 上游 → 本地 main → 推 fork) ==="
    for r in "$@"; do
      _sync_contrib_repo "$r"
    done
    ;;
  *)
    echo "ERROR: 未知模式 '$MODE' (应为 loop | contrib)" >&2
    exit 0
    ;;
esac

echo "[preflight] 完成"
exit 0
