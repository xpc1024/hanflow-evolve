---
name: loop-evolve-max
description: 启动或恢复 hanflow 自主进化循环(满血版, 内嵌领域专家团队). 读取
  hanflow-evolve/state-max.yaml 判断当前阶段并继续. 支持 /loop-evolve-max (继续当前)
  /loop-evolve-max new (强制新周期) /loop-evolve-max status (只看状态)
  /loop-evolve-max gate approve|revise|reject (Gate 确认)
  /loop-evolve-max topic <描述> (预设主题) /loop-evolve-max abort (紧急终止)
  /loop-evolve-max init (首次初始化)
---

# Loop-Evolve-Max — Hanflow 自主进化循环(满血版)

> loop-evolve 的满血版:核心阶段委托 loop-evolve(经路径替换),专家带(P3/P3b/P4/P4b/P6/P7)
> 完全自有并内嵌 9 位领域专家。详见 spec:
> `docs/superpowers/specs/2026-08-03-loop-evolve-max-design.md`

## 启动逻辑

1. 定位 LOOP 家目录: `E:\opensource\hanflow-evolve`(或 `$HANFLOW_EVOLVE_DIR`)
2. 读 `state-max.yaml`:
   - 无 state-max.yaml 或 `phase == "uninitialized"` → 提示运行 `/loop-evolve-max init`
   - `phase == "awaiting_next_cycle"` → 检查 BACKLOG 队首, 询问开始新周期
   - `phase` 是普通阶段且无 `last_error` → 继续该阶段
   - `phase` 是 `gateN` 且 `gate_status == "awaiting_user"` → 提示 Gate 确认
   - `last_error` 非空 → 报告错误, 按恢复决策树询问如何继续
3. 进入对应阶段, 按下表执行

## 并发防护

启动时先 `source scripts/acquire-lock.sh $EVOLVE_HOME` 获取锁(与 loop-evolve 共享
`.loop.lock`, 互斥——max 与 loop-evolve 驱动同一 hanflow checkout)。
锁机制同 loop-evolve(spec §8.6)。

## 启动强制拉取最新代码 (preflight-sync)

加锁**之后**、读 state 路由**之前**:
`bash $EVOLVE_HOME/scripts/preflight-sync.sh loop`
(智能 WIP 保护同 loop-evolve, 详见 scripts/preflight-sync.sh)

## 委托阶段路径替换约定

委托阶段读 loop-evolve 的 reference doc 执行, 但**执行前将 `state.yaml` 全局替换为
`state-max.yaml`**。其余字面量(cycles/、.loop.lock、BACKLOG.md、docs/superpowers、
CHARTER.md、LEARNINGS.md、hanflow-evolve、hanflow-home)均为共享 infra, 保持不变。
(经 Python 扫描 loop-evolve 全部 reference doc 核实, 唯一需替换项即 state.yaml。)

**loop-evolve reference 路径解析**(同 contribute-pr):
- 优先读安装位置 `~/.zcode/skills/loop-evolve/references/<phase>.md`
- 若不存在(install.sh 未装或非 ZCode 环境), 读仓库相对路径
  `$EVOLVE_HOME/skills/loop-evolve/references/<phase>.md`
- 两种形式等价, 取先找到者

## 阶段路由表

| phase | 执行方式 | reference |
|-------|---------|-----------|
| scan | **纯委托** | 读 loop-evolve/references/scan.md(路径替换) |
| prioritize | **纯委托** | 读 loop-evolve/references/prioritize.md(路径替换) |
| human_topic | **委托+追加** | references/human-topic.md |
| plan | **自有** | references/plan.md |
| audit_direction | **自有** | references/audit.md(P3b) |
| gate1 | (inline) | 等待用户方向确认 |
| design | **自有** | references/design.md |
| audit_design | **自有** | references/audit.md(P4b) |
| gate2 | (inline) | 等待用户设计确认 |
| plan_exec | **纯委托** | 读 loop-evolve/references/execute.md(路径替换) |
| code | **自有** | references/code.md |
| verify | **自有** | references/verify.md |
| gate3 | (inline) | 等待用户最终确认 |
| release | **纯委托** | 读 loop-evolve/references/release.md(路径替换) |
| learn | **委托+追加** | references/learn.md |

## 命令变体

| 命令 | 行为 |
|------|------|
| `/loop-evolve-max` | 默认: 读 state-max.yaml 继续当前阶段 |
| `/loop-evolve-max new` | 强制开始新周期(若当前未完成会警告) |
| `/loop-evolve-max status` | 只读: 打印 state-max.yaml + BACKLOG 队首 + 最近周期摘要 |
| `/loop-evolve-max gate approve` | 在 Gate 阶段: 批准, 推进 |
| `/loop-evolve-max gate revise <反馈>` | 在 Gate 阶段: 附反馈回退 |
| `/loop-evolve-max gate reject <原因>` | 在 Gate 阶段: 终止周期 |
| `/loop-evolve-max topic <描述>` | 预设下周期主题(写入 pending_human_topic) |
| `/loop-evolve-max abort` | 紧急终止当前周期 |
| `/loop-evolve-max init` | 首次初始化: 创建 state-max.yaml(见下) |

## /loop-evolve-max init(bootstrap state-max.yaml)

write-state.sh 不创建文件, 故 init 须先建 state-max.yaml 种子:

```yaml
# state-max.yaml 种子(init 时写入)
cycle_id: null
phase: awaiting_next_cycle
gate_status: approved
started_at: null
target_theme: null
target_version: null
retry_count: 0
audit_retry_count: 0
last_error: null
revision_feedback: null
pending_human_topic: null
pending_core_override: false
last_cycle_completed: null
last_reminded: null
site_sync_needed: false
# 注意: 不含 current_version(规避 loop-evolve 冻结字段 bug, 需要时从
#       hanflow/hanflow/__init__.py.__version__ 实时读)
```

写入后提示用户用 `/loop-evolve-max new` 开始首个周期。

## 关键约束

- state-max.yaml 是 max 唯一真相源, 每次阶段转换用 `scripts/write-state.sh state-max.yaml <key> <value>` 原子更新
- Gate 阶段不自动推进, 必须等用户 approve/revise/reject
- 所有阶段产物落盘到 `cycles/<cycle_id>/`(与 loop-evolve 共享), 阶段结束 commit
- 零改动 loop-evolve / contribute-pr: max 永不写入它们的文件;委托阶段只读 loop-evolve reference
- 遵循 spec: `docs/superpowers/specs/2026-08-03-loop-evolve-max-design.md`

## 安装

维护者/尝鲜者通过 install.sh 单独安装(不进默认安装列表):

```bash
bash install.sh <github_user>          # 先做基础安装(clone evolve 仓库)
bash install.sh --install-max          # 再装 loop-evolve-max 满血版 skill
```

或手工:把 `skills/loop-evolve-max/` 复制到 `~/.zcode/skills/loop-evolve-max/`。
