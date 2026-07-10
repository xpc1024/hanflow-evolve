#!/usr/bin/env bash
# learnings-inject.sh — 按阶段抽取 LEARNINGS.md 相关段落注入 phase 上下文 (spec §7.6)
#
# 用法: learnings-inject.sh <evolve_home> <phase>
#   phase ∈ {scan, plan, design, code}
#
# 各阶段注入的 LEARNINGS 段落:
#   scan  : 已知技术债 + 下次优先
#   plan  : 框架架构模式 + 用户偏好 + 失败教训
#   design: 框架架构模式 + 失败教训
#           (编码风格 是 框架架构模式 的 ### 子节, 已包含在内, 无需单独抽取)
#   code  : 编码风格 + 失败教训
#
# 输出: 相关段落拼接到 stdout, 供 phase 提示词引用。
#
# 抽取规则 (awk, robust to future LEARNINGS 结构调整):
#   - 目标段落定位: 优先匹配 `## <name>`; 找不到再匹配 `### <name>` (子节)
#   - 边界: 从目标标题行起, 到下一个同级或更高级标题 / `---` 横线 / EOF
#     · h2 目标 → 遇下一个 `## ` 或 `---` 停
#     · h3 目标 → 遇下一个 `### ` / `## ` / `---` 停
#   - 边界行本身不计入输出 (干净段落)
set -euo pipefail

EVOLVE_HOME="${1:?Usage: learnings-inject.sh <evolve_home> <phase>}"
PHASE="${2:?Usage: learnings-inject.sh <evolve_home> <phase> (scan|plan|design|code)}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

# 解析 learnings 文件路径 (config.yaml learning.learnings_file, 默认 LEARNINGS.md)
CONFIG="$EVOLVE_HOME/config.yaml"
LEARNINGS_REL="LEARNINGS.md"
if [ -f "$CONFIG" ]; then
  LEARNINGS_REL=$(CONFIG_FILE="$CONFIG" python -c "import os,yaml; c=yaml.safe_load(open(os.environ['CONFIG_FILE'],encoding='utf-8')); print((c.get('learning') or {}).get('learnings_file') or 'LEARNINGS.md')" 2>/dev/null || echo "LEARNINGS.md")
fi

# 支持 learnings_file 为绝对路径或相对 EVOLVE_HOME 的名称
case "$LEARNINGS_REL" in
  /*|[A-Za-z]:*) LEARNINGS="$LEARNINGS_REL" ;;
  *)             LEARNINGS="$EVOLVE_HOME/$LEARNINGS_REL" ;;
esac

if [ ! -f "$LEARNINGS" ]; then
  echo "ERROR: LEARNINGS file not found: $LEARNINGS" >&2
  exit 1
fi

# 阶段 → 段落名列表 (顺序即输出顺序)
case "$PHASE" in
  scan)  SECTIONS=(已知技术债 下次优先) ;;
  plan)  SECTIONS=(框架架构模式 用户偏好 失败教训) ;;
  design) SECTIONS=(框架架构模式 失败教训) ;;
  code)  SECTIONS=(编码风格 失败教训) ;;
  *)
    echo "ERROR: unknown phase '$PHASE' (expected scan|plan|design|code)" >&2
    exit 1
    ;;
esac

# extract <name>: 一次性 awk, 自动判定 h2 / h3 并按级别切边界
extract() {
  local name="$1"
  awk -v name="$name" '
    BEGIN { found = 0; level = "" }
    !found {
      if ($0 ~ ("^## " name "[ \t]*$"))      { found = 1; level = "h2"; print; next }
      else if ($0 ~ ("^### " name "[ \t]*$")) { found = 1; level = "h3"; print; next }
    }
    found {
      if (level == "h2") {
        if ($0 ~ /^## / || $0 ~ /^---$/) { exit }
      } else {  # h3
        if ($0 ~ /^### / || $0 ~ /^## / || $0 ~ /^---$/) { exit }
      }
      print
    }
  ' "$LEARNINGS"
}

# 拼接各段落, 段落间用分隔线
first=1
for s in "${SECTIONS[@]}"; do
  body=$(extract "$s" || true)
  if [ -z "$body" ]; then
    # 段落缺失不致命, 仅 stderr 提示
    echo "WARN: section '$s' not found in $LEARNINGS" >&2
    continue
  fi
  if [ "$first" -eq 0 ]; then
    echo "---"
  fi
  first=0
  printf '%s\n' "$body"
done
