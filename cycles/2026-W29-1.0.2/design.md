# Design: LLM 流式输出（Streaming）

- cycle_id: 2026-W29-1.0.2
- target_version: 1.1.0
- 日期: 2026-07-17
- direction: `cycles/2026-W29-1.0.2/direction.md`（Gate 1 已确认）
- P3b AUDIT 结论: 通过（0 严重 / 4 轻微），无需 ADR（`ModelProvider` 不在公开 SDK 导出内，公开流式入口 `RunEvent(kind="llm_token")` 已预留）

> 本设计采纳 P3b 审计的 4 条轻微建议（见各章"审计采纳"标注）。

---

## 架构定位

本改动落在 **L4 models 层**（Protocol + Router + Provider）+ **L2 orchestration 层**（RuntimeContext + LLMExecutor），是 direction 路径 A（Protocol 扩展 + 逐 provider 实现）的落地。

遵循 CHARTER §3 依赖倒置原则：所有改动经 `RuntimeContext(ctx)` 访问 L4，不引入跨层直连。`StreamChunk` 数据模型落在 `core/`（底座），与 `ModelResponse`/`TokenUsage` 并列。

**与现有 `complete()` 对称**：新增平行的 `stream()` 链路，复用 Router 的候选收集/仲裁/trace span 机制，不污染非流式路径。

---

## 组件分解

### 1. `StreamChunk` 数据模型（新增，落 `core/result.py` 或 `models/providers/base.py`）

```python
# 落 hanflow/models/providers/base.py（与 ModelResponse/TokenUsage 并列，provider 层契约）
class StreamChunk(BaseModel):
    delta: str                          # 本次增量文本（可能为空，如纯 usage chunk）
    model_used: str = ""                # 首 chunk 填，后续可空
    provider: str = ""                  # 首 chunk 填
    usage: TokenUsage | None = None     # 仅末尾 chunk 填（中间 chunk 为 None）
    finish_reason: str | None = None    # 仅末尾 chunk 填（stop/length/tool_calls）
    raw: dict[str, Any] | None = None   # 透传 SDK 原 chunk（调试/trace）
```

**审计采纳 #3**：`usage: TokenUsage | None = None`——中间 chunk 无 usage，仅末尾填。与 OpenAI 的 `stream_options={"include_usage": True}`（末尾 chunk 带 usage）对齐。

### 2. `ModelProvider` Protocol 扩展（`models/providers/base.py`）

```python
@runtime_checkable
class ModelProvider(Protocol):
    name: str
    async def complete(self, model: str, messages: list[Any], **kwargs: Any) -> ModelResponse: ...
    async def stream(self, model: str, messages: list[Any], **kwargs: Any) -> AsyncIterator[StreamChunk]: ...
    def estimate_cost(self, model: str, usage: TokenUsage) -> float: ...
    def supported_models(self) -> list[str]: ...
    @property
    def is_local(self) -> bool: ...
```

**关键决策**：`stream` 声明为 `async def`（与 `complete` 一致），返回 `AsyncIterator[StreamChunk]`。Protocol 加方法后，`runtime_checkable` 的 `isinstance` 不破坏现有 provider（stream 是新增，旧 provider 需补实现或占位）。

### 3. `ModelRouter.stream()`（`models/router.py`，镜像 complete）

```python
async def stream(
    self,
    messages: list[Any],
    *,
    role: str | None = None,
    task_type: str | None = None,
    sensitivity: SensitivityLevel = "public",
    prefer: tuple[str, str] | None = None,
    run_budget_remaining: float = 1.0,
    **kwargs: Any,
) -> AsyncIterator[StreamChunk]:
    request = RoutingRequest(messages=..., role=..., ...)
    async with self.trace.span("llm.stream", kind="llm", role=role, task_type=task_type):
        candidates = self._collect_candidates(request)
        chosen = self._arbitrate(candidates, request)
        # fallback 仅在首 token 前允许（见错误处理章）
        async for chunk in self._stream_with_prefetch_fallback(chosen, request, kwargs):
            yield chunk
```

**复用**：`_collect_candidates` / `_arbitrate` / `trace.span` 完全复用 complete 的逻辑。span 名改为 `"llm.stream"`（区分可观测性）。

### 4. `RuntimeContext.stream()` Protocol + 实现

```python
# core/context.py Protocol 新增
async def stream(
    self, messages: list[Any], *, role=None, task_type=None,
    sensitivity="public", prefer: str | None = None, **kwargs: Any,
) -> AsyncIterator[StreamChunk]: ...

# orchestration/context_impl.py 实现（镜像 complete 的 _resolve_named_model）
async def stream(self, messages, *, prefer=None, **kwargs) -> AsyncIterator[StreamChunk]:
    resolved = self._resolve_named_model(prefer) if prefer else None
    async for chunk in self._router.stream(messages, prefer=resolved, **kwargs):
        yield chunk
```

### 5. `LLMExecutor` 流式分支（`orchestration/nodes/leaf.py`）

```python
async def run(self, ctx, node, inputs) -> AtomResult:
    cfg = _cfg(node)
    # ... 现有 template/prompt/messages 构造 ...
    if cfg.get("stream"):                            # 流式分支
        chunks: list[StreamChunk] = []
        content_parts: list[str] = []
        final_usage: TokenUsage | None = None
        async for chunk in ctx.stream(messages, role=role, prefer=prefer, sensitivity=...):
            chunks.append(chunk)
            if chunk.delta:
                content_parts.append(chunk.delta)
                # 实时推送 llm_token 到 RunHandle._queue（经 ctx.emit_run_event，见 §5a）
                await ctx.emit_run_event(RunEvent(
                    kind="llm_token", node_id=node.id, data={"delta": chunk.delta},
                ))
            if chunk.usage is not None:
                final_usage = chunk.usage
        return AtomResult(
            output={"content": "".join(content_parts), "model": chunks[0].model_used if chunks else None,
                    "usage": final_usage, "chunk_count": len(chunks)},
            next_action=NextAction(type="continue"),
        )
    # ... 现有非流式 ctx.complete 分支不变 ...
```

**审计采纳 #1**：`cfg.get("stream")` 走 `__pydantic_extra__`（`_cfg` 已是 `node.config.__pydantic_extra__ or {}`），**不升格为 NodeConfig 强类型字段**——避免触发 CHARTER §6 第 7 类（DSL schema 变更）ADR。

**审计采纳 #2**：流式 token 走 `ctx.emit_run_event(RunEvent(kind="llm_token"))` 直推 RunHandle._queue（见 §5a），**不污染 NodeState.outputs**（只把最终聚合 content 写 AtomResult.output）。这保护了增量 checkpoint 语义。

### 5a. `emit_run_event` 机制（新增，修 P4b 严重 #2 数据流断链）

**问题**：P4b 审核发现 `ctx.event()` 只往 trace span 写（`context_impl.py:148` → `trace.event`），**不推 `RunHandle._queue`**。`llm_token` 全代码库无生产者。要让流式 token 真正到达前端（`RunHandle.stream()` 消费者），需新增直推 queue 的通道。

**方案**：`RuntimeContext` 新增 `emit_run_event(event: RunEvent)` 方法，与现有 `event()`（trace 标记）分离职责：
- `ctx.event(name, **attrs)` —— **保持原语义**，只往 trace span 追加 SpanEvent（可观测性）。
- `ctx.emit_run_event(RunEvent(...))` —— **新增**，直推当前 run 的 `RunHandle._queue`（若 ctx 持有 handle 引用）。

```python
# core/context.py Protocol 新增
async def emit_run_event(self, event: "RunEvent") -> None: ...

# orchestration/context_impl.py 实现
class RuntimeContextImpl:
    def __init__(self, ..., run_handle_queue: asyncio.Queue | None = None):
        self._run_handle_queue = run_handle_queue   # 由 Hanflow.run 注入（sdk.py:183 处已有 queue）

    async def emit_run_event(self, event: RunEvent) -> None:
        if self._run_handle_queue is not None:
            await self._run_handle_queue.put(event)
        # 无 handle（如子 agent / 测试）时静默丢弃——不阻塞流式主路径
```

**注入点**：`Hanflow.run`（sdk.py:160+）构造 RuntimeContextImpl 时，把 `handle._queue` 传入。现有 `handle._queue.put(RunEvent(kind="node_start"...))`（sdk.py:183/197/201）的 node 生命周期事件保持不变；新增的 `llm_token` 由 LLMExecutor 经 `ctx.emit_run_event` 生产。

**审计采纳 #2 更正**：流式 token 经 `ctx.emit_run_event(RunEvent(kind="llm_token"))` 实时推到 RunHandle._queue（**不**经 `ctx.event`，那个只做 trace）；不污染 NodeState.outputs（只把最终聚合 content 写 AtomResult.output）。`ctx.event("llm.stream.chunk", ...)` 仍可用于 trace 可观测性（与 emit_run_event 并行调用，互不冲突）。

### 6. Provider stream 实现

> **修 P4b 严重 #1**：每个 provider 的 stream() **必须**用 try/except 把 SDK 原生异常包装成 HanflowError 子类，否则 Router 的 `except HanflowError`（router.py:121）fallback 不触发，违反 §2 不变量 1。
> **修 P4b 严重 #3**：glm.py 现状 complete() 已用 `await client...`（async），非同步 SDK——stream 也走 async，不做 `asyncio.to_thread`/`list()` 物化（那会丧失流式语义）。

**openai.py**（async SDK 原生支持）：
```python
async def stream(self, model, messages, **kwargs) -> AsyncIterator[StreamChunk]:
    client = AsyncOpenAI(api_key=..., base_url=...)
    try:
        stream = await client.chat.completions.create(
            model=model, messages=messages, stream=True,
            stream_options={"include_usage": True}, **kwargs,
        )
    except AsyncOpenAIError as e:   # SDK 原生异常
        raise ModelTimeoutError(f"openai stream connect failed: {e}", retryable=True) from e
    try:
        async for chunk in stream:
            delta = chunk.choices[0].delta.content if chunk.choices else ""
            if chunk.usage:   # 末尾 chunk
                yield StreamChunk(delta=delta or "", usage=TokenUsage(...),
                                  finish_reason=chunk.choices[0].finish_reason if chunk.choices else None,
                                  raw=chunk.model_dump())
            else:
                yield StreamChunk(delta=delta or "")
    except AsyncOpenAIError as e:   # 流中途失败（首 token 后）
        raise ModelTimeoutError(f"openai stream mid-flight failed: {e}", retryable=False) from e
```

**glm.py**（async SDK——核实 glm.py:38 已用 `await`，stream 同样 async，不物化）：
```python
async def stream(self, model, messages, **kwargs) -> AsyncIterator[StreamChunk]:
    client = ZhipuAI(api_key=...)   # 实测 complete() 已 await，SDK 支持 async create
    try:
        stream = await client.chat.completions.create(
            model=model, messages=messages, stream=True, **kwargs,
        )
    except Exception as e:
        raise ModelTimeoutError(f"glm stream connect failed: {e}", retryable=True) from e
    try:
        async for chunk in stream:   # 直接 async 迭代，不做 list() 物化
            delta = chunk.choices[0].delta.content if chunk.choices else ""
            yield StreamChunk(delta=delta or "", finish_reason=...)
    except Exception as e:
        raise ModelTimeoutError(f"glm stream mid-flight failed: {e}", retryable=False) from e
    # GLM 末尾 usage：P6 实现时核实 SDK 是否随末尾 chunk 返回 usage；
    # 若无，则 usage 留 None（ Router 层用首末 chunk 计时估算 latency_ms 兜底）。
```

> **GLM SDK 事实待 P6 实现时二次确认**：glm.py:38 现状用 `await client.chat.completions.create(...)`，但 ZhipuAI 官方 SDK 的 async 支持版本需核实。若实测发现 glm SDK 流式只返回同步 iterator，则在 provider 内部用 `asyncio.to_thread` 包装**单个 next() 调用**（逐个转换，非 `list()` 物化），保持流式语义。

**占位 provider（anthropic/ollama/deepseek/vllm）**：
```python
async def stream(self, model, messages, **kwargs) -> AsyncIterator[StreamChunk]:
    raise NotImplementedError("stream() for <provider> lands in next cycle (2026-W30+)")
    yield  # never reached，仅为满足 async generator 语法
```

遵循 CHARTER §4：明确标记占位，不静默 no-op。

---

## 接口契约

| 组件 | 方法签名 | 输入 | 输出 |
|---|---|---|---|
| `StreamChunk` | Pydantic 模型 | — | delta/model_used/provider/usage/finish_reason/raw |
| `ModelProvider.stream` | `async def stream(model, messages, **kwargs)` | model 名 + messages | `AsyncIterator[StreamChunk]` |
| `ModelRouter.stream` | `async def stream(messages, *, role, task_type, sensitivity, prefer, ...)` | messages + 路由参数 | `AsyncIterator[StreamChunk]` |
| `RuntimeContext.stream` | `async def stream(messages, *, prefer: str, ...)` | messages + named-model | `AsyncIterator[StreamChunk]` |
| `LLMExecutor.run`（流式分支） | `cfg.get("stream")` 判定 | node + inputs | `AtomResult`（聚合）+ `ctx.emit_run_event(llm_token)` 实时 |

**类型一致性**：`prefer` 在 ctx 层是 `str`（named model），router 层是 `tuple[str,str]`——经 `RuntimeContextImpl._resolve_named_model` 桥接（与 complete 完全一致）。

---

## 数据流

```
LLMExecutor.run (cfg.get("stream") 分支)
  → ctx.stream(messages, prefer="strong")              # RuntimeContext Protocol
  → RuntimeContextImpl.stream                          # _resolve_named_model("strong") → ("openai","gpt-4o")
  → ModelRouter.stream                                 # _collect_candidates + _arbitrate, span("llm.stream")
  → provider.stream("gpt-4o", messages)                # openai/glm async（含 try/except 包装 HanflowError）
  → AsyncIterator[StreamChunk]
     ├─ 每 chunk: ctx.emit_run_event(RunEvent(kind="llm_token", data={delta}))  # 直推 RunHandle._queue（§5a）
     ├─ 每 chunk: ctx.event("llm.stream.chunk", ...)   # 并行：trace 可观测性（span event，不走 queue）
     └─ 末 chunk: 提取 usage
  → 聚合 content + usage → AtomResult.output           # 一次性返回最终结果
  → 上游：RunHandle.stream() 从 _queue 消费 RunEvent(llm_token) → API SSE/WS（runs_ws.py 已通）
```

**实时通道接通（修 P4b 严重 #2）**：`ctx.event()` 只做 trace（不推 queue），无法到达前端。新增 `ctx.emit_run_event()` 直推 `RunHandle._queue`。`RunEvent(kind="llm_token")`（sdk.py:47 已声明，此前无生产者）→ 本 cycle 由 LLMExecutor 经 `emit_run_event` 生产。`RunHandle._queue` + `handle.stream()`（sdk.py:63-74）下行通道已通，无需改消费者。

---

## 错误处理（含 HanflowError）

遵循 CHARTER §2 不变量 1（统一错误层级）：

1. **provider stream 抛错**（网络/超时/鉴权）：包装为 `ModelTimeoutError` / `RateLimitError` / `MCPConnectionError`（hanflow/core/errors.py 已有），带 run_id/node_id。
2. **fallback × stream 冲突的决策**（关键）：
   - iterator **首 token 前**失败 → 允许 fallback 到下一个 provider（与 complete 一致，此时无内容已 yield，可安全重试）。
   - iterator **首 token 后**失败 → **不 fallback**（已 yield 部分内容，重试会重复输出），直接抛 `HanflowError`，由 orchestration 层按 `on_error` 策略处理。
   - 实现：`_stream_with_prefetch_fallback` 先 peek 首 chunk（`anext(iterator)`），首 chunk 成功后才 commit 到外层 yield；首 chunk 失败则走 fallback chain。
3. **budget/限流**：`check_budget` / `acquire_rate_limit` 在 stream 开始前检查（与 complete 一致），超限抛 `HanflowError`。
4. **缓存**：stream 模式**不读缓存**（流式语义不支持返回缓存 ModelResponse），但**可写缓存**（末尾聚合后存完整 ModelResponse 供下次 complete 命中）——design 实现阶段决定是否启用写缓存，默认 v1 不写（简化）。

---

## 测试策略

1. **`StreamChunk` 单测**：Pydantic 字段验证（usage 可空、finish_reason 可空）。
2. **FakeProvider.stream 对齐**：返回类型改 `AsyncIterator[StreamChunk]`（审计采纳 #4），同步更新 `tests/models/test_providers_fake.py`（断言从 `["a","b","c"]` 改为 chunk.delta）。
3. **ModelRouter.stream 单测**：mock provider，验证候选收集/仲裁/span 打点；**首 token 前 fallback** 场景（主 provider 首 chunk 抛错 → 切备用）；**首 token 后不 fallback** 场景（yield 1 个 chunk 后抛错 → 直接失败）。
4. **openai/glm stream 契约测试**：mock SDK（`AsyncOpenAI` / `ZhipuAI`），验证 chunk 解析、末尾 usage 提取、finish_reason。
5. **LLMExecutor 流式分支**：`node.config.stream: true` 时走 ctx.stream，验证 `ctx.emit_run_event(RunEvent(kind="llm_token"))` 被调用、AtomResult.output 聚合正确。
6. **emit_run_event 机制**：RuntimeContextImpl 持有 queue 时直推、无 queue 时静默丢弃（不阻塞）；Hanflow.run 注入 handle._queue 后，RunHandle.stream() 能收到 llm_token 事件。
7. **openai/glm 错误包装**：mock SDK 抛原生异常，验证包装成 ModelTimeoutError（retryable 标志：连接失败=True，中途=False），Router fallback 正确触发。
8. **占位 provider**：`anthropic/ollama/deepseek/vllm` 的 stream() 抛 `NotImplementedError`（断言错误消息含 next cycle 标记）。
9. **回归**：现有 `complete()` 路径所有测试不破（非流式分支不变）。

---

## 前端影响

**无**。本 cycle 只到 Executor 层产出流（`ctx.emit_run_event` + `AtomResult`），不涉及 Web Studio（`web/`）或 API 层的 SSE/WS 端点改动。`RunEvent(kind="llm_token")` 的 API 下行（`api/routes/runs_ws.py`）已存在，本 cycle 只是开始生产事件，不改端点。前端流式 UI 是后续 cycle。

---

## 迁移兼容

1. **`ModelProvider` Protocol 加方法**：`@runtime_checkable` 的 isinstance 不破坏（新方法是加法）。所有现有 provider 需补 stream（2 个真实实现 + 4 个占位 + 1 个 Fake 对齐）。
2. **`complete()` 路径完全不变**：流式是平行新分支，非流式节点行为零变化。
3. **`node.config.stream` 默认 falsy**：现有 LLM 节点（无 stream 配置）走原 complete 分支。新节点显式配 `stream: true` 才走流式。
4. **FakeProvider.stream 返回类型变**：破坏 `test_providers_fake.py` 的 `chunks == ["a","b","c"]` 断言——同步改为 `[c.delta for c in chunks]`。这是唯一破坏性改动，局限在测试。
5. **`RunEvent` 消费者**：`RunHandle.stream()` 已能处理任意 kind 的事件，新增 `llm_token` kind 无需改消费者。

---

## 影响模块汇总（与 charter-check 对应）

| 文件 | 改动 | 预期 charter-check |
|---|---|---|
| `models/providers/base.py` | +StreamChunk, +Protocol.stream | pydantic-data（StreamChunk 用 BaseModel ✓） |
| `models/router.py` | +stream() + _stream_with_prefetch_fallback | async-api（stream 是 IO 动词，async ✓） |
| `models/providers/openai.py` | +stream() 实现（含 HanflowError 包装） | async-api ✓ |
| `models/providers/glm.py` | +stream() 实现（async，含 HanflowError 包装） | async-api ✓ |
| `models/providers/{anthropic,ollama,deepseek,vllm}.py` | +stream() 占位 | async-api（占位也 async def ✓） |
| `models/providers/fake.py` | stream 返回类型改 StreamChunk | — |
| `core/context.py` | +Protocol.stream + +Protocol.emit_run_event | — |
| `orchestration/context_impl.py` | +stream() +emit_run_event()（持有 run_handle_queue） | layering（经 ctx 访问 models ✓） |
| `orchestration/nodes/leaf.py` | +流式分支（emit_run_event 生产 llm_token） | — |
| `sdk.py` | Hanflow.run 构造 ctx 时注入 handle._queue | — |

**本 cycle 预期 P7 charter-check --diff 全绿**：所有改动在合规范围内（async IO、Pydantic、经 ctx、无跨层、Protocol 扩展非公开 SDK 签名）。这验证守护不误报合法改动。
