#!/usr/bin/env bash
# version-bump.sh — RELEASE 阶段: 对齐 4 个版本位置 + 生成 CHANGELOG (spec §5.1-5.3)
#
# 用法: version-bump.sh <evolve_home> <target_version>
#
# 版本唯一真相源 (single source of truth):
#   hanflow/hanflow/__init__.py  __version__  ← 权威源
#   下列 4 处 + state.yaml.current_version 均为它的派生, 由本脚本对齐:
#
# 4 个版本位置 (spec §5.1):
#   1. hanflow/hanflow/__init__.py   __version__ = "x.y.z"   (权威源)
#   2. hanflow/hanflow/api/__init__.py  FastAPI(version="x.y.z", ...)  (子包)
#   3. hanflow/pyproject.toml        [project] version = "x.y.z"
#   4. hanflow/web/package.json      { "version": "x.y.z" }
#   + state.yaml.current_version     (release 成功后回写, 解冻原冻结字段)
#
# 行为:
#   - 阻止降级 (target <= current 退出非 0, 原文件不动)
#   - 更新 4 处版本号
#   - 在 hanflow/CHANGELOG.md 顶部追加 (或创建) 新版本条目
#   - 校验 4 处一致后退出 0
#   - 把 evolve state.yaml.current_version 同步到 target (非阻断, 失败仅 WARN)
#
# Windows/MSYS 兼容:
#   路径通过环境变量传给 Python, 不经 shell 字符串插值, 避免被 MSYS 路径转换破坏。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: version-bump.sh <evolve_home> <target_version>}"
TARGET="${2:?Usage: version-bump.sh <evolve_home> <target_version>}"

if [ ! -d "$EVOLVE_HOME" ]; then
  echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2
  exit 1
fi

CONFIG="$EVOLVE_HOME/config.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "ERROR: config.yaml not found: $CONFIG" >&2
  exit 1
fi

# 校验 target 是合法 semver (x.y.z, 数字)
if ! printf '%s' "$TARGET" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: target_version '$TARGET' is not valid semver (x.y.z)" >&2
  exit 1
fi

# 用 Python 读取 config 里的 hanflow 路径 (经环境变量传路径, 避免插值)
HANFLOW_PATH=$(CONFIG_FILE="$CONFIG" python -c "import os,yaml; c=yaml.safe_load(open(os.environ['CONFIG_FILE'],encoding='utf-8')); print((c.get('paths') or {}).get('hanflow') or '')")
if [ -z "$HANFLOW_PATH" ]; then
  echo "ERROR: config.yaml paths.hanflow is empty" >&2
  exit 1
fi

# MSYS→Windows 路径解析 (native Windows python 需要 Windows 路径)
# 走环境变量 + 内嵌 python 的自解析, 与 signal-gather.sh 思路一致。
export HANFLOW_PATH TARGET

python - <<'PYEOF'
import json
import os
import re
import subprocess
import sys
import datetime

import yaml


def is_windows_native():
    return os.name == "nt"


_CYGPATH = None


def cygpath_available():
    global _CYGPATH
    if _CYGPATH is None:
        try:
            subprocess.run(["cygpath", "--version"], capture_output=True, check=True)
            _CYGPATH = True
        except (FileNotFoundError, subprocess.CalledProcessError):
            _CYGPATH = False
    return _CYGPATH


def resolve(p):
    """把 config/MSYS 路径解析成 native Windows python 可直接 open 的形式。"""
    if not p:
        return p
    if os.path.exists(p):
        return p
    if is_windows_native() and cygpath_available():
        try:
            proc = subprocess.run(
                ["cygpath", "-w", p], capture_output=True, text=True, check=True
            )
            return proc.stdout.strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass
    return p


def read_text(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def write_text(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def parse_current_version(init_path):
    """从 hanflow/__init__.py 的 __version__ 取当前版本 (权威源)。"""
    text = read_text(init_path)
    m = re.search(r"""__version__\s*=\s*['"]([^'"]+)['"]""", text)
    if not m:
        raise SystemExit(f"ERROR: __version__ not found in {init_path}")
    return m.group(1)


def semver_tuple(v):
    parts = v.split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise SystemExit(f"ERROR: invalid semver '{v}'")
    return tuple(int(p) for p in parts)


def update_file(path, transform):
    text = read_text(path)
    new_text = transform(text)
    if new_text == text:
        raise SystemExit(f"ERROR: no version field matched in {path}")
    write_text(path, new_text)


def main():
    hanflow = resolve(os.environ["HANFLOW_PATH"])
    target = os.environ["TARGET"]

    if not os.path.isdir(hanflow):
        raise SystemExit(f"ERROR: hanflow path not found: {hanflow}")

    init_py = os.path.join(hanflow, "hanflow", "__init__.py")
    api_init = os.path.join(hanflow, "hanflow", "api", "__init__.py")
    pyproject = os.path.join(hanflow, "pyproject.toml")
    package_json = os.path.join(hanflow, "web", "package.json")
    changelog = os.path.join(hanflow, "CHANGELOG.md")

    for p in (init_py, api_init, pyproject, package_json):
        if not os.path.isfile(p):
            raise SystemExit(f"ERROR: version location missing: {p}")

    current = parse_current_version(init_py)
    if semver_tuple(target) <= semver_tuple(current):
        raise SystemExit(
            f"ERROR: refusing downgrade/equals: current={current} target={target}"
        )

    # 1. __init__.py  __version__ = "x.y.z"
    update_file(
        init_py,
        lambda t: re.sub(
            r"""(__version__\s*=\s*)['"][^'"]+['"]""",
            lambda m: f'{m.group(1)}"{target}"',
            t,
        ),
    )

    # 2. api/__init__.py  FastAPI(version="x.y.z", ...)
    update_file(
        api_init,
        lambda t: re.sub(
            r"""(version\s*=\s*)['"][^'"]+['"]""",
            lambda m: f'{m.group(1)}"{target}"',
            t,
        ),
    )

    # 3. pyproject.toml  version = "x.y.z"  (匹配键后整体替换值)
    update_file(
        pyproject,
        lambda t: re.sub(
            r"""(^version\s*=\s*)['"][^'"]+['"]""",
            lambda m: f'{m.group(1)}"{target}"',
            t,
            flags=re.MULTILINE,
        ),
    )

    # 4. web/package.json — 用 node 做安全 JSON 编辑; 无 node 则回退到 Python json。
    try:
        subprocess.run(
            ["node", "--version"], capture_output=True, check=True
        )
        node_available = True
    except (FileNotFoundError, subprocess.CalledProcessError):
        node_available = False

    if node_available:
        # 经 stdin/stdout 传递 JSON, 避免路径插值问题
        pkg_raw = read_text(package_json)
        proc = subprocess.run(
            ["node", "-e",
             "let d='';process.stdin.on('data',c=>d+=c);"
             "process.stdin.on('end',()=>{const v=process.argv[1];"
             "const o=JSON.parse(d);o.version=v;"
             "process.stdout.write(JSON.stringify(o,null,2)+'\\n');})",
             target],
            input=pkg_raw, capture_output=True, text=True, check=True,
        )
        write_text(package_json, proc.stdout)
    else:
        pkg = json.loads(read_text(package_json))
        pkg["version"] = target
        write_text(package_json, json.dumps(pkg, ensure_ascii=False, indent=2) + "\n")

    # 5. CHANGELOG.md — 追加 (或创建) 新版本条目
    today = datetime.date.today().isoformat()
    header = f"# {target} — {today}\n\n"
    if os.path.isfile(changelog):
        existing = read_text(changelog)
        body = header + existing
    else:
        body = header
    write_text(changelog, body)

    # 校验 4 处一致
    new_current = parse_current_version(init_py)
    if new_current != target:
        raise SystemExit(
            f"ERROR: post-check __version__={new_current} != target={target}"
        )
    api_text = read_text(api_init)
    if not re.search(rf"""version\s*=\s*['"]{re.escape(target)}['"]""", api_text):
        raise SystemExit("ERROR: post-check api/__init__.py version mismatch")
    py_text = read_text(pyproject)
    if not re.search(
        rf"""^version\s*=\s*['"]{re.escape(target)}['"]""", py_text, flags=re.MULTILINE
    ):
        raise SystemExit("ERROR: post-check pyproject.toml version mismatch")
    pkg2 = json.loads(read_text(package_json))
    if pkg2.get("version") != target:
        raise SystemExit("ERROR: post-check package.json version mismatch")

    print(f"OK: bumped {current} -> {target} across 4 locations + CHANGELOG")


main()
PYEOF

# ── 同步 state.yaml.current_version (解冻字段) ──────────────────────────────
# 旧 bug: state.yaml.current_version 由 init 写一次后从不更新, 与权威源
# __init__.py.__version__ 长期 drift, 导致 site-sync.sh 把滞后版本号写进官网。
# release 成功后这里把它对齐到新 target (从 __init__.py 读 = target)。非阻断:
# 失败仅 WARN,不影响 4 处版本对齐已成功的退出 0。
#
# state 文件优先从 config.yaml paths.evolve_home 读 (与 site-sync.sh 同源),
# 退化到参数 evolve_home 自身的 state.yaml。write-state.sh 是本脚本的同级
# (scripts/write-state.sh), 用 BASH_SOURCE 解析, 不依赖 evolve_home 里有 scripts/。
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITE_STATE="$SELF_DIR/write-state.sh"
STATE_FILE=""
EVOLVE_HOME_FROM_CONFIG=$(CONFIG_FILE="$CONFIG" python -c "
import os, yaml
try:
    c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
    print(((c.get('paths') or {}).get('evolve_home') or '').strip())
except Exception:
    print('')
" 2>/dev/null || echo "")
for cand in "$EVOLVE_HOME_FROM_CONFIG/state.yaml" "$EVOLVE_HOME/state.yaml"; do
  if [ -n "$cand" ] && [ -f "$cand" ]; then
    STATE_FILE="$cand"
    break
  fi
done
if [ -n "$STATE_FILE" ] && [ -f "$WRITE_STATE" ]; then
  if bash "$WRITE_STATE" "$STATE_FILE" current_version "\"$TARGET\"" >/dev/null 2>&1; then
    echo "OK: state.yaml current_version -> $TARGET"
  else
    echo "WARN: 同步 state.yaml.current_version 失败 (4 处版本已对齐, 不阻断)" >&2
  fi
fi
