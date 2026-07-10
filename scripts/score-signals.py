#!/usr/bin/env python3
"""score-signals.py — P2 PRIORITIZE phase signal scoring + theme clustering.

(spec §3.3)

读取 <evolve_home>/cycles/<cycle_id>/signals.json (由 signal-gather.sh 产出) 与
<evolve_home>/config.yaml, 对每条 signal 打 0-100 分, 再聚合成 theme 并打 theme 分,
写出 <evolve_home>/cycles/<cycle_id>/scored.json。

用法:
    score-signals.py <evolve_home> <cycle_id>

设计说明 (Windows/MSYS 兼容):
    本机 python 是 native Windows 解释器。路径一律通过 argv 传入 (不经字符串插值进
    `python -c`), 与 signal-gather.sh / 测试 helper 的约定一致, 避免被 MSYS 转换。
"""
from __future__ import annotations

import datetime
import json
import os
import re
import sys
from typing import Any

import yaml


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

def load_config(evolve_home: str) -> dict[str, Any]:
    cfg_path = os.path.join(evolve_home, "config.yaml")
    with open(cfg_path, encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def now_utc() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc)


def parse_iso(ts: str | None) -> datetime.datetime | None:
    """解析 ISO8601 时间戳 (含 'Z' 后缀); 失败返回 None。"""
    if not ts:
        return None
    try:
        # Python 3.11+ 的 fromisoformat 可直接处理 'Z'; 兼容旧格式做一次替换。
        return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def normalize_source(source: str) -> str:
    """把 signal.source 归一化到 config.prioritization.source_weights 的 key。

    signal-gather.sh 产出 source ∈ {github, source_stub, learnings, competitor};
    测试与其它采集器可能用 github_issue / github_pr 等细分值, 统一映射到 github。
    """
    if not source:
        return ""
    if source.startswith("github"):
        return "github"
    return source


# ---------------------------------------------------------------------------
# 信号级打分 (spec §3.3 step 1)
# ---------------------------------------------------------------------------

# 标签 → 严重度加分 (取最大值, 不叠加)
LABEL_SEVERITY = [
    (frozenset({"bug", "security", "crash", "regression"}), 15),
    (frozenset({"feature", "enhancement", "improvement"}), 8),
    (frozenset({"question", "docs", "documentation"}), 2),
]

# 占位类型 → 严重度加分
STUB_TYPE_SEVERITY = {
    "stub_impl": 10,
    "cli_stub": 8,
    "todo_marker": 3,
}
# deferred_marker 按 Phase 阈值打分 (spec: Phase<=17 视为高优先)
DEFERRED_PHASE_THRESHOLD = 17
DEFERRED_SEVERITY_HIGH = 12
DEFERRED_SEVERITY_LOW = 0


def base_weight(source: str, config: dict[str, Any]) -> int:
    weights = (config.get("prioritization", {}) or {}).get("source_weights", {}) or {}
    key = normalize_source(source)
    return int(weights.get(key, 0))


def popularity_bonus(signal: dict[str, Any]) -> int:
    """GitHub only: min(reactions.total_count * 3, 25)。"""
    if normalize_source(signal.get("source", "")) != "github":
        return 0
    raw = signal.get("raw", {}) or {}
    reactions = raw.get("reactions", {}) or {}
    count = reactions.get("total_count", 0) or 0
    return min(int(count) * 3, 25)


def freshness_bonus(signal: dict[str, Any], now: datetime.datetime) -> int:
    """updated_at (优先) / created_at 在 7 天内 +15, 30 天内 +8, 否则 0。"""
    raw = signal.get("raw", {}) or {}
    ts = parse_iso(raw.get("updated_at")) or parse_iso(raw.get("created_at"))
    if ts is None:
        return 0
    # 归一化到 UTC 比较; 无时区信息时按 UTC 解释
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=datetime.timezone.utc)
    age_days = (now - ts).total_seconds() / 86400.0
    if age_days <= 7:
        return 15
    if age_days <= 30:
        return 8
    return 0


def _label_severity(labels: list[str]) -> int:
    best = 0
    lower = {str(l).lower() for l in (labels or [])}
    for keys, bonus in LABEL_SEVERITY:
        if lower & keys and bonus > best:
            best = bonus
    return best


def _stub_severity(raw: dict[str, Any]) -> int:
    stub_type = raw.get("type", "")
    if stub_type in STUB_TYPE_SEVERITY:
        return STUB_TYPE_SEVERITY[stub_type]
    if stub_type == "deferred_marker":
        # 从 context / snippet 解析 "Phase N"
        haystack = " ".join(filter(None, [
            str(raw.get("context", "") or ""),
            str(raw.get("snippet", "") or ""),
            str(raw.get("pattern", "") or ""),
        ]))
        m = re.search(r"Phase\s+(\d+)", haystack, flags=re.IGNORECASE)
        if m:
            phase = int(m.group(1))
            return DEFERRED_SEVERITY_HIGH if phase <= DEFERRED_PHASE_THRESHOLD else DEFERRED_SEVERITY_LOW
        # 未声明 Phase 的 deferred 视为高优先 (默认近期落地)
        return DEFERRED_SEVERITY_HIGH
    return 0


def severity_bonus(signal: dict[str, Any]) -> int:
    """标签严重度与占位类型严重度取最大值 (二者互斥, 取 max 安全)。"""
    raw = signal.get("raw", {}) or {}
    return max(_label_severity(raw.get("labels") or []), _stub_severity(raw))


def score_signal(signal: dict[str, Any], config: dict[str, Any],
                 now: datetime.datetime | None = None) -> dict[str, Any]:
    """计算单条 signal 的 0-100 分, 返回含 score + breakdown 的 signal 字典。"""
    if now is None:
        now = now_utc()
    base = base_weight(signal.get("source", ""), config)
    pop = popularity_bonus(signal)
    fresh = freshness_bonus(signal, now)
    sev = severity_bonus(signal)
    raw_score = base + pop + fresh + sev
    score = max(0, min(100, raw_score))

    out = dict(signal)
    out["score"] = score
    out["score_breakdown"] = {
        "base_weight": base,
        "popularity_bonus": pop,
        "freshness_bonus": fresh,
        "severity_bonus": sev,
        "raw_total": raw_score,
        "clamped": raw_score != score,
    }
    return out


# ---------------------------------------------------------------------------
# 主题聚类与主题打分 (spec §3.3 steps 2-3)
# ---------------------------------------------------------------------------

# theme_id → (title, version_impact, default_source)
THEME_META: dict[str, tuple[str, str, str]] = {
    "cli-completion": ("CLI command completion (stub delegation to SDK)", "patch", "source_stub"),
    "issue-bug": ("Bug / security fixes from GitHub issues", "patch", "github"),
    "issue-feature": ("Feature requests from GitHub", "minor", "github"),
    "issue-docs": ("Documentation improvements from GitHub", "patch", "github"),
    "issue-misc": ("Miscellaneous GitHub issues", "patch", "github"),
    "learnings-priority": ("Priorities from LEARNINGS.md", "minor", "learnings"),
    "misc": ("Miscellaneous signals", "patch", "mixed"),
}


def _signal_module(signal: dict[str, Any]) -> str:
    """从 signal 抽取模块名: 优先 raw.module, 否则从 file 路径推导。"""
    raw = signal.get("raw", {}) or {}
    mod = raw.get("module")
    if mod:
        return str(mod)
    f = raw.get("file", "") or ""
    if f:
        norm = str(f).replace("\\", "/")
        parts = [p for p in norm.split("/") if p and p != "hanflow"]
        return parts[0] if parts else ""
    return ""


def theme_key_for(signal: dict[str, Any]) -> str:
    """返回 signal 所属的 theme_id (聚类键)。"""
    source = normalize_source(signal.get("source", ""))
    raw = signal.get("raw", {}) or {}
    if source == "source_stub":
        stub_type = raw.get("type", "")
        if stub_type == "cli_stub":
            return "cli-completion"
        mod = _signal_module(signal) or "unknown"
        return f"stub-{mod}"
    if source == "github":
        labels = [str(l).lower() for l in (raw.get("labels") or [])]
        for bucket, keys in (
            ("bug", {"bug", "security", "crash", "regression"}),
            ("feature", {"feature", "enhancement", "improvement"}),
            ("docs", {"question", "docs", "documentation"}),
        ):
            if set(labels) & keys:
                return f"issue-{bucket}"
        return "issue-misc"
    if source == "learnings":
        return "learnings-priority"
    if source == "competitor":
        feat = raw.get("feature") or raw.get("framework") or "observed"
        return f"competitor-{feat}"
    return "misc"


def _theme_title(tid: str) -> str:
    """为动态 theme_id (stub-* / competitor-*) 生成可读标题; 其余查 THEME_META。"""
    if tid in THEME_META:
        return THEME_META[tid][0]
    if tid.startswith("stub-"):
        mod = tid[len("stub-"):].split(".")[0]
        return f"Complete source stubs in '{mod}' module"
    if tid.startswith("competitor-"):
        return f"Competitor feature inspiration: {tid[len('competitor-'):]}"
    return tid.replace("-", " ").capitalize()


def _theme_meta(tid: str, sources: set[str]) -> tuple[str, str, str]:
    """(title, version_impact, source) for a theme_id."""
    if tid in THEME_META:
        title, vimpact, default_src = THEME_META[tid]
    else:
        title = _theme_title(tid)
        if tid.startswith("stub-"):
            vimpact = "patch"
        elif tid.startswith("competitor-"):
            vimpact = "minor"
        else:
            vimpact = "patch"
        default_src = "mixed"
    src = sorted(sources)[0] if sources else default_src
    return title, vimpact, src


def cluster_themes(scored_signals: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """按 theme_id 聚类已打分的 signals → 原始 theme 列表 (未打分, 保序)。"""
    groups: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for sig in scored_signals:
        tid = theme_key_for(sig)
        if tid not in groups:
            groups[tid] = {
                "member_ids": [],
                "modules": set(),
                "sources": set(),
            }
            order.append(tid)
        g = groups[tid]
        sid = sig.get("id")
        if sid is not None:
            g["member_ids"].append(sid)
        mod = _signal_module(sig)
        if mod:
            g["modules"].add(mod)
        src = normalize_source(sig.get("source", ""))
        if src:
            g["sources"].add(src)

    themes: list[dict[str, Any]] = []
    for tid in order:
        g = groups[tid]
        title, vimpact, src = _theme_meta(tid, g["sources"])
        themes.append({
            "theme_id": tid,
            "title": title,
            "member_signals": g["member_ids"],
            "affected_modules": sorted(g["modules"]),
            "version_impact": vimpact,
            "source": src,
            # 默认 effort/risk; 未来可由 signal 元数据或 direction 阶段覆盖
            "effort": "medium",
            "risk": "low",
        })
    return themes


def score_theme(theme: dict[str, Any], scored_by_id: dict[str, dict[str, Any]],
                config: dict[str, Any]) -> dict[str, Any]:
    """计算单 theme 的 theme_score (0-100), 写回 theme 字典。"""
    pri = config.get("prioritization", {}) or {}
    tw = pri.get("theme_weights", {}) or {}

    member_ids = theme.get("member_signals") or []
    members = [scored_by_id[sid] for sid in member_ids if sid in scored_by_id]
    if not members:
        theme["theme_score"] = 0
        theme["theme_score_breakdown"] = {"member_count": 0}
        return theme

    scores = [m.get("score", 0) for m in members]
    # member_score = max*0.5 + avg*0.5: 既奖励峰值信号, 又反映群体热度
    member_score = max(scores) * 0.5 + (sum(scores) / len(scores)) * 0.5

    module_count = len(theme.get("affected_modules") or [])
    if module_count <= 1:
        breadth = 0
    elif module_count <= 3:
        breadth = 8
    else:
        breadth = 15
    breadth = min(breadth, int(tw.get("breadth_bonus_max", 15)))

    learnings_align = int(tw.get("learnings_alignment", 12)) if any(
        normalize_source(m.get("source", "")) == "learnings" for m in members
    ) else 0

    effort_pen = tw.get("effort_penalty", {}) or {}
    risk_pen = tw.get("risk_penalty", {}) or {}
    effort_p = int(effort_pen.get(theme.get("effort", "medium"), effort_pen.get("medium", -8)))
    risk_p = int(risk_pen.get(theme.get("risk", "low"), risk_pen.get("low", 0)))

    raw_total = member_score + breadth + learnings_align + effort_p + risk_p

    # 全员竞品来源 → 按 competitor_member_discount 折扣
    all_competitor = bool(members) and all(
        normalize_source(m.get("source", "")) == "competitor" for m in members
    )
    if all_competitor:
        raw_total *= float(pri.get("competitor_member_discount", 0.5))

    theme["theme_score"] = max(0, min(100, int(round(raw_total))))
    theme["theme_score_breakdown"] = {
        "member_score": round(member_score, 2),
        "member_count": len(members),
        "breadth_bonus": breadth,
        "module_count": module_count,
        "learnings_alignment": learnings_align,
        "effort_penalty": effort_p,
        "risk_penalty": risk_p,
        "competitor_discounted": all_competitor,
        "raw_total": round(raw_total, 2),
    }
    return theme


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def main(argv: list[str]) -> int:
    if len(argv) != 3:
        sys.stderr.write(
            "Usage: score-signals.py <evolve_home> <cycle_id>\n"
        )
        return 2

    evolve_home = argv[1]
    cycle_id = argv[2]

    if not os.path.isdir(evolve_home):
        sys.stderr.write(f"ERROR: evolve_home not found: {evolve_home}\n")
        return 1

    config = load_config(evolve_home)
    cycle_dir = os.path.join(evolve_home, "cycles", cycle_id)
    signals_path = os.path.join(cycle_dir, "signals.json")
    output_path = os.path.join(cycle_dir, "scored.json")

    if not os.path.isfile(signals_path):
        sys.stderr.write(f"ERROR: signals.json not found: {signals_path}\n")
        return 1

    with open(signals_path, encoding="utf-8") as fh:
        signals_data = json.load(fh)

    now = now_utc()
    scored_signals = [
        score_signal(sig, config, now)
        for sig in (signals_data.get("signals") or [])
    ]

    # 按分降序排列 (高优先在前); 稳定排序保持原顺序处理并列
    scored_signals.sort(key=lambda s: s.get("score", 0), reverse=True)

    # 聚类成 theme 并打 theme 分
    themes = cluster_themes(scored_signals)
    scored_by_id = {sig.get("id"): sig for sig in scored_signals if sig.get("id") is not None}
    themes = [score_theme(t, scored_by_id, config) for t in themes]
    themes.sort(key=lambda t: t.get("theme_score", 0), reverse=True)

    result = {
        "cycle_id": signals_data.get("cycle_id", cycle_id),
        "scored_at": now.isoformat(timespec="seconds"),
        "degraded": signals_data.get("degraded", {}) or {},
        "signals": scored_signals,
        "themes": themes,
    }

    os.makedirs(cycle_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
