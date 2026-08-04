# AUDIT — design.md (cycle 2026-W32-1.2.2)

| 审核项 | |
|---|---|
| 文档 | `cycles/2026-W32-1.2.2/design.md` |
| 阶段 | P4b audit_design |
| 审核员 | 独立 subagent (Layer-2 语义审核, fresh context) |
| 时间 | 2026-08-04 |

## Layer-1 (规则检查)
- `audit-rules-check.sh design`: **OK** (初次 FAIL: 错误处理章节未提 HanflowError; 已修订为显式声明"零运行时改动, 不触碰任何 HanflowError 子类" — 这既满足规则又如实反映设计本质; 复检 OK exit 0)
- `charter-check --doc`: **WARN** (假阳性, "影响模块"正则误匹配; Layer-2 E 类判定无需 ADR)

## Layer-2 (语义审核)

### 审核结论
- 整体: **通过** (0 严重 / 0 轻微)
- 基线声明经源码全部核实: pyproject markers 仅 integration / ci.yml docker pull continue-on-error / 13 测试构成 / Makefile 无 test-docker / 4 个 Sandbox 错误全名准确

### A. 架构合规性 — 全 pass
- 6 层定位: pass — 改动全在测试基建层, hanflow/ 运行时零触碰
- Protocol-based/RuntimeContext: pass — 不涉及
- HanflowError-only (不变量1): pass — 显式声明零运行时改动; 4 个 Sandbox 错误抛出路径/code/retryable/run_id 不被触碰
- 异步优先: pass — 4 lifecycle 测试保留 @pytest.mark.asyncio
- Pydantic/DSL/三段式/per-run sandbox/LangGraph: pass — 均不涉及
- spec 段落引用: pass — 回链 cycle 出处与 LEARNINGS 编号

### B. 完整性 — 全 pass
- 覆盖 direction 全部目标 (缺口A→改动4, 缺口B→改动1/2/3, CI可见性→改动4, 文档→改动5)
- 错误处理 / 测试策略 (5 条可验证断言) / 迁移兼容 (4 条) / 非目标 / 前端影响(无): 全 pass

### C. 自洽性 — 全 pass
- 接口契约 5 入口与改动一一对应; 依赖无环; 数据流闭环
- 命名一致: `test (non-docker)` / `test (docker, real daemon)` 全文统一, 已落实 audit-direction 命名精确化建议
- 测试计数守恒: not docker (9) + docker (4) = 13 = 原 make test 全集 ✓ (经源码核实)
- 双标记并存语义: skip_no_docker (本机 skip, 判定不变) + docker (可选运行+可辨识), 职责分离

### D. 复杂度控制 — 全 pass
- YAGNI: 选最小方案, 否决独立 job/testcontainers 并留升级路径; ~20 行配置 + 1 README
- 不引入无用抽象: marker 只加 1 个, 不为 Local/K8s 预留

### E. 历史一致性 — 全 pass
- charter-check WARN (ADR 必要性): **无需 ADR** (CHARTER §6 七类触发无一命中, 运行时零改动)
- 与 LEARNINGS #1/#133/#135 对齐; 正确划界 K8s/定制镜像为其它主题
- 与现有 specs/ADR (0001/0002/0006/0007) 不冲突

## 建议修订
无。

## 处置决策
- 0 严重 0 轻微 → **通过**, 进入 Gate 2
