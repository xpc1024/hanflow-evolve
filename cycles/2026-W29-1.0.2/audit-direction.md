# AUDIT — direction.md (2026-W29-1.0.2 LLM streaming)

> 审核身份：P3b AUDIT Layer-2（fresh context，未参与 direction 编写）
> 审核对象：`cycles/2026-W29-1.0.2/direction.md`
> 审核日期：2026-07-15
> 审核基准：`CHARTER.md`、`LEARNINGS.md`、hanflow 源码（`E:/opensource/hanflow/hanflow/`）

## 审核结论
- 整体: **通过（含 1 项轻微修订建议，不阻断进 P3c）**
- 严重问题: 0（A/C/E 类全 pass）
- 轻微问题: 1（B/D 类，建议在 design 阶段补，可自动补）
- **ADR 必要性核心结论: 不需要产 ADR**（详见 E 类逐条判定）

源码交叉验证（用于支撑判定）：
- `ModelProvider` Protocol 确无 `stream()`（`models/providers/base.py:34`）✓
- `ModelRouter` 确无 `stream()`（`models/router.py:32`）✓
- 6 个真实 provider（openai/anthropic/glm/ollama/deepseek/vllm）均无 `stream` ✓
- `FakeProvider.stream()` 返回 `AsyncIterator[str]`（裸 str，非结构化 chunk）——与 direction 提议的 `StreamChunk` 模型存在签名分歧，"孤岛"描述属实 ✓
- `LLMExecutor` 只调 `ctx.complete()`（`orchestration/nodes/leaf.py:37`）✓
- `RuntimeContextImpl` 存在于 `orchestration/context_impl.py`，`complete()` 委托 router，分层合规 ✓

---

## 逐项判定

### A. 架构合规性

- [pass] **6 层定位清晰**: 改动落在 L0 `core/`（context/result）+ L2 `orchestration/`（context_impl + leaf）+ L4 `models/`（base/router/providers）。影响模块表（line 62-74）逐一列明，未触达 L3 atoms / L1 DSL / 持久化 / 隔离。定位精确。
- [pass] **Protocol-based 不靠继承**: `ModelProvider` 本就是 `@runtime_checkable Protocol`（base.py:33），新增 `stream()` 仍是 Protocol 方法；`RuntimeContext` 同为 Protocol（context.py:25-26）。无引入具体类继承耦合。推荐路径 A 维持 Protocol 扩展而非新增继承层级，符合 §3 依赖倒置。
- [pass] **错误处理用 HanflowError**: 现有 `LLMExecutor` 已用 `HanflowError`（leaf.py:14,28）；direction 明确占位用 `NotImplementedError`（遵循 §4 编码规范"明确标记不静默"），二者职责清晰——`NotImplementedError` 是"未实现"信号、`HanflowError` 是运行时框架错误。stream 路径的 provider 调用失败仍会经 router fallback 走 HanflowError 链路，未破坏不变量 #1。
- [pass] **经 RuntimeContext 注入不跨层 import**: `LLMExecutor` 调 `ctx.stream()`（line 30 目标），不直接 import `models.*`；`RuntimeContextImpl` 作为组合根经构造注入 router。与现网 `complete()` 模式对称，符合 §3 "atoms/orchestration 经 ctx 访问 L4"。方向文档影响模块表 line 71 已正确标注"context_impl 经 ctx 访问 models，合规"。
- [pass] **DSL 单一真相源**: 本 cycle 不动 `WorkflowDSL.from_yaml` / `Compiler` / `NodeExecutorRegistry`，只在 `NodeConfig.__pydantic_extra__` 加可选 `stream: true` 键（leaf.py:19 模式）。严格说这是往 config extra dict 里塞键而非改 DSL schema——验收标准 #7 也声明"charter-check 全绿"。注意：若 design 阶段把 `stream` 提升为 `NodeConfig` 的显式 Pydantic 字段，需重新评估是否触发 DSL schema 变更（见建议 1）。
- [pass] **LangGraph 薄运行时不引 LangChain 抽象**: direction §风险（line 80）明确 openai 用原生 `AsyncOpenAI().chat.completions.create(stream=True)`、glm 用 SSE，不引 LangChain agent/chain/retriever。符合 §5 禁止模式。base.py docstring 已写死"NOT LangChain LLM abstractions"。

A 类小结：6/6 pass，无严重项。

### B. 完整性

- [pass] **覆盖所有目标（in scope 清晰）**: 6 条 in scope（Protocol/Router/ctx/Provider/Executor/测试）逐条可验收，验收标准 8 条对应得上。
- [pass] **有错误处理策略**: 占位 `NotImplementedError` + router fallback 复用 complete 策略（line 39, 82）。明确声明非静默 no-op。
- [pass] **有测试策略**: 验收标准 #2/#4/#6/#8 含 Router/Executor 单测 + openai/glm 契约测试（mock HTTP）+ FakeProvider 对齐 + `make ci` 全绿。覆盖面合理。
- [pass] **有迁移兼容（现有代码不破）**: 路径 A 的 `stream()` 作为 Protocol 新方法，占位让未实现的 provider 显式失败；FakeProvider 已有 stream（需对齐签名）；验收标准 #8 明确"现有测试不破"。
- [pass] **有非目标（out of scope）**: 5 条 out of scope 清晰（DOCKER/WS 推送/原子流式/剩余 provider/特殊成本处理），边界明确。
- [**轻微**] **缺：DSL config 键 `stream: true` 的迁移/兼容声明**。direction 在 line 30 提"`node.config.stream: true`"作为触发开关，但未说明：这是走 `__pydantic_extra__`（现状，零迁移）还是升格为 NodeConfig 显式字段（会改 schema）？若后者，需补 migration 说明。建议 design 阶段定：**保持 extra dict，不升格**（最小惊讶 + 不触发 ADR 第 7 类）。

B 类小结：5/6 pass，1 轻微（建议自动补）。

### C. 自洽性

- [pass] **接口输入输出匹配**: `ctx.stream()` → `AsyncIterator[StreamChunk]`，router 产同类型，provider 产同类型；`LLMExecutor` 消费 `AsyncIterator[StreamChunk]` 累积进 `NodeState`。类型链闭环。`RuntimeContext.complete` 返回 `Any`（context.py:44），而 router.complete 返回 `ModelResponse`——这是既有松散签名（不是本 cycle 引入），stream 应直接声明 `AsyncIterator[StreamChunk]` 而非 `Any`，direction 已这么做（line 26-27），自洽。
- [pass] **组件依赖无环**: models←(router 调 providers)←(context_impl 调 router)←(leaf 调 ctx)。单向 DAG，无环。models 不 import orchestration（§3 矩阵 L4→L2 为 ✗），direction 未破坏。
- [pass] **数据流闭环**: Provider token → StreamChunk → Router（fallback/trace span）→ ctx.stream → Executor 累积 NodeState + 上游事件。闭环完整。**注意一处需 design 明确**：direction line 30 "向上游传播流式事件"——上游指 `RunHandle._queue`（sdk.py 已预留 `RunEvent.kind="llm_token"` 但当前无人 emit）还是 NodeState？这两条路径差异大。direction 没说清，但属 design 细节非 direction 自洽问题。
- [pass] **命名一致**: `stream` / `StreamChunk` / `complete` / `ModelResponse` 全文统一；与现有 `complete()`/`ModelResponse`/`TokenUsage` 命名族对齐。

C 类小结：4/4 pass，无严重项。数据流向上游传播的去向建议 design 阶段细化（非 direction 级问题）。

### D. 复杂度控制

- [pass] **未过度设计（YAGNI）**: 推荐"路径 A（扩展 Protocol）"而非"路径 B（新建 StreamingProvider）"，明确拒绝组合式新 Protocol。占位 `NotImplementedError` 而非给 4 个不急的 provider 写真实实现，符合 YAGNI。仅做 2 个真实 provider（openai+glm，一国际一国产）作为契约验证，合理。
- [pass] **复杂度匹配 minor 版本**: 1.0.2→1.1.0 是 minor bump。本 cycle 改动是"补技术债"（LEARNINGS 中优先级明确标注）+ 加对称方法，不引入新架构概念、不改依赖方向、不动 DSL。复杂度与 minor 匹配。LEARNINGS 用户偏好（line 125）"演进优先填补现有占位/技术债"——本主题完全对齐。

D 类小结：2/2 pass。

### E. 历史一致性 + ADR 必要性（核心）

- [pass] **不与 LEARNINGS 约束冲突**: LEARNINGS 中优先级（line 83-85）明确"LLM token 流式未实现"是已知技术债，本 cycle 正是补此项；用户偏好（单主题版本、填补技术债、conventional commits）全对齐。`__version__` 现为 `1.0.1`（`__init__.py:14`），本 cycle 升 `1.1.0`（feat→minor）符合语义化版本策略。无冲突。
- [pass] **不与现有 specs 冲突**: hanflow 仓库内未发现独立 spec 文档目录（`docs/adr/` 当前不存在/为空）；CHARTER §2 不变量、§3 依赖矩阵、§5 禁止模式均未被触犯（见 A 类）。`base.py` docstring "NOT LangChain LLM abstractions" 与 direction 路径选择一致。

#### ADR 必要性判定（逐条对照 CHARTER §6 七类触发）

- **第 1 类（新增/删除/迁移顶层模块）: 否。**
  本 cycle 不新增顶层包（14 包枚举不变），只在现有 `models/providers/`、`orchestration/`、`core/` 内加方法/加类。`StreamChunk` 是新增数据类，不是顶层模块迁移。

- **第 2 类（改层间依赖方向）: 否。**
  依赖矩阵（CHARTER §3）零变化。`orchestration→models` 仍为 ✗（走 ctx 注入），`orchestration→core` 仍为 ✓。新增的 `ctx.stream()` 反而强化了既有的依赖倒置（经 ctx 访问），方向不变。

- **第 3 类（换核心依赖）: 否。**
  LangGraph 仍是运行时；openai/glm 用各自原生 SDK（本就在用）。不替换任何核心依赖。

- **第 4 类（改错误基类契约）: 否。**
  `HanflowError` 的 `code`/`retryable`/`run_id`/`node_id`/`span_id` 契约不动。占位用 `NotImplementedError`（Python 内置，非框架错误层级成员），不污染 `HanflowError`。stream 路径的运行时错误仍走 router→HanflowError 链。

- **第 5 类（改 fitness function）: 否。**
  不动 §3 矩阵、不增删 charter-check 脚本。验收标准 #7 反而依赖现有 charter-check 全绿来"验证守护不误报"。

- **第 6 类（改 CHARTER 自身）: 否。**
  本 cycle 不改 CHARTER.md，也不走 §8 升级流程。

- **第 7 类（公开 API/契约变更）: 否（重点项，已逐字核实）。**
  核实依据（源码证据）：
  1. `hanflow/__init__.py:16-25` 的 `__all__`（公开 SDK 面）只导出：`Hanflow`、`HanflowConfig`、`load_config`、`WorkflowDSL`、`RunHandle`、`RunResult`、`RunEvent`、`__version__`。**`ModelProvider` 不在公开 SDK 导出列表内**——它是 `models/providers/base.py` 的内部 Protocol，面向"实现新 provider 的开发者"而非"调用 hanflow 的终端用户"。
  2. CHARTER §6 第 7 类原文枚举的"公开 API/契约"四种形态是：**CLI 增删命令 / SDK 签名变更 / DSL schema 加删节点 / YAML 配置键变更**。逐项对照：
     - CLI 命令：本 cycle 不动 CLI（无命令增删）。✗ 触发。
     - **SDK 签名变更**：公开 SDK 入口 `Hanflow.run()` 已有 `stream: bool = False` 参数（sdk.py:114），`RunHandle.stream()` 已存在（sdk.py:68），`RunEvent.kind` 已含 `"llm_token"` 字面量（sdk.py:47）——**公开 SDK 的流式签名本就已预留**，本 cycle 是"接通内部实现"而非"新增公开签名"。✗ 触发。
     - DSL schema 加删节点：不增删节点类型（LLM 节点早存在）。✗ 触发。
     - YAML 配置键变更：本 cycle 不动 `config.yaml` 的 `models:` / 顶层键。`node.config.stream` 走 `__pydantic_extra__`（即任意键字典），不是 DSL schema 的强类型字段，不构成"YAML 配置键变更"（前提是 design 阶段守住"不升格为 NodeConfig 显式字段"，见建议 1）。✗ 触发。
  3. "在 Protocol 上加方法算签名变更吗？"——在 hanflow 的语义下，`ModelProvider` 是**内部扩展点契约**（供写新 provider 的人实现），不是面向用户的 SDK 签名。即便视为"实现者契约"变更，加方法（非改/删方法）是**纯加法、向后兼容**：现有 provider 不实现 `stream()` 时，由于 Protocol 是 `@runtime_checkable` 且仅做结构子集匹配，不会导致现有实例 `isinstance` 失败；未实现的 provider 调用 `stream()` 会得到明确的 `AttributeError`/`NotImplementedError`（direction 已要求显式占位）。这属于 §6 末尾"纯实现改动（加函数）不需要 ADR"的范畴。

  **综合：第 7 类不触发。**

- **结论: 不需要产 ADR。**
  七类触发条件无一命中。本 cycle 属 CHARTER §6 末段定义的"纯实现改动（加函数/补技术债）"，agent 可在 LOOP 自动流内自主完成，无需人工 Gate。

  附注（不阻断）：direction 文档自身**未声明"本 cycle 不需要 ADR"**——这是 Layer-1 WARN 的合理触发点（提到架构层改动却未做 ADR 必要性判定）。本 Layer-2 审核的职责正是补这个判定，结论为"不需要"。建议 design 阶段开头补一句"本 cycle 经 AUDIT E 类判定无需 ADR（七类触发均不命中）"，把判定固化进设计文档，消除后续 Gate 的歧义。

---

## 建议修订

1. **（轻微，design 阶段补）明确 `node.config.stream` 的承载方式**：建议在设计文档中写死"走 `NodeConfig.__pydantic_extra__`（与现有 `template`/`prompt`/`model`/`role` 同模式），不升格为 NodeConfig 强类型字段"。理由：若升格为显式 Pydantic 字段，则构成 DSL schema 字段变更，会触发 ADR 第 7 类的"DSL schema"分支，需重新评估 ADR 必要性并可能走人工 Gate。守住 extra dict 即可保持本 cycle 全自动。

2. **（轻微，design 阶段补）明确"向上游传播流式事件"的落点**：direction line 30 未说是写入 `NodeState`（累积）还是 emit 到 `RunHandle._queue`（供 `RunEvent(kind="llm_token")` 消费）。`sdk.py:47` 已预留 `llm_token` 事件类型但当前无人 emit——建议 design 阶段定：本 cycle 至少打通 `NodeState` 累积（Executor 层闭环，对应 in scope），`RunHandle` 的 `llm_token` 事件 emit 是否纳入本 cycle 显式声明（若不纳入，归入 out of scope 的"WS/SSE 推送后续 cycle"）。

3. **（轻微，design 阶段补）固化 FakeProvider.stream() 签名迁移**：现状 `FakeProvider.stream()` 返回 `AsyncIterator[str]`（裸字符串），新 Protocol 将要求 `AsyncIterator[StreamChunk]`。验收标准 #8 已提到"对齐"，建议 design 明确这是**破坏性改动**（FakeProvider 的 stream 消费者需同步改），并在测试清单里覆盖。

4. **（轻微，文档习惯）补 ADR 必要性判定语**：design 文档开头加一句"经 AUDIT Layer-2 E 类判定，本 cycle 七类 ADR 触发均不命中，无需产 ADR，走 LOOP 自动流"。把本次审核结论固化，避免后续 Gate 重复质疑。
