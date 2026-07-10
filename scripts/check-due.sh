#!/usr/bin/env bash
# check-due.sh — SessionStart Hook: 零 token 的 LOOP 到期提醒 (spec §6.3)
#
# 用法: check-due.sh <evolve_home>
#
# 这是 SessionStart Hook 的入口。设计为零 token:
#   - 不调用任何 LLM, 只做日期比较 + 固定文案输出
#   - 静默 (无输出) 的情况:
#       1. 尚未初始化 (无 state.yaml)
#       2. config reminder.enabled = false
#       3. 距 last_reminded 不足 suppress_hours (避免每个新 session 都刷屏)
#       4. 距 last_cycle_completed 不足 interval_days (周期还没到点)
#   - 否则输出提醒文案到 stdout (附在 session 上下文里), 并由调用方负责把
#     last_reminded 更新为现在。
#
# 提醒文案按 phase 区分:
#   - phase == "awaiting_next_cycle" → 提示 "开始新周期"
#   - 其它 phase                    → 提示 "继续当前周期"
#
# 测试钩子: 若设了 NOW_DATE 环境变量 (YYYY-MM-DD), 用它代替系统今天, 便于测试。
#
# 退出码: 始终 0 (hook 失败不应中断 session 启动)。
set -euo pipefail

EVOLVE_HOME="${1:-${HANFLOW_EVOLVE_DIR:-}}"

# 缺参 → 静默 (hook 不能阻断 session)
if [ -z "$EVOLVE_HOME" ]; then
  exit 0
fi

if [ ! -d "$EVOLVE_HOME" ]; then
  exit 0
fi

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state.yaml"

# 情况 1: 未初始化 (无 state.yaml 或无 config.yaml) → 静默
if [ ! -f "$STATE" ] || [ ! -f "$CONFIG" ]; then
  exit 0
fi

# 一次性用 Python 读取 config + state 并完成所有日期判定。
# 路径一律走环境变量 (Windows native python 兼容), 不经 shell 插值。
export CONFIG STATE EVOLVE_HOME

# 默认 NOW = 系统今天; 测试可经 NOW_DATE 覆盖
if [ -n "${NOW_DATE:-}" ]; then
  export NOW_DATE
fi

# 输出约定: 第 1 行 = 动作 (SILENT | NEW_CYCLE | CONTINUE), 第 2 行起 = 文案(若有)
DECISION=$(python - <<'PYEOF'
import datetime
import os
import sys

import yaml


def load(path):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


cfg = load(os.environ["CONFIG"])
state = load(os.environ["STATE"])

reminder_cfg = (cfg.get("schedule") or {}).get("reminder") or {}
enabled = bool(reminder_cfg.get("enabled", True))
interval_days = int(reminder_cfg.get("interval_days", 7))
suppress_hours = int(reminder_cfg.get("suppress_hours", 24))

# 情况 2: reminder 关闭
if not enabled:
    print("SILENT")
    sys.exit(0)

# 解析 NOW
now_env = os.environ.get("NOW_DATE", "").strip()
if now_env:
    try:
        now = datetime.date.fromisoformat(now_env)
    except ValueError:
        now = datetime.date.today()
else:
    now = datetime.date.today()


def parse_date(v):
    if not v:
        return None
    try:
        # 兼容 "2026-07-10" 与 "2026-07-10T12:00:00+08:00"
        return datetime.date.fromisoformat(str(v)[:10])
    except ValueError:
        return None


def parse_dt(v):
    """尽力解析成 datetime (用于 suppress_hours 比较); 失败回退到 date。"""
    if not v:
        return None
    s = str(v)
    try:
        return datetime.datetime.fromisoformat(s)
    except ValueError:
        d = parse_date(s)
        return datetime.datetime(d.year, d.month, d.day) if d else None


last_cycle = parse_date(state.get("last_cycle_completed"))
last_reminded = parse_dt(state.get("last_reminded"))
phase = state.get("phase") or "uninitialized"

# 情况 3: suppress 窗口内 (距上次提醒不足 suppress_hours) → 静默
if last_reminded is not None:
    now_dt = datetime.datetime(now.year, now.month, now.day)
    hours_since = (now_dt - last_reminded).total_seconds() / 3600.0
    if hours_since < suppress_hours:
        print("SILENT")
        sys.exit(0)

# 情况 4: 距上次周期完成不足 interval_days → 静默
if last_cycle is not None:
    days_since = (now - last_cycle).days
    if days_since < interval_days:
        print("SILENT")
        sys.exit(0)

# 周期到点 (或从未完成过周期) → 输出提醒
if phase == "awaiting_next_cycle":
    print("NEW_CYCLE")
else:
    print("CONTINUE")
PYEOF
)

case "$DECISION" in
  SILENT|SILENT*)
    # 静默: 不输出任何东西
    :
    ;;
  NEW_CYCLE)
    cat <<'EOF'
LOOP 提醒: 距上个 cycle 完成已超过 interval_days, 可以开始新周期了。
运行 /loop-evolve new 或 /loop-evolve 继续 BACKLOG 队首主题。
EOF
    ;;
  CONTINUE)
    cat <<'EOF'
LOOP 提醒: 当前 cycle 距上次活动已超过 interval_days, 建议继续推进。
运行 /loop-evolve 继续当前阶段。
EOF
    ;;
  *)
    # 未知决策 → 静默 (不阻断 session)
    :
    ;;
esac

exit 0
