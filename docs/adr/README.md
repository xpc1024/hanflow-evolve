# Architecture Decision Records (ADR)

本目录记录 hanflow 架构契约的变更决策。详见 `CHARTER.md §6 决策协议`。

## 规则

1. **何时必须产 ADR**：见 CHARTER §6 触发清单（7 类：新增/删除/迁移模块、改依赖方向、换核心依赖、改错误基类契约、改 fitness function 矩阵/逻辑、改 CHARTER 自身、公开 API 契约变更）。
2. **格式**：MADR（见 `0000-template.md`）。强制记录 *备选方案* + *优劣*。
3. **编号**：连续递增（0001, 0002, ...），不重用。
4. **不可变**：已 `accepted` 的 ADR **不可编辑**，只能被新 ADR `supersede`（旧条标 `deprecated`，新条 frontmatter 写 `superseded by ADR-NNNN`）。
5. **白名单**：标题含 `allow-<check>-<pattern>` 的 ADR 可豁免对应 charter-check 违规，须精确列出豁免项 + `清零截止` 字段。
6. **强制力**：ADR 缺失不由脚本判定（无法 grep），而由 AUDIT Layer-2 的 E 类（历史一致性）检查——设计文档提架构变更却无 ADR 引用 → 严重问题回 P3/P4。

## 索引

- 0001 - Use CHARTER.md as authoritative source（确立权威源）
- 0002 - Bootstrap charter-check whitelist（首次全量扫描存量记录）
- 0003 (allow-errors-expr-error) - 豁免 core/expr.py ExprError 存量
- 0004 (allow-async-checkpoint-stubs) - 豁免 checkpoint.py LangGraph sync stubs
- 0005 (allow-layering-cross-ctx-gaps) - 豁免 8 文件跨层 import 存量
- 0006 - Broaden --doc architecture-change signal regex（扩展文档变更信号正则）
