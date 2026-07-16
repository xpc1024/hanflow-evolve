# ADR-0001: Use CHARTER.md as authoritative source for architecture governance

- 日期: 2026-07-16
- 状态: accepted
- 关联 cycle: 2026-W30-1.0.2
- 相关 fitness function: none
- 清零截止: n/a

## 背景 (Context)

hanflow-evolve 的架构治理此前分散在三处：`LEARNINGS.md` 的 6 条设计不变量、`references/audit.md` 的 AUDIT A/E 类规则、LOOP spec §0.3/§8.9 的设计原则与自保护规则。没有任何一份始终生效的全局规约，agent 在 LOOP 外动代码时不会自动加载约束，长期自主进化面临架构漂移风险。

## 决策驱动因素 (Decision Drivers)

1. 可控性（防漂移）> 一致性 > 开发速度
2. 业界研究结论：纯 markdown 规则会立即衰减，需 policy-as-code
3. 消除"多真相源"导致的规则不一致

## 备选方案 (Considered Options)

1. 整合为单一权威源 CHARTER.md，现有文件改为引用它
2. 叠加在现有治理之上，CHARTER 只补充未覆盖部分
3. 分层结构（CHARTER + AGENTS.md + fitness-functions.md + adr/ 多文件）

## 各方案优劣 (Pros/Cons)

### 方案1：整合为单一权威源
- 优：一份文件管全部，消除重复与不一致；改动集中
- 劣：CHARTER 较长（~8 节）

### 方案2：叠加
- 优：改动最小
- 劣：治理仍分散，双真相源风险

### 方案3：分层
- 优：结构清晰
- 劣：文件多，维护成本高，agent 需读多份

## 决策 (Decision)

选 方案1。新建 `CHARTER.md` 收编 LEARNINGS 6 不变量 + AUDIT A 类 + spec §0.3 原则；LEARNINGS 的不变量区块加指针引用 CHARTER §2；AUDIT A 类保持不动（本就与 CHARTER 对齐）。

## 后果 (Consequences)

- 正面：单一权威源，始终生效；每条不变量挂可执行守护脚本
- 负面：CHARTER 修改须经人工 Gate（见 CHARTER §8）
- 中性：LEARNINGS 保留为"学习库"，不变量区块降为速查摘要
- 引入的合规豁免: n/a
