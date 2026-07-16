# CHARTER.md — hanflow 架构守护规约（权威源）

> 本文件是 hanflow 自主进化体系的**单一权威规约源**。所有架构契约、设计不变量、编码规范、
> 禁止模式、决策协议均以此为准。LEARNINGS.md 的"设计不变量"区块为本文件的速查摘要；
> AUDIT A 类规则与本文件 §2/§3 对齐。
>
> **加载时机**：LOOP P6（code）阶段开头必读全文（SOUL.md 式注入：本心先于行动）。
> **修改规则**：见 §8——agent 不可单方面修改本文件，须经 ADR + 人工 Gate。
>
> 关联：ADR-0001 确立本文件为权威源。

---

## §1 本心与定位

**hanflow 是什么**：以 LangGraph 为运行时地基的高可控 agent 编排框架，融合研究（DeerFlow 式引用溯源）/执行（DeepAgents 式文件记忆+递归委派）/多 agent 协作三类能力，在统一 DSL 下同时支持静态/动态可递归组合。

**北极星目标**：唯一在统一 DSL 下同时支持静态/动态可递归组合，且把隐私路由、RAG 便捷对接、LangSmith 可观测作为一等公民的高可控编排框架。

**自主进化授权范围**：
- LOOP 系统可在本文件 §2 不变量约束内自主演进代码与设计。
- **以下变更必须经人工 Gate**（agent 不可自主完成）：
  - 修改本文件自身（§8）；
  - 公开 API/契约变更（§6 触发清单第 7 类：CLI 增删命令、SDK 签名变更、DSL schema 加删节点、YAML 配置键变更）；
  - 换核心依赖（如替换 LangGraph）。

---

## §2 设计不变量

以下模式在重构/演进时**不可破坏**，否则破坏框架契约。每条标注守护脚本（policy-as-code）。

1. **统一错误层级** —— 守护：`charter-check/errors.sh`
   所有框架错误继承 `HanflowError`（`hanflow/core/errors.py`），带稳定 `code`（机器可读）+ `retryable` 标志 + `run_id`/`node_id`/`span_id` 关联坐标。atoms/primitives **永不吞异常**；由 orchestration 包装层捕获，记录 `NodeState.error` + trace error span，再按 `on_error` 策略决定下一步。

2. **异步优先 (async-first)** —— 守护：`charter-check/async-api.sh`
   全框架默认 `async def`；同步入口仅 CLI/SDK 边界用 `asyncio.run` 桥接。新增 IO API（complete/embed/get/put/search 等，见脚本的方法名模式）默认 `async def`。

3. **Pydantic v2 配置/数据模型** —— 守护：`charter-check/pydantic-data.sh`
   结构化数据（Config/State/Schema/Spec/Request/Response 命名的类）走 `BaseModel` + `ConfigDict`，不用裸 `@dataclass`。

4. **DSL→编译→执行 三段式** —— 守护：`charter-check/registry.sh`
   `WorkflowDSL.from_yaml` → `Compiler.compile` → `NodeExecutorRegistry` 分派。新增节点类型走 registry 注册（`@register_node` 或等价机制），**不要在 compiler 里硬编码 `if/elif node.type ==` 链**。

5. **per-run sandbox（非 per-agent）** —— 守护：AUDIT A 类（语义）
   `RunSandbox` 是 run 级共享资源；子 agent 只在其下分得 subdir。隔离级别 LOCAL/DOCKER/K8S/NONE 可选，但契约固定。

6. **spec 段落引用** —— 守护：AUDIT（文档习惯）
   设计决策在 docstring 中以 `§N.N` 回链 spec，便于追溯。

---

## §3 架构图与边界

### 依赖倒置原则（矩阵的立法理由）

`RuntimeContext` 的 Protocol 定义必须放在 `core/`（L0 底座）。只有**组合根**（runtime/api/cli + 顶层 `config.py`/`sdk.py`）直接 import 具体的 L4 模块去构造 ctx；atoms/orchestration 等只依赖 core 里的 ctx Protocol + 基础类型。**经 ctx 访问 L4，不直接 import**——这是矩阵里大片 ✗ 的统一依据。

### 合法依赖方向矩阵（14×14）

行 = 调用方，列 = 被调用方，✓ = 允许，✗ = 禁止，self = 同模块。包枚举（经 `hanflow/` 实际目录核实，14 个顶层包）：core / atoms / orchestration / models / memory / runtime / isolation / persistence / tools / retrieval / observability / workflows / api / cli。

| 调用方 ↓ \ 被调用方 → | core | atoms | orchestration | models | memory | runtime | isolation | persistence | tools | retrieval | observability | workflows | api | cli |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **core** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **atoms** | ✓ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **orchestration** | ✓ | ✓ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **models** | ✓ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **memory** | ✓ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **isolation** | ✓ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **persistence** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **tools** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ |
| **retrieval** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ | ✗ |
| **observability** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ | ✗ | ✗ |
| **workflows** | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | ✗ | self | ✗ | ✗ |
| **runtime** | ✓ | ✓ | ✓ | ✓ | ✓ | self | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| **api** | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | self | ✗ |
| **cli** | ✓ | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | self |

**解读**：
- core 是底座，只依赖自身，谁都能依赖它。
- L2/L3/L4 各层内部模块互不横穿（atoms 不碰 orchestration，models 不碰 memory）。
- runtime/api/cli 是组合根，可向下依赖任意 L4（含 workflows）；**runtime 的全依赖仅限构造 RuntimeContext，业务逻辑不得下沉**；cli 经 api，不直接绕。
- observability 横切：被各层 tap（经 `ctx.trace.export()`），但 observability 自身只依赖 core；各层 tap 走 ctx，不直接 import observability。
- retrieval/workflows 是 L4 数据访问层，规则同 models/memory。

---

## §4 编码规范

- 文件头 docstring 说明本模块职责 + 回链 spec 段落（如 `§12.10`）。
- 普遍使用 `from __future__ import annotations`（PEP 563，字符串形式注解）。
- 类型：`X | None` 而非 `Optional[X]`；内置泛型 `list[str]`/`dict[str, Any]`，不用 `typing.List`。
- 枚举用 `StrEnum`（字符串值，JSON 友好）。
- 错误信息带上下文（run_id/node_id），便于 trace 关联。
- 占位代码用明确标记：`NotImplementedError("...lands in Phase N (reason)")` 或 docstring 注明 `wired in Phase N`，**不静默 no-op**。

---

## §5 禁止模式

- **LangChain 抽象泄漏**：不在 hanflow 内引入 LangChain 的 agent/chain/retriever 抽象（LangGraph 薄封装除外）。对应概要设计"避免 DeepAgents 三层抽象泄漏"。
- **隐式/不确定控制流**：不写"agent 自己决定顺序"的隐式编排；控制流须显式声明。
- **工具硬编码不走 MCP**：工具调用统一走 MCPBus，不绕过直接调外部 API。
- **吞异常**：atoms/primitives 永不 `except: pass`（见 §2.1）。
- **裸 dataclass 做配置**：Config/State/Schema 用 Pydantic，不用裸 `@dataclass`（见 §2.3）。

---

## §6 决策协议（ADR）

### 何时必须产 ADR（7 类触发）

| # | 触发条件 | 例子 |
|---|---|---|
| 1 | 新增/删除/迁移一个顶层模块 | 新增 `retrieval/`、拆分 `memory/` |
| 2 | 改层间依赖方向 | 让 `core` 开始依赖别的模块 |
| 3 | 换核心依赖 | 从 LangGraph 换到别的运行时 |
| 4 | 改错误基类契约 | `HanflowError` 加/删必填字段 |
| 5 | 修改 fitness function 矩阵或检查逻辑 | 改 §3 矩阵、新增/删除 charter-check |
| 6 | 修改 CHARTER.md 自身 | 改不变量、改原则（见 §8） |
| 7 | 公开 API/契约变更 | CLI 增删命令、SDK 签名变更、DSL schema 加删节点、YAML 配置键变更 |

纯实现改动（加函数、修 bug、补 docstring）**不需要 ADR**。

### ADR 规则

- 格式：MADR（`docs/adr/0000-template.md`），强制记录备选方案 + 优劣。
- 编号：连续递增，不重用。
- **不可变**：已 accepted 的 ADR 不可编辑，只能 supersede。
- 详见 `docs/adr/README.md`。

### 白名单放行

- 标题含 `allow-<check>-<pattern>` 的 accepted ADR 可豁免对应 charter-check 违规。
- ADR 须**精确**列出豁免的模块/文件路径 + `清零截止` 字段。
- 无 `清零截止` 的豁免立即 FAIL；到期未清零须 supersede 说明延期理由，否则豁免失效。

---

## §7 进化契约

mutation loop 三步：
1. **generate**：P6 code 阶段实现（加载本文件后）。
2. **fitness functions 守门**：P7 verify 跑 `charter-check.sh --diff`（增量）+ P8 release 跑 `--full`（全量，只阻断白名单外新增违规）。
3. **(需 ADR 则产 ADR) → commit**：属 §6 触发的变更，先产 ADR 再编码；Gate 通过的 artifact 是锁定输入，不可重跑。

---

## §8 升级规约本身

**agent 不可单方面修改本文件**。修改流程：

1. 必须产 ADR（属 §6 第 6 类触发）。
2. ADR 必须走**人工 Gate**（不进 LOOP 自动流）。
3. 人工批准后：新建 CHARTER 版本 + 对应 charter-check 脚本同步更新 + LEARNINGS 指针刷新。

### 紧急豁免通道（防规则僵化）

若 charter-check 因"规则本身疑似有误"而 FAIL：
1. agent 产 ADR 标记"规则修正提案"（status: proposed，关联违规证据）。
2. LOOP 带问题标注进 Gate（复用现有 `gate_status: revised`，不新增状态）。
3. 人工审议：批准 → CHARTER + charter-check 同步修正；驳回 → agent 按原规则修代码。

这是"规则疑似有误"的专用通道，**不是**"嫌规则烦"的逃生口。
