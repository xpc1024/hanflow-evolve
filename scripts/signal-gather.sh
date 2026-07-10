#!/usr/bin/env bash
# signal-gather.sh — 收集 evolution signals (spec §3.1, P1 SCAN phase)
# 用法: signal-gather.sh <evolve_home> <cycle_id>
#
# 信号来源:
#   1. GitHub issues/PRs (gh CLI, 可选)        — signals.github
#   2. 源码占位标记 (grep patterns)            — signals.source_stubs
#   3. LEARNINGS.md "## 下次优先" 段落          — signals.learnings
#   4. 竞品观察 (默认关闭)                      — signals.competitor
#
# 输出: <evolve_home>/cycles/<cycle_id>/signals.json
#   {cycle_id, gathered_at, degraded:{gh, competitor}, signals:[...]}
#
# 降级跟踪 (degraded):
#   gh         = "disabled_by_config" | "error: <type>" | "ok"
#   competitor = "skipped_by_default" | "disabled_by_config" | "ok"
#
# 设计说明 (Windows/MSYS 兼容):
#   本机 python 是 native Windows 解释器, 无法直接打开 MSYS 风格路径 (/tmp/...)
#   当路径被插值进 `python -c "..."` 字符串时。MSYS 仅在 (a) argv 传参和
#   (b) 环境变量 两种情况下自动转换路径。因此所有路径一律通过环境变量传入
#   内嵌 Python, 不做字符串插值。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: signal-gather.sh <evolve_home> <cycle_id>}"
CYCLE_ID="${2:?Missing cycle_id}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "ERROR: config.yaml not found: $CONFIG" >&2
  exit 1
fi

CYCLE_DIR="$EVOLVE_HOME/cycles/$CYCLE_ID"
OUTPUT="$CYCLE_DIR/signals.json"

mkdir -p "$CYCLE_DIR"

# 所有配置与路径一律走环境变量; 内嵌 Python 读取 os.environ。
# (避免把 MSYS 路径插值进 python -c 字符串 —— 见文件头说明)
export CONFIG
export OUTPUT
export CYCLE_ID
export EVOLVE_HOME

python <<'PYEOF'
import json
import os
import re
import subprocess
import datetime

import yaml


def is_windows_native():
    """True 当本进程是 native Windows python (非 MSYS/Cygwin python)。"""
    return os.name == "nt"


_CYGPATH = None


def cygpath_available():
    global _CYGPATH
    if _CYGPATH is not None:
        return _CYGPATH
    try:
        subprocess.run(["cygpath", "--version"], capture_output=True, check=True)
        _CYGPATH = True
    except (FileNotFoundError, subprocess.CalledProcessError):
        _CYGPATH = False
    return _CYGPATH


def resolve_path(p):
    """把配置里的路径解析成 python 可直接 open 的形式。

    背景: config.yaml 里的路径值 (如 hanflow: "/tmp/..." 或 "E:/...")
    只是普通字符串, 不会被 MSYS 自动转换。当运行 native Windows python
    时, MSYS 风格路径 (/tmp, /e/...) 无法被 open/isdir 解析。
    本函数在 Windows + 有 cygpath 时把 MSYS 路径转成 Windows 路径;
    其它情况原样返回 (Linux/MSYS-python 本身就能识别)。
    """
    if not p:
        return p
    if os.path.exists(p):
        return p
    if is_windows_native() and cygpath_available():
        try:
            proc = subprocess.run(
                ["cygpath", "-w", p],
                capture_output=True, text=True, check=True,
            )
            return proc.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass
    return p


def load_config():
    with open(os.environ["CONFIG"], encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def now_iso():
    # 本地时间 + 时区偏移, 避免 naive datetime 的歧义
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def true_str(s):
    """把 YAML bool/None 安全转成小写字符串 'true'/'false'。"""
    if s is None:
        return "false"
    return "true" if bool(s) else "false"


def classify_stub(pattern, line):
    """根据匹配的 pattern 与所在行, 给源码占位标记分类。

    返回值用于 weight_tier 估算与 direction 阶段判断:
      - stub_impl      : NotImplementedError (会抛异常的真占位实现)
      - deferred_marker: "deferred to Phase" / "wired in Phase" / "lands in Phase"
      - cli_stub       : "delegates to SDK" (CLI 命令批量占位)
      - todo_marker    : TODO / FIXME (弱信号)
    """
    p = pattern.lower()
    low = line.lower()
    if "notimplementederror" in p:
        return "stub_impl"
    if "delegates to sdk" in p:
        return "cli_stub"
    if "deferred to phase" in p or "wired in phase" in p or "lands in phase" in low:
        return "deferred_marker"
    if p in ("todo", "fixme"):
        return "todo_marker"
    return "todo_marker"


def tier_for_stub(stub_type):
    return {
        "stub_impl": "high",
        "cli_stub": "high",
        "deferred_marker": "high",
        "todo_marker": "low",
    }.get(stub_type, "low")


def collect_source_stubs(hanflow_path, patterns):
    """grep 各 pattern, 每个匹配产出一条 signal。

    扫描范围: 优先 `<hanflow_path>/hanflow` (框架源码包); 若不存在则回退到
    `<hanflow_path>` 本身。这样既覆盖真实仓库 (hanflow/ 是 E:/opensource/hanflow
    下的子包, 同级还有 508MB 的 web/ 前端资产不应被扫), 又兼容测试夹具
    (fake-hanflow/hanflow/...)。始终排除 VCS/缓存/构建目录, 避免噪声与超时。
    """
    signals = []
    if not hanflow_path or not os.path.isdir(hanflow_path):
        return signals
    package_dir = os.path.join(hanflow_path, "hanflow")
    scan_root = package_dir if os.path.isdir(package_dir) else hanflow_path

    # 排除目录: VCS / 依赖 / 缓存 / 构建 / 前端资产等
    exclude_dirs = [
        ".git", ".hg", ".svn",
        "node_modules", ".venv", "venv", "env",
        "__pycache__", ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox",
        "dist", "build", "site", ".eggs",
        "web", "site",  # 前端/官网资产, 非 hanflow 框架源码
    ]
    grep_args = ["grep", "-rn", "-E"]
    for d in exclude_dirs:
        grep_args += ["--exclude-dir", d]

    seen = set()  # (file, lineno) 去重, 同行多 pattern 只算一次按首个分类
    for pattern in patterns:
        try:
            proc = subprocess.run(
                grep_args + ["--", pattern, scan_root],
                capture_output=True, text=True,
            )
        except FileNotFoundError:
            # 没有 grep (极端环境): 跳过该 pattern
            continue
        if proc.returncode not in (0, 1):  # 1 = 无匹配, 正常
            continue
        for line in proc.stdout.splitlines():
            m = re.match(r"^(.*?):(\d+):(.*)$", line)
            if not m:
                continue
            path, lineno, content = m.group(1), int(m.group(2)), m.group(3)
            key = (path, lineno)
            if key in seen:
                continue
            seen.add(key)
            stub_type = classify_stub(pattern, content)
            signals.append({
                "id": f"stub:{path}:{lineno}",
                "source": "source_stub",
                "weight_tier": tier_for_stub(stub_type),
                "raw": {
                    "file": path,
                    "line": lineno,
                    "snippet": content.strip()[:300],
                    "pattern": pattern,
                    "type": stub_type,
                },
            })
    return signals


def collect_learnings(learnings_file):
    """解析 LEARNINGS.md 的 '## 下次优先' 段落。

    支持两种条目格式:
      - `- ` (无序列表, spec 示例格式)
      - `1. ` / `2. ` (有序列表, LEARNINGS.md 当前实际格式)
    """
    signals = []
    if not learnings_file or not os.path.isfile(learnings_file):
        return signals
    with open(learnings_file, encoding="utf-8") as fh:
        text = fh.read()

    # 切出 "## 下次优先" 段落 (到下一个 '## ' 或 EOF)
    m = re.search(r"^##\s*下次优先\s*$", text, flags=re.MULTILINE)
    if not m:
        return signals
    rest = text[m.end():]
    nxt = re.search(r"^##\s+", rest, flags=re.MULTILINE)
    section = rest[:nxt.start()] if nxt else rest

    idx = 0
    for raw_line in section.splitlines():
        stripped = raw_line.strip()
        # 无序 / 有序列表条目
        lm = re.match(r"^(?:-\s+|\d+\.\s+)(.+)$", stripped)
        if not lm:
            continue
        body = lm.group(1).strip()
        if not body:
            continue
        idx += 1
        signals.append({
            "id": f"learning:{idx}",
            "source": "learnings",
            "weight_tier": "high",
            "raw": {
                "text": body,
                    "index": idx,
            },
        })
    return signals


def collect_github(enabled, repo):
    """尝试 gh issue list; 返回 (signals, degraded_flag)。"""
    if not enabled:
        return [], "disabled_by_config"
    try:
        cmd = ["gh", "issue", "list", "--state", "open",
               "--limit", "50", "--json", "number,title,labels,body"]
        if repo:
            cmd += ["--repo", repo]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except FileNotFoundError:
        return [], "error: gh_not_installed"
    except subprocess.TimeoutExpired:
        return [], "error: gh_timeout"
    except OSError as exc:
        return [], f"error: {type(exc).__name__}"
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "").strip().splitlines()
        first = msg[0] if msg else "unknown"
        return [], f"error: gh_failed:{first[:120]}"
    try:
        items = json.loads(proc.stdout or "[]")
    except json.JSONDecodeError:
        return [], "error: gh_bad_json"
    signals = []
    for it in items:
        number = it.get("number")
        title = it.get("title", "")
        labels = [lb.get("name", "") for lb in (it.get("labels") or [])]
        signals.append({
            "id": f"gh:issue:{number}",
            "source": "github",
            "weight_tier": "high",
            "raw": {
                "number": number,
                "title": title,
                "labels": labels,
                "url": it.get("url", ""),
            },
        })
    return signals, "ok"


def competitor_degraded(enabled):
    if not enabled:
        return "skipped_by_default"
    return "ok"


def main():
    cfg = load_config()
    paths = cfg.get("paths", {}) or {}
    sig_cfg = cfg.get("signals", {}) or {}
    learning_cfg = cfg.get("learning", {}) or {}

    hanflow_path = resolve_path(paths.get("hanflow") or "")
    evolve_home = resolve_path(
        paths.get("evolve_home") or os.environ.get("EVOLVE_HOME") or ""
    )

    gh_cfg = sig_cfg.get("github", {}) or {}
    gh_enabled = bool(gh_cfg.get("enabled", False))
    gh_repo = gh_cfg.get("repo", "") or ""

    stubs_cfg = sig_cfg.get("source_stubs", {}) or {}
    stubs_enabled = bool(stubs_cfg.get("enabled", False))
    stub_patterns = list(stubs_cfg.get("patterns", []) or [])

    learn_enabled = bool((sig_cfg.get("learnings", {}) or {}).get("enabled", False))
    learnings_rel = learning_cfg.get("learnings_file", "LEARNINGS.md")
    # learnings_file 可能是相对名 (LEARNINGS.md) 或绝对路径
    lf_candidate = learnings_rel if os.path.isabs(learnings_rel) else os.path.join(evolve_home, learnings_rel)
    learnings_file = resolve_path(lf_candidate)

    comp_cfg = sig_cfg.get("competitor", {}) or {}
    comp_enabled = bool(comp_cfg.get("enabled", False))

    signals = []

    # 1. GitHub
    gh_signals, gh_deg = collect_github(gh_enabled, gh_repo)
    signals.extend(gh_signals)

    # 2. 源码占位
    if stubs_enabled:
        signals.extend(collect_source_stubs(hanflow_path, stub_patterns))

    # 3. LEARNINGS
    if learn_enabled:
        signals.extend(collect_learnings(learnings_file))

    # 4. 竞品 (默认关闭, 仅记 degraded)
    comp_deg = competitor_degraded(comp_enabled)

    result = {
        "cycle_id": os.environ["CYCLE_ID"],
        "gathered_at": now_iso(),
        "degraded": {
            "gh": gh_deg,
            "competitor": comp_deg,
        },
        "signals": signals,
    }

    with open(os.environ["OUTPUT"], "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=2)
        fh.write("\n")


main()
PYEOF
