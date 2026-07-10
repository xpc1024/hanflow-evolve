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
