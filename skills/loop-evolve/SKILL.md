---
name: loop-evolve
description: 启动或恢复 hanflow 自主进化循环. 读取 hanflow-evolve/state.yaml 判断当前阶段并继续.
  支持 /loop-evolve (继续当前) /loop-evolve new (强制新周期) /loop-evolve status (只看状态)
  /loop-evolve gate approve|revise|reject (Gate 确认) /loop-evolve topic <描述> (预设主题)
  /loop-evolve abort (紧急终止) /loop-evolve init (首次初始化)
---

# Loop Evolve — Hanflow 自主进化循环

## 启动逻辑

1. 定位 LOOP 家目录: `E:\opensource\hanflow-evolve` (或 `$HANFLOW_EVOLVE_DIR`)
2. 读 `state.yaml`:
   - 无 state.yaml 或 `phase == "uninitialized"` → 提示运行 `/loop-evolve init`
   - `phase == "awaiting_next_cycle"` → 检查 BACKLOG 队首,询问开始新周期
   - `phase` 是普通阶段(scan/prioritize/human_topic/plan/audit_direction/design/audit_design/plan_exec/code/verify/release/learn)且无 `last_error` → 继续该阶段
   - `phase` 是 `gateN` 且 `gate_status == "awaiting_user"` → 提示 Gate 确认
   - `last_error` 非空 → 报告错误,按恢复决策树(spec §8.4)询问如何继续
3. 进入对应阶段,按 `references/<phase>.md` 执行

## 并发防护

启动时先 `source scripts/acquire-lock.sh $EVOLVE_HOME` 获取锁,防止多个 LOOP 实例同时运行 (spec §8.6)。退出时自动释放。

## 命令变体

| 命令 | 行为 |
|------|------|
| `/loop-evolve` | 默认: 读 state.yaml 继续当前阶段 |
| `/loop-evolve new` | 强制开始新周期 (若当前未完成会警告) |
| `/loop-evolve status` | 只读: 打印 state.yaml + BACKLOG 队首 + 最近周期摘要 |
| `/loop-evolve gate approve` | 在 Gate 阶段: 批准,推进 |
| `/loop-evolve gate revise <反馈>` | 在 Gate 阶段: 附反馈回退 |
| `/loop-evolve gate reject <原因>` | 在 Gate 阶段: 终止周期 |
| `/loop-evolve topic <描述>` | 预设下周期主题 (写入 pending_human_topic) |
| `/loop-evolve abort` | 紧急终止当前周期 |
| `/loop-evolve init` | 首次初始化 LOOP 系统 |

## 阶段路由

根据 state.yaml 的 phase 字段,执行对应 reference 文档:

| phase | reference | 动作概述 |
|-------|-----------|---------|
| scan | references/scan.md | 采集信号 (issues/stubs/learnings) |
| prioritize | references/prioritize.md | 打分排序 BACKLOG |
| human_topic | references/human-topic.md | 询问开发者主题 (P2b) |
| plan | references/plan.md | 生成方向计划 (brainstorming 轻量) |
| audit_direction | references/audit.md | AUDIT direction.md |
| gate1 | (inline) | 等待用户方向确认 |
| design | references/design.md | 概要+架构设计 |
| audit_design | references/audit.md | AUDIT design.md |
| gate2 | (inline) | 等待用户设计确认 |
| plan_exec | references/execute.md | 生成执行计划 |
| code | references/code.md | TDD 实现 |
| verify | references/verify.md | 测试+smoke+auto-fix |
| gate3 | (inline) | 等待用户最终确认 |
| release | references/release.md | 版本号+GitHub 同步 |
| learn | references/learn.md | 回顾+写 LEARNINGS |

## 关键约束

- state.yaml 是唯一真相源,每次阶段转换用 `scripts/write-state.sh` 原子更新
- Gate 阶段不自动推进,必须等用户 approve/revise/reject
- 所有阶段产物落盘到 `cycles/<cycle_id>/`,阶段结束 commit 到 hanflow-evolve git
- 遵循 spec: `E:\opensource\docs\superpowers\specs\2026-07-10-hanflow-evolve-loop-system-design.md`
