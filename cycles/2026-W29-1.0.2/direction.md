# Direction: LLM 流式输出（Streaming）

- cycle_id: 2026-W29-1.0.2
- target_version: 1.1.0
- theme: learnings-priority（聚焦子集：LLM 流式输出）
- 日期: 2026-07-17

## 动机

hanflow 当前 LLM 调用只支持一次性返回（`complete()`），无流式输出。这带来两个问题：

1. **用户体验差**：长回答需等待全部生成完才显示，无逐字/逐 token 流式反馈。
2. **技术债缺口**：`LEARNINGS.md` 下次优先[1] 明确标注"补齐 LLM 流式输出（高优先级技术债 + 用户体验直接改善）"。

经源码探查，现状缺口清晰且边界明确：
- `ModelProvider` Protocol（`hanflow/models/providers/base.py:34`）**只声明 `complete()`，无 `stream()` 抽象**。
- `ModelRouter`（`hanflow/models/router.py:47`）**只暴露 `complete()`**，无流式路由。
- 5 个真实 provider（openai/anthropic/glm/ollama + deepseek/vllm）**全部无 `stream()` 实现**。
- 仅 `FakeProvider`（测试替身）实现了 `stream()`，但它不在 Protocol 契约内（孤岛）。
- `LLMExecutor`（`hanflow/orchestration/nodes/leaf.py:37`）只调 `ctx.complete()`，无流式路径。

本 cycle 目标：**把流式输出做成一等公民**——Protocol 契约、Router 路由、Provider 实现、Executor 调用全链路打通。

## 目标（in scope）

1. **Protocol 契约**：`ModelProvider` 增加 `stream()` 异步生成器方法（`async def stream(...) -> AsyncIterator[StreamChunk]`），定义 `StreamChunk` 数据模型。
2. **Router 路由**：`ModelRouter` 增加 `stream()` 方法，复用现有 fallback/角色路由策略，产出 `AsyncIterator[StreamChunk]`，含 trace span。
3. **ctx 暴露**：`RuntimeContext` 暴露 `stream()`（与现有 `complete()` 对称），供 `LLMExecutor` 调用。
4. **Provider 实现**：至少 **2 个真实 provider** 实现 `stream()`（openai + glm，覆盖一个国际一个国产）；其余 provider（anthropic/ollama/deepseek/vllm）提供 `NotImplementedError` 占位（明确标记，不静默 no-op——遵循 CHARTER §4 编码规范）。
5. **Executor 流式路径**：`LLMExecutor` 支持 `node.config.stream: true` 时走 `ctx.stream()`，把 token 流写入 `NodeState`（累积）+ 向上游传播流式事件。
6. **测试**：FakeProvider 的 `stream()` 对齐新 Protocol；Router/Executor 流式路径单测；openai/glm stream 的契约测试（mock HTTP）。

## 非目标（out of scope）

- **不在本 cycle 做 DOCKER sandbox**（用户明确指定下个 cycle 做，已记入 LEARNINGS 下次优先[1]）。
- **不做 WebSocket 流式推送到 API 层**（`api/routes/*.py` 的 SSE/WS 端点）——本 cycle 只到 Executor 层产出流，API 推送是后续 cycle。
- **不做 Research/Execution 原子的流式**——只做 LLM 叶子节点。
- **不做剩余 4 个 provider（anthropic/ollama/deepseek/vllm）的真实 stream 实现**——只占位，下个 cycle 按需补。
- **不做流式的成本/限流特殊处理**——复用 complete 的 budget/privacy 路由逻辑。

## 实现路径（2 选项 + 推荐）

### 路径 A：Protocol 扩展 + 逐 provider 实现（推荐）

在 `ModelProvider` Protocol 加 `stream()`，Router 加 `stream()`，逐个 provider 实现。FakeProvider 已有 stream 对齐契约。

- **优**：契约清晰、与现有 `complete()` 对称、每个 provider 独立可测、遵循 CHARTER §2.4（DSL→compile→execute 不受影响，纯 L4 models 层扩展）。
- **劣**：需改 Protocol（影响所有 provider），但占位 `NotImplementedError` 让未实现的 provider 不阻塞。

### 路径 B：独立 StreamingProvider Protocol（组合而非扩展）

新建 `StreamingProvider` Protocol，只有支持流式的 provider 实现它；Router 检查 `isinstance` 决定走流式还是降级 complete。

- **优**：不污染基础 Protocol；流式是"可选能力"语义明确。
- **劣**：Router 需类型判断分支、两个 Protocol 维护成本高、与"流式应是一等公民"目标相悖（暗示流式是二等能力）。

### 推荐：路径 A

理由：流式是现代 LLM 调用的基本能力，应进基础 Protocol 而非侧支。路径 A 与现有 `complete()` 对称，最小惊讶。占位策略（`NotImplementedError("...lands in next cycle")`）遵循 CHARTER §4 编码规范，让未实现的 provider 显式失败而非静默。

## 影响模块

| 模块 | 改动 | 触发的 charter-check |
|---|---|---|
| `models/providers/base.py` | 加 `stream()` 到 Protocol + `StreamChunk` 模型 | pydantic-data（StreamChunk 用 BaseModel） |
| `models/router.py` | 加 `stream()` 方法 + trace span | async-api（stream 是 IO 动词，须 async） |
| `models/providers/openai.py` | 实现 `stream()` | async-api |
| `models/providers/glm.py` | 实现 `stream()` | async-api |
| `models/providers/{anthropic,ollama,deepseek,vllm}.py` | 加 `stream()` 占位 NotImplementedError | async-api（占位也须 async def） |
| `core/context.py` | RuntimeContext Protocol 暴露 `stream()` | — |
| `orchestration/context_impl.py` | 实现 `ctx.stream()` 委托 router | layering（context_impl 经 ctx 访问 models，合规） |
| `orchestration/nodes/leaf.py` | LLMExecutor 加流式分支 | — |
| `core/result.py` 或新增 | StreamChunk / 流式事件模型 | pydantic-data |

**关键：本 cycle 预期 charter-check 全绿**——所有改动都在合规范围内（async IO、Pydantic 模型、经 ctx 访问、无跨层）。这正好验证守护不会误报合法改动。

## 风险评估

- **风险低**：纯 L4 models 层 + L2 orchestration 的 Executor 扩展，不动 DSL/编译器/持久化。
- **主要风险**：openai/glm 的 SDK 流式 API 差异（openai 用 `AsyncOpenAI().chat.completions.create(stream=True)`，glm 用 SSE）。需在实现时对齐各自 SDK 的异步迭代器接口。
- **契约风险**：`StreamChunk` 的字段设计（delta 文本 / finish_reason / usage）需与现有 `ModelResponse` 协调，避免两套 usage 语义。design 阶段细化。
- **charter-check 风险**：占位 `NotImplementedError` 的 `stream()` 必须是 `async def`（否则 async-api 检查会 FAIL）——这是守护正确生效的体现，非风险。

## 验收标准

1. `ModelProvider` Protocol 声明 `async def stream(...)`；`StreamChunk` 为 Pydantic BaseModel。
2. `ModelRouter.stream()` 实现，含 fallback + trace span；单测覆盖。
3. `RuntimeContext.stream()` 暴露；`LLMExecutor` 在 `config.stream: true` 时走流式。
4. openai + glm provider 的 `stream()` 实现，契约测试（mock）通过。
5. 其余 4 provider 的 `stream()` 占位 `NotImplementedError`（明确标记 next cycle）。
6. `make ci` 全绿（ruff + mypy --strict + pytest）。
7. **`charter-check --diff` 在 P7 全绿**（本 cycle 改动全部合规，验证守护不误报）。
8. FakeProvider `stream()` 对齐新 Protocol（现有测试不破）。
