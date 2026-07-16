# ADR-0002: Bootstrap charter-check whitelist from initial full scan

- 日期: 2026-07-16
- 状态: accepted
- 关联 cycle: 2026-W30-1.0.2
- 相关 fitness function: errors | async-api | layering
- 清零截止: v1.1.0

## 背景 (Context)

首次全量运行 `charter-check.sh --full`，发现代码库存在与 CHARTER §3 矩阵 / §2 不变量的偏差。
这些是历史存量（代码先于 charter 存在），非本 cycle 引入。为避免"首次全红卡死"，按 spec §3.3/§5.5
将存量入白名单，逐步清零；新增违规一律 FAIL。

**初始基线扫描结果**（2026-07-16，hanflow v1.0.1，110 文件）：

| 检查 | 违规数 | 说明 |
|---|---|---|
| errors | 1 | `core/expr.py` 的 `ExprError(Exception)` 未继承 HanflowError |
| registry | 0 | 基线干净（代码已用 NodeExecutorRegistry） |
| pydantic-data | 0 | 基线干净（Config/State/Schema 全走 Pydantic） |
| async-api | 3 | `persistence/checkpoint.py` 的 put/get_tuple/list 是 LangGraph BaseCheckpointSaver 强制 sync 签名（真实 async 实现在 aput/aget_tuple/alist） |
| layering | 11 | 8 个文件的跨层 import（直连 observability/isolation 而非经 ctx） |

## 决策驱动因素 (Decision Drivers)

1. 不让存量债卡住正常 release（spec §6.4：存量不阻断）
2. 存量可见、有清零计划（spec §5.3：过期机制）

## 备选方案 (Considered Options)

1. 存量入白名单（allow-* ADR），逐步清零
2. 存量立即修复后再启用 charter-check
3. 存量永久豁免

## 各方案优劣 (Pros/Cons)

### 方案1：入白名单逐步清零
- 优：立即可用，存量可见，增量守门即时生效
- 劣：需跟踪清零至 v1.1.0

### 方案2：立即修复
- 优：无技术债
- 劣：11 处 layering 修复需重构 ctx 注入，阻断所有演进，不现实

### 方案3：永久豁免
- 优：零工作量
- 劣：白名单腐烂，违背 fitness function 初衷

## 决策 (Decision)

选 方案1。本 ADR 是**记录性**文档（不可变历史）；实际豁免由 3 个 `allow-*` ADR 承载，
`_lib.sh:in_whitelist` 按文件名前缀 `allow-<check>-*` 精确匹配：
- `allow-errors-expr-error.md` → errors 检查的 core/expr.py
- `allow-async-checkpoint-stubs.md` → async-api 检查的 checkpoint.py
- `allow-layering-cross-ctx-gaps.md` → layering 检查的 8 个文件

## 后果 (Consequences)

- 正面：charter-check 立即生效，增量守门开始工作（P7 --diff / P8 --full 只阻断白名单外新增违规）
- 负面：存量违规存在至 v1.1.0，需在后续 cycle 逐步重构（layering 修复 = 把直连 import 改为经 ctx 注入）
- 中性：registry/pydantic-data 基线干净，无需白名单
- 引入的合规豁免: n/a（本文件为记录性，实际豁免见 3 个 allow-* ADR）
