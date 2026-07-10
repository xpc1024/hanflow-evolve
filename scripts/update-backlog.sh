#!/usr/bin/env bash
# update-backlog.sh — P2 PRIORITIZE 阶段: 由 scored.json 重新生成 BACKLOG.md (spec §3.4)
#
# 用法:
#     update-backlog.sh <evolve_home> <cycle_id>
#
# 输入: <evolve_home>/cycles/<cycle_id>/scored.json   (由 score-signals.py 产出)
# 输出: 覆写 <evolve_home>/BACKLOG.md
#
# 排序规则:
#   1. source == "human_override" 的主题无条件排最前;
#   2. 其余按 theme_score 降序; 分数并列时保持 scored.json 中的原顺序 (稳定排序)。
#
# Windows/MSYS 兼容:
#   本机 python 为 native Windows 解释器。路径通过环境变量传入, 不经 shell 插值进
#   `python -c`, 避免被 MSYS 路径转换破坏。Python 代码经 stdin (`python -`) 读取,
#   保证 heredoc 内不会有任何 shell 展开。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: update-backlog.sh <evolve_home> <cycle_id>}"
CYCLE_ID="${2:?Missing cycle_id}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

SCORED_FILE="$EVOLVE_HOME/cycles/$CYCLE_ID/scored.json"
if [ ! -f "$SCORED_FILE" ]; then
  echo "ERROR: scored.json not found: $SCORED_FILE" >&2
  exit 1
fi

BACKLOG="$EVOLVE_HOME/BACKLOG.md"

# 通过环境变量把路径传给 Python (不经 shell 字符串插值), 与 score-signals.py /
# write-state.sh 的 Windows 兼容约定一致。
export SCORED_FILE BACKLOG

python - <<'PYEOF'
import datetime
import json
import os
import sys


def now_utc_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def render_backlog(scored_path: str, backlog_path: str) -> None:
    with open(scored_path, encoding="utf-8") as fh:
        data = json.load(fh)

    themes = data.get("themes") or []

    # 排序: human_override 优先 (source == "human_override"), 其余按 theme_score 降序。
    # Python sort 稳定, 对并列分数保持原相对顺序。
    def sort_key(t):
        is_human = 1 if (t.get("source") == "human_override") else 0
        score = int(t.get("theme_score", 0) or 0)
        # 升序排序: human 标志在前 (1 > 0), 同标志内分数高的在前。
        # 用 (is_human, score) 升序排列后需要反转, 故这里用 (-is_human, -score)。
        return (-is_human, -score)

    themes_sorted = sorted(themes, key=sort_key)

    lines = []
    lines.append("# BACKLOG.md — hanflow-evolve 主题候选队列 (spec §7)")
    lines.append("")
    lines.append(
        "由 LOOP 的 signal + prioritization 阶段自动维护。每个候选**主题 (theme)** "
        "是一个可独立交付的演进单元, 对应一个 release。"
    )
    lines.append("")
    lines.append(
        f"> 自动生成于 {now_utc_iso()} · 共 {len(themes_sorted)} 个候选主题 "
        f"(cycle `{data.get('cycle_id', '')}`)。"
    )
    lines.append("")
    lines.append(
        "> 排序: `[human_override]` 主题无条件优先; 其余按 prioritization 得分降序。"
    )
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 待实现 (Pending)")
    lines.append("")
    lines.append(
        "> 按 prioritization 得分降序。标注 `[HUMAN]` 的条目为 human_override, "
        "无条件优先。"
    )
    lines.append("")

    if not themes_sorted:
        lines.append("(本 cycle 无候选主题。)")
        lines.append("")
    else:
        for idx, t in enumerate(themes_sorted, start=1):
            title = str(t.get("title") or t.get("theme_id") or "(untitled)")
            score = int(t.get("theme_score", 0) or 0)
            version = str(t.get("version_impact") or "patch")
            # score-signals.py 写出的字段名为 effort; 测试 fixture / 部分上游可能用
            # estimated_effort。两者都兼容, 缺省 medium。
            effort = str(t.get("effort") or t.get("estimated_effort") or "medium")
            risk = str(t.get("risk") or "low")
            source = str(t.get("source") or "")
            theme_id = str(t.get("theme_id") or "")
            modules = t.get("affected_modules") or []

            human_tag = " [HUMAN]" if source == "human_override" else ""
            header = (
                f"### [{idx}] {title}{human_tag} · score {score} · "
                f"{version} · effort {effort} · risk {risk}"
            )
            lines.append(header)
            lines.append("")
            lines.append(f"- **theme_id**: `{theme_id}`")
            if modules:
                mods = ", ".join(f"`{m}`" for m in modules)
                lines.append(f"- **affected_modules**: {mods}")
            lines.append(f"- **source**: `{source}`")
            member_signals = t.get("member_signals") or []
            if member_signals:
                sigs = ", ".join(f"`{s}`" for s in member_signals)
                lines.append(f"- **member_signals**: {sigs}")
            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("## 进行中 (In Progress)")
    lines.append("")
    lines.append("> 当前 cycle 锁定的主题。同一时刻最多 1 条 (单主题版本策略)。")
    lines.append("")
    lines.append("(空)")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 已完成 (Done)")
    lines.append("")
    lines.append(
        "> 已合并到 main 并 release 的主题。保留简短记录 "
        "(cycle_id / 版本 / 主题 / 日期)。"
    )
    lines.append("")
    lines.append("(空)")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 暂缓 (Deferred)")
    lines.append("")
    lines.append(
        "> 暂不处理的主题 (风险过高 / 等待外部依赖 / 优先级被压低)。"
        "人类可随时移回 Pending。"
    )
    lines.append("")
    lines.append("(空)")
    lines.append("")

    content = "\n".join(lines)
    # 原子写: 先写临时文件再替换, 避免半写状态。
    tmp = backlog_path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(content)
    os.replace(tmp, backlog_path)


def main() -> int:
    scored_path = os.environ.get("SCORED_FILE")
    backlog_path = os.environ.get("BACKLOG")
    if not scored_path or not backlog_path:
        sys.stderr.write("ERROR: SCORED_FILE / BACKLOG env vars not set\n")
        return 2
    if not os.path.isfile(scored_path):
        sys.stderr.write(f"ERROR: scored.json not found: {scored_path}\n")
        return 1
    render_backlog(scored_path, backlog_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYEOF
