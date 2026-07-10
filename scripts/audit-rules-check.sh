#!/usr/bin/env bash
# audit-rules-check.sh — AUDIT Layer 1 规则检查 (spec §4b.3)
#
# 用法: audit-rules-check.sh <doc.md> <direction|design>
#
# Layer 1 是零 token 的纯规则检查:
#   - direction 文档必须包含章节: 动机 / 目标 / 非目标 / 影响模块 / 验收标准
#   - design  文档必须包含章节: 架构定位 / 组件分解 / 接口契约 / 数据流 /
#                                 错误处理 / 测试策略 / 迁移兼容
#   - design 的 "错误处理" 章节还必须提到 HanflowError
#
# 章节匹配规则: 形如 `## <section>` 或 `### <section>` 的 markdown 标题
# (section 名后允许跟其它文字, 如 `## 错误处理 / HanflowError`)。
#
# 退出码: 0 = 全部章节就绪; 非 0 = 有缺失章节 (FAIL 消息写到 stderr/stdout)。
set -euo pipefail

DOC="${1:?Usage: audit-rules-check.sh <doc.md> <direction|design>}"
KIND="${2:?Usage: audit-rules-check.sh <doc.md> <direction|design>}"

if [ ! -f "$DOC" ]; then
  echo "ERROR: doc not found: $DOC" >&2
  exit 1
fi

case "$KIND" in
  direction)
    REQUIRED_SECTIONS=(动机 目标 非目标 影响模块 验收标准)
    ;;
  design)
    REQUIRED_SECTIONS=(架构定位 组件分解 接口契约 数据流 错误处理 测试策略 迁移兼容)
    ;;
  *)
    echo "ERROR: unknown doc kind '$KIND' (expected direction|design)" >&2
    exit 1
    ;;
esac

# header_present <section>
# 匹配 `^##?\s*<section>` (markdown ## 或 ### 标题, section 后可跟任意文字)。
header_present() {
  local section="$1"
  # -E 扩展正则; ## 与 ### 都算章节标题
  grep -Eq "^###[[:space:]]*${section}|^##[[:space:]]*${section}" "$DOC"
}

missing=()
for s in "${REQUIRED_SECTIONS[@]}"; do
  if ! header_present "$s"; then
    missing+=("$s")
  fi
done

# design 专属: 错误处理章节须提到 HanflowError
hanflow_error_ok=true
if [ "$KIND" = "design" ]; then
  # 先确认存在 "错误处理" 标题, 再读取该章节正文判定是否含 HanflowError
  if header_present "错误处理"; then
    # 提取 "错误处理" 章节正文 (从该标题到下一个同级或更高级 ## 标题)
    # 用 awk 抓取从匹配行到下一个 `^## ` (不含 ###) 的内容
    section_text=$(awk '
      /^##[[:space:]]*错误处理/ { in_sec=1; next }
      in_sec && /^##[[:space:]]/ { in_sec=0 }
      in_sec { print }
    ' "$DOC")
    if ! echo "$section_text" | grep -Eq "HanflowError"; then
      hanflow_error_ok=false
    fi
  fi
fi

# 判定与输出
if [ ${#missing[@]} -eq 0 ] && [ "$hanflow_error_ok" = "true" ]; then
  echo "OK: $KIND doc has all required sections"
  exit 0
fi

echo "FAIL: $KIND doc ($DOC) is missing required content:"
for s in "${missing[@]}"; do
  echo "  - 缺失章节: $s"
done
if [ "$KIND" = "design" ] && [ "$hanflow_error_ok" = "false" ]; then
  echo "  - 错误处理章节未提及 HanflowError"
fi
exit 1
