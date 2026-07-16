# ADR-0005: Allow layering check to exempt cross-ctx-gap imports

- 日期: 2026-07-16
- 状态: accepted
- 关联 cycle: 2026-W30-1.0.2
- 相关 fitness function: layering
- 清零截止: v1.1.0

## 背景 (Context)

首次全量 layering 检查发现 11 处跨层 import（8 个文件），均为 L2/L3/L4 模块**直接 import**
observability/isolation/atoms 而非经 `ctx` 访问。这是 charter §3 依赖倒置原则的存量违规：
代码先于"经 ctx 访问"原则确立。

具体违规（caller → callee）：
- `atoms/execution.py:117` atoms → isolation
- `isolation/sandbox.py:29` isolation → observability
- `memory/skills.py:20` memory → observability
- `models/router.py:27` models → observability
- `orchestration/context_impl.py:18,19,160` orchestration → isolation（×2）/ observability
- `orchestration/nodes/coordinator.py:19` orchestration → isolation
- `orchestration/nodes/leaf.py:78,108` orchestration → atoms（×2）
- `tools/bus.py:17` tools → observability

## 决策驱动因素 (Decision Drivers)

1. 修复需重构 ctx 注入路径（把直连 import 改为经 RuntimeContext Protocol 访问），涉及 8 文件、跨多模块
2. 非本 cycle 范围（本 cycle 是 charter 基础设施搭建）
3. 存量必须可见、有清零计划

## 备选方案 (Considered Options)

1. 豁免 8 文件，v1.1.0 前逐步重构为 ctx 注入
2. 立即重构所有 11 处
3. 永久豁免

## 各方案优劣 (Pros/Cons)

### 方案1：豁免 + 逐步重构
- 优：charter-check 增量守门立即生效；新增跨层违规即被抓
- 劣：11 处存量存续至 v1.1.0

### 方案2：立即重构
- 优：无债
- 劣：8 文件 ctx 重构是独立工作量，超出本 cycle 范围；阻断 charter 启用

### 方案3：永久豁免
- 优：零工作
- 劣：白名单腐烂，违背 fitness function 初衷

## 决策 (Decision)

选 方案1。v1.1.0 前按文件逐个重构：把 `from hanflow.observability import ...` 改为
`ctx.trace.export(...)`（经 RuntimeContext Protocol）。每修一个文件，从本 ADR 豁免列表移除一项。

## 后果 (Consequences)

- 正面：layering 检查对增量代码立即生效（新增跨层 import 立即 FAIL）
- 负面：11 处存量违规存续至 v1.1.0
- 引入的合规豁免: hanflow/atoms/execution.py, hanflow/isolation/sandbox.py, hanflow/memory/skills.py, hanflow/models/router.py, hanflow/orchestration/context_impl.py, hanflow/orchestration/nodes/coordinator.py, hanflow/orchestration/nodes/leaf.py, hanflow/tools/bus.py（跨层直连 import 存量，应经 ctx 访问，清零截止 v1.1.0）
