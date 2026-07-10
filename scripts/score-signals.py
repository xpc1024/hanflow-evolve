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

    result = {
        "cycle_id": signals_data.get("cycle_id", cycle_id),
        "scored_at": now.isoformat(timespec="seconds"),
        "degraded": signals_data.get("degraded", {}) or {},
        "signals": scored_signals,
        "themes": [],  # 由 E2.2 填充
    }

    os.makedirs(cycle_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
