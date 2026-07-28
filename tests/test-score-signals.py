"""Tests for score-signals.py (spec §3.3)."""
import json
import subprocess
import sys
import tempfile
import os
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "scripts" / "score-signals.py"

DEFAULT_CONFIG = {
    "prioritization": {
        "source_weights": {"github": 40, "source_stub": 35, "learnings": 40, "competitor": 15},
        "theme_weights": {
            "breadth_bonus_max": 15,
            "learnings_alignment": 12,
            "effort_penalty": {"small": 0, "medium": -8, "large": -18},
            "risk_penalty": {"low": 0, "medium": -10, "high": -25},
        },
        "competitor_member_discount": 0.5,
        "score_gap_for_tie": 5,
        "max_themes_in_backlog": 20,
    }
}


def run_score(signals_data, config_data=None):
    """Write signals.json + config.yaml, run score-signals.py, return parsed scored.json."""
    import yaml
    with tempfile.TemporaryDirectory() as tmp:
        evolve = Path(tmp)
        cycle_dir = evolve / "cycles" / "test"
        cycle_dir.mkdir(parents=True)
        (cycle_dir / "signals.json").write_text(json.dumps(signals_data), encoding="utf-8")
        if config_data is None:
            config_data = DEFAULT_CONFIG
        (evolve / "config.yaml").write_text(yaml.dump(config_data), encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(SCRIPT), str(evolve), "test"],
            capture_output=True, text=True
        )
        assert result.returncode == 0, f"score-signals failed: {result.stderr}"
        return json.loads((cycle_dir / "scored.json").read_text(encoding="utf-8"))


def test_github_bug_with_reactions_scores_high():
    signals = {
        "cycle_id": "test",
        "degraded": {},
        "signals": [{
            "id": "gh-issue-42",
            "source": "github_issue",
            "weight_tier": "high",
            "raw": {
                "number": 42, "title": "CLI resume not working",
                "labels": ["bug"],
                "reactions": {"total_count": 8},
                "created_at": "2026-07-08T00:00:00Z",
                "updated_at": "2026-07-08T00:00:00Z",
            }
        }]
    }
    result = run_score(signals)
    score = result["signals"][0]["score"]
    # base(40) + popularity(min(24,25)=24) + severity(bug=15) = 79 min (freshness varies)
    assert score >= 79, f"Expected >= 79, got {score}"


def test_notimplementederror_stub_gets_severity_bonus():
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [{
            "id": "stub-1", "source": "source_stub", "weight_tier": "high",
            "raw": {"type": "stub_impl", "file": "a/b.py", "line": 1, "module": "a", "context": "raise NotImplementedError()"}
        }]
    }
    result = run_score(signals)
    score = result["signals"][0]["score"]
    assert score == 45, f"Expected 45, got {score}"  # base(35) + severity(10)


def test_score_clamped_to_100():
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [{
            "id": "gh-1", "source": "github_issue", "weight_tier": "high",
            "raw": {
                "number": 1, "title": "x", "labels": ["bug", "security"],
                "reactions": {"total_count": 100},
                "created_at": "2026-07-09T00:00:00Z", "updated_at": "2026-07-09T00:00:00Z",
            }
        }]
    }
    result = run_score(signals)
    assert result["signals"][0]["score"] <= 100


def test_competitor_signal_has_low_base_weight():
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [{
            "id": "comp-1", "source": "competitor", "weight_tier": "low",
            "raw": {"framework": "LangGraph", "feature": "streaming"}
        }]
    }
    result = run_score(signals)
    score = result["signals"][0]["score"]
    assert score == 15, f"Expected 15, got {score}"  # base only, no other bonuses


def test_theme_aggregation_groups_related_signals():
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [
            {"id": f"stub-{i}", "source": "source_stub", "weight_tier": "high",
             "raw": {"type": "cli_stub", "file": "hanflow/cli/main.py", "line": 100+i,
                     "module": "cli", "context": f"cmd{i}: delegates to SDK"}}
            for i in range(5)
        ]
    }
    result = run_score(signals)
    assert len(result["themes"]) >= 1
    cli_theme = result["themes"][0]
    assert len(cli_theme["member_signals"]) == 5
    assert cli_theme["theme_score"] > 0


def test_themes_sorted_by_score_descending():
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [
            {"id": "gh-1", "source": "github_issue", "weight_tier": "high",
             "raw": {"number": 1, "title": "bug", "labels": ["bug"],
                     "reactions": {"total_count": 20},
                     "created_at": "2026-07-09T00:00:00Z", "updated_at": "2026-07-09T00:00:00Z"}},
            {"id": "stub-1", "source": "source_stub", "weight_tier": "high",
             "raw": {"type": "todo_marker", "file": "x/y.py", "line": 1, "module": "x", "context": "# TODO"}},
        ]
    }
    result = run_score(signals)
    scores = [t["theme_score"] for t in result["themes"]]
    assert scores == sorted(scores, reverse=True), f"Not sorted desc: {scores}"


def test_stub_module_extracted_from_windows_absolute_path():
    """回归: stub 在 Windows 绝对路径下不应聚成 stub-E: / stub-e / stub-home。

    历史 bug: _signal_module 用"过滤 hanflow 后取 parts[0]",但 Windows 绝对路径
    E:/.../hanflow/hanflow/api/... 的 parts[0] 是盘符 'E:',导致所有 stub 聚成
    一个错误的 stub-E: theme (19 stub 挤一起)。

    修复: 定位路径中最后一个 /hanflow/ 包根, 取其后第一级目录作 module。
    本测试锁住该行为, 三种路径风格都应聚成按真实模块的 theme。
    """
    # 三种路径风格, 都指向 observability 模块 (路径里有两个 hanflow: 仓库根 + 包根)
    paths = [
        "E:/opensource/hanflow/hanflow/observability/trace.py",          # Windows 绝对
        "/e/opensource/hanflow/hanflow/observability/trace.py",          # MSYS
        "/home/user/hanflow/hanflow/observability/trace.py",             # Linux
    ]
    signals = {
        "cycle_id": "test", "degraded": {},
        "signals": [
            {"id": f"stub:{p}:{i}", "source": "source_stub", "weight_tier": "high",
             "raw": {"type": "stub_impl", "file": p, "line": 80 + i, "snippet": "NotImplementedError"}}
            for i, p in enumerate(paths)
        ]
    }
    result = run_score(signals)
    theme_ids = [t["theme_id"] for t in result["themes"]]

    # 三条 signal 应聚成同一个 stub-observability theme (而非 stub-E:/stub-e/stub-home)
    assert "stub-observability" in theme_ids, f"应为 stub-observability, 实际: {theme_ids}"
    assert "stub-E:" not in theme_ids, "Windows 盘符泄露到 theme_id (回归 bug)"
    assert "stub-e" not in theme_ids, "MSYS 盘符泄露到 theme_id"
    obs_theme = next(t for t in result["themes"] if t["theme_id"] == "stub-observability")
    assert len(obs_theme["member_signals"]) == 3, "三种路径应聚到同一模块"
    assert obs_theme["affected_modules"] == ["observability"], \
        f"affected_modules 应为 ['observability'], 实际: {obs_theme['affected_modules']}"
