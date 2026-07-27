#!/usr/bin/env bash
# install.sh — contribute-pr 一键安装脚本 (v2: 全自动 clone + 装 skill)
#
# 核心理念: 为社区开发者省事。贡献 PR 操作越简单越好。
#
# 一条命令完成:
#   1. 检测环境 (git / gh / AI 工具)
#   2. clone hanflow-evolve (skill 源) → 装 contribute-pr + loop-evolve 到 ~/.zcode/skills/
#   3. fork + clone hanflow (贡献者要改的代码, 自动 fork 或读用户名)
#   4. clone hanflow-site (P2 文档 PR 用)
#   5. 配置 upstream remote (发 PR 到 xpc1024/hanflow 需要)
#   6. 打印下一步: cd hanflow, 跑 /contribute-pr
#
# 用法:
#   bash install.sh                          # 全自动 (gh 登录则自动 fork, 否则问用户名)
#   bash install.sh <github用户名>           # 指定用户名, clone github.com/<用户名>/hanflow
#   bash install.sh --target <目录>          # 指定 clone 根目录 (默认 ~/hanflow-dev/)
#   bash install.sh --check                  # 只做环境 + 仓库状态预检, 不安装
#   bash install.sh --update-skills          # 只更新 skill (hanflow-evolve git pull + 重装)
#   bash install.sh --uninstall              # 移除已安装的 skill
#   bash install.sh -h|--help
#
# 仓库布局 (默认 ~/hanflow-dev/):
#   ~/hanflow-dev/
#   ├── hanflow/         (贡献者工作目录, 长期, 改代码在这里)
#   ├── hanflow-evolve/  (skill 源, 留着可 git pull 更新 skill)
#   └── hanflow-site/    (P2 文档 PR 用)
#
# 一键安装 (官网文案给):
#   curl -fsSL https://raw.githubusercontent.com/xpc1024/hanflow-evolve/main/install.sh | bash
set -euo pipefail

# ── 颜色输出 ──
if [ -t 1 ]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi
info()  { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; }

# ── 默认配置 ──
HANFLOW_DEV_DIR="${HANFLOW_DEV_DIR:-$HOME/hanflow-dev}"
GITHUB_USER=""
UPSTREAM_HANFLOW="xpc1024/hanflow"
UPSTREAM_HANFLOW_SITE="xpc1024/hanflow-site"
UPSTREAM_HANFLOW_EVOLVE="xpc1024/hanflow-evolve"

# skill 安装目录 (.zcode 优先, 回退 .agents)
detect_skills_dir() {
  if [ -d "$HOME/.zcode" ] || [ -d "$HOME/.zcode/skills" ]; then
    echo "$HOME/.zcode/skills"
  elif [ -d "$HOME/.agents" ] || [ -d "$HOME/.agents/skills" ]; then
    echo "$HOME/.agents/skills"
  else
    echo "$HOME/.zcode/skills"  # 默认, 会创建
  fi
}
SKILLS_DIR="$(detect_skills_dir)"

# 平台检测
detect_platform() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    Darwin)               echo "macos" ;;
    Linux)                echo "linux" ;;
    *)                    echo "unknown" ;;
  esac
}
PLATFORM="$(detect_platform)"

# ── 解析参数 ──
ACTION="install"
while [ $# -gt 0 ]; do
  case "$1" in
    --target)        HANFLOW_DEV_DIR="$2"; shift 2 ;;
    --check)         ACTION="check" ; shift ;;
    --update-skills) ACTION="update_skills"; shift ;;
    --uninstall)     ACTION="uninstall"; shift ;;
    -h|--help)       ACTION="help"; shift ;;
    -*)              fail "未知选项: $1"; exit 1 ;;
    *)               GITHUB_USER="$1"; shift ;;  # 位置参数 = github 用户名
  esac
done

# ── git clone 辅助 (已存在则跳过, 不覆盖贡献者工作) ──
# 用法: clone_repo <url> <目标目录> <显示名>
clone_repo() {
  local url="$1" dest="$2" name="$3"
  if [ -d "$dest/.git" ]; then
    ok "$name 已存在: $dest (跳过 clone, 如需更新手动 git pull)"
    return 0
  fi
  if [ -d "$dest" ]; then
    warn "$dest 存在但不是 git 仓库, 跳过 clone (避免覆盖)"
    return 1
  fi
  info "clone $name → $dest"
  if git clone "$url" "$dest"; then
    ok "$name clone 完成"
    return 0
  else
    fail "$name clone 失败 (URL: $url)"
    return 1
  fi
}

# ── 装 skill (cp -r Windows / symlink Unix) ──
# 用法: install_skill <源目录> <目标目录> <skill名>
install_skill() {
  local src="$1" dest="$2" name="$3"
  [ -e "$dest" ] || [ -L "$dest" ] && rm -rf "$dest"
  case "$PLATFORM" in
    macos|linux) ln -s "$src" "$dest"; ok "$name: symlink → $src" ;;
    *)           cp -r "$src" "$dest"; ok "$name: 复制到 $dest (Windows, 更新重跑 --update-skills)" ;;
  esac
}

# ── 环境预检 ──
check_env() {
  info "环境预检..."
  info "  平台: $PLATFORM"
  info "  skill 目录: $SKILLS_DIR"
  info "  仓库根目录: $HANFLOW_DEV_DIR"
  local issues=0

  # git
  if command -v git >/dev/null 2>&1; then ok "git: $(git --version | head -1)"
  else fail "未检测到 git (必需)"; issues=$((issues+1)); fi

  # AI 工具
  local has_tool=0
  for d in "$HOME/.zcode" "$HOME/.claude" "$HOME/.codex"; do
    [ -d "$d" ] && has_tool=1
  done
  if [ "$has_tool" -eq 0 ]; then
    warn "未检测到 AI 工具 (~/.zcode / ~/.claude / ~/.codex)"
    issues=$((issues+1))
  fi

  # gh (可选但强烈推荐, 自动 fork 需要)
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      GH_USER=$(gh api user --jq '.login' 2>/dev/null || echo "")
      [ -n "$GH_USER" ] && ok "gh 已登录: @$GH_USER" || ok "gh 已安装"
    else
      warn "gh 已安装但未登录 (自动 fork 不可用, 将询问用户名)"
      issues=$((issues+1))
    fi
  else
    warn "未检测到 gh (自动 fork 不可用, 将询问用户名)"
    issues=$((issues+1))
  fi

  return $issues
}

# ── 获取贡献者 GitHub 用户名 (自动优先, 兜底交互) ──
resolve_github_user() {
  # 优先级: 命令行参数 > gh 登录用户 > 交互询问
  if [ -n "$GITHUB_USER" ]; then
    info "使用命令行指定的用户名: $GITHUB_USER"
    return 0
  fi
  if [ -n "${GH_USER:-}" ]; then
    GITHUB_USER="$GH_USER"
    info "使用 gh 登录用户名: $GITHUB_USER"
    return 0
  fi
  # 交互询问
  echo ""
  printf "${BLUE}[?]${NC} 你的 GitHub 用户名 (用于 clone 你的 hanflow fork): "
  read -r GITHUB_USER
  if [ -z "$GITHUB_USER" ]; then
    fail "未提供用户名, 无法 clone hanflow"
    return 1
  fi
  # 去掉可能的 @ 前缀
  GITHUB_USER="${GITHUB_USER#@}"
  info "用户名: $GITHUB_USER"
  return 0
}

# ── fork + clone hanflow (核心: 自动优先) ──
setup_hanflow() {
  local dest="$HANFLOW_DEV_DIR/hanflow"
  # 已存在则跳过
  if [ -d "$dest/.git" ]; then
    ok "hanflow 已存在: $dest (跳过, 如需重建先删该目录)"
    ensure_upstream "$dest" "$UPSTREAM_HANFLOW"
    return 0
  fi

  # 尝试 gh repo fork (自动, 最省事)
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    info "尝试 gh repo fork $UPSTREAM_HANFLOW (自动)..."
    # gh repo fork 默认会 clone 到当前目录, 用 --clone + 指定目录
    if gh repo fork "$UPSTREAM_HANFLOW" --clone --remote-name upstream 2>&1 | sed 's/^/    /'; then
      # gh fork 默认 clone 到 <repo名>, 移到目标位置
      if [ -d "./hanflow" ] && [ "$(pwd)" != "$HANFLOW_DEV_DIR" ]; then
        mv "./hanflow" "$dest" 2>/dev/null || true
      fi
      if [ -d "$dest/.git" ]; then
        ok "hanflow fork + clone 完成 (自动): $dest"
        ensure_upstream "$dest" "$UPSTREAM_HANFLOW"
        GITHUB_USER="${GH_USER:-}"
        return 0
      fi
    fi
    warn "gh repo fork 未成功 (可能已 fork 过), 回退到 clone 已有 fork"
  fi

  # 回退: 读用户名, clone github.com/<user>/hanflow
  resolve_github_user || return 1

  local fork_url="https://github.com/$GITHUB_USER/hanflow"
  if ! clone_repo "$fork_url" "$dest" "hanflow (你的 fork)"; then
    # clone 失败, 可能没 fork
    fail "clone $fork_url 失败"
    echo ""
    echo "  可能你还没 fork hanflow。请先去 GitHub fork:" >&2
    echo "    https://github.com/xpc1024/hanflow" >&2
    echo "  fork 后重跑本脚本 (或用 gh auth login 后自动 fork)。" >&2
    return 1
  fi
  ensure_upstream "$dest" "$UPSTREAM_HANFLOW"
}

# ── 配置 upstream remote (发 PR 到上游需要) ──
# 用法: ensure_upstream <repo目录> <上游 owner/repo>
ensure_upstream() {
  local repo="$1" upstream="$2"
  local upstream_url="https://github.com/$upstream"
  if git -C "$repo" remote get-url upstream >/dev/null 2>&1; then
    ok "upstream remote 已配置: $upstream"
    return 0
  fi
  info "配置 upstream remote → $upstream"
  if git -C "$repo" remote add upstream "$upstream_url" 2>/dev/null; then
    ok "upstream remote 已添加"
  else
    warn "添加 upstream remote 失败 (可能已存在), 继续"
  fi
}

# ── 主安装流程 ──
do_install() {
  info "===== contribute-pr 一键安装 ====="
  info "仓库根: $HANFLOW_DEV_DIR"
  echo ""

  check_env || true
  echo ""

  mkdir -p "$HANFLOW_DEV_DIR"

  # 1. clone hanflow-evolve (skill 源)
  info "[1/3] hanflow-evolve (skill 源)"
  local evolve_dest="$HANFLOW_DEV_DIR/hanflow-evolve"
  clone_repo "https://github.com/$UPSTREAM_HANFLOW_EVOLVE" "$evolve_dest" "hanflow-evolve" || {
    fail "hanflow-evolve clone 失败, skill 安装无法继续"
    exit 1
  }

  # 2. 装 skill (从 clone 下来的 evolve 仓库)
  info "[2/3] 安装 skill (contribute-pr + loop-evolve)"
  for skill in contribute-pr loop-evolve; do
    local src="$evolve_dest/skills/$skill"
    if [ ! -d "$src" ]; then
      fail "skill 源不存在: $src"
      exit 1
    fi
    install_skill "$src" "$SKILLS_DIR/$skill" "$skill"
  done

  # 3. fork + clone hanflow
  info "[3/3] hanflow (你的 fork, 工作目录)"
  setup_hanflow || {
    warn "hanflow clone 未完成, 你可以手动 fork + clone 后再跑 /contribute-pr"
  }

  # 4. clone hanflow-site (P2, 失败不阻断)
  info "[可选] hanflow-site (P2 文档 PR 用)"
  clone_repo "https://github.com/$UPSTREAM_HANFLOW_SITE" "$HANFLOW_DEV_DIR/hanflow-site" "hanflow-site" || \
    warn "hanflow-site clone 失败 (P2 才需要, 可忽略)"

  echo ""
  ok "===== 安装完成 ====="
  echo ""
  info "下一步:"
  echo "  1. cd $HANFLOW_DEV_DIR/hanflow"
  echo "  2. 在你的 AI 工具里运行: /contribute-pr"
  echo "  3. 首次会打印凭证安全声明, 提供 fine-grained PAT"
  echo ""
  if [ "$PLATFORM" = "windows" ]; then
    warn "Windows 静态副本: skill 源更新后重跑同步:"
    echo "    bash install.sh --update-skills"
  fi
  echo ""
  info "hanflow 工作目录: $HANFLOW_DEV_DIR/hanflow"
  [ -n "$GITHUB_USER" ] && info "你的 fork: https://github.com/$GITHUB_USER/hanflow"
}

# ── 只更新 skill ──
do_update_skills() {
  info "更新 skill..."
  local evolve_dest="$HANFLOW_DEV_DIR/hanflow-evolve"
  if [ ! -d "$evolve_dest/.git" ]; then
    fail "hanflow-evolve 未 clone 到 $evolve_dest, 无法更新"
    echo "  请先完整跑一次 bash install.sh" >&2
    exit 1
  fi
  info "git pull hanflow-evolve..."
  git -C "$evolve_dest" pull --ff-only 2>&1 | sed 's/^/    /' || warn "pull 失败, 用本地版本"
  for skill in contribute-pr loop-evolve; do
    install_skill "$evolve_dest/skills/$skill" "$SKILLS_DIR/$skill" "$skill"
  done
  ok "skill 更新完成"
}

# ── 卸载 ──
do_uninstall() {
  info "移除 skill (不删 hanflow 工作目录)..."
  for name in contribute-pr loop-evolve; do
    dest="$SKILLS_DIR/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      rm -rf "$dest"; ok "已移除 $dest"
    else
      warn "$dest 不存在, 跳过"
    fi
  done
  echo ""
  info "skill 已移除。hanflow 工作目录 $HANFLOW_DEV_DIR/hanflow 保留 (你写的代码在里面)。"
}

# ── 主入口 ──
case "$ACTION" in
  install)       do_install ;;
  check)         check_env; exit $? ;;
  update_skills) do_update_skills ;;
  uninstall)     do_uninstall ;;
  help)
    cat <<EOF
contribute-pr 一键安装脚本
用法: bash install.sh [选项] [github用户名]

选项:
  (无)              完整安装: clone 三仓库 + 装 skill + 配 upstream (默认)
  <github用户名>    指定贡献者用户名 (clone github.com/<用户名>/hanflow)
  --target <目录>   指定仓库根目录 (默认 ~/hanflow-dev/)
  --check           只做环境 + 仓库状态预检
  --update-skills   只更新 skill (hanflow-evolve git pull + 重装, Windows 用)
  --uninstall       移除已安装 skill (保留 hanflow 工作目录)
  -h, --help        显示本帮助

环境变量:
  HANFLOW_DEV_DIR   仓库根目录 (同 --target)

一键安装:
  curl -fsSL https://raw.githubusercontent.com/xpc1024/hanflow-evolve/main/install.sh | bash

布局:
  ~/hanflow-dev/
  ├── hanflow/         (工作目录, 改代码)
  ├── hanflow-evolve/  (skill 源)
  └── hanflow-site/    (P2 文档 PR 用)
EOF
    ;;
esac
