# LLM 流式输出（Streaming）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 LLM 流式输出做成一等公民——Protocol 契约 → Router 路由 → ctx 暴露 → Executor 调用全链路打通，并接通 RunEvent(llm_token) 实时通道。

**Architecture:** 路径 A（Protocol 扩展 + 逐 provider 实现）。新增 StreamChunk 模型 + ModelProvider/RuntimeContext/ModelRouter 各加 stream() + emit_run_event 直推 RunHandle._queue + openai/glm 实现 + 4 provider 占位。所有改动经 ctx 访问 L4，不跨层。

**Tech Stack:** Python 3.11+ / asyncio / Pydantic v2 / AsyncOpenAI SDK / ZhipuAI SDK / pytest。

**Spec:** `cycles/2026-W29-1.0.2/design.md`（Gate 2 已确认，P4b 两轮审核通过）

**工作目录:** 被改的代码库在 `E:\opensource\hanflow`。commit 到 hanflow 的 feature 分支 `evolve/2026-W29-1.0.2`。

---

## File Structure

### 新增
无新文件——所有改动落在现有文件（StreamChunk 加进 base.py，与 ModelResponse 并列）。

### 修改
| 文件 | 改动 |
|---|---|
| `hanflow/models/providers/base.py` | +StreamChunk 模型；ModelProvider Protocol +stream() |
| `hanflow/models/router.py` | +stream() + _stream_with_prefetch_fallback |
| `hanflow/core/context.py` | RuntimeContext Protocol +stream() +emit_run_event() |
| `hanflow/orchestration/context_impl.py` | +stream() +emit_run_event()（持有 _run_handle_queue） |
| `hanflow/models/providers/openai.py` | +stream() 实现（含 HanflowError 包装） |
| `hanflow/models/providers/glm.py` | +stream() 实现（async，含 HanflowError 包装） |
| `hanflow/models/providers/{anthropic,ollama,deepseek,vllm}.py` | +stream() 占位 NotImplementedError |
| `hanflow/models/providers/fake.py` | stream() 返回类型改 AsyncIterator[StreamChunk] |
| `hanflow/orchestration/nodes/leaf.py` | LLMExecutor +流式分支（emit_run_event 生产 llm_token） |
| `hanflow/sdk.py` | Hanflow.run 构造 ctx 时注入 handle._queue |
| `tests/models/test_providers_fake.py` | stream 断言改 chunk.delta |
| `tests/models/test_router_stream.py` | 新建：Router stream + fallback 测试 |
| `tests/models/test_providers_stream.py` | 新建：openai/glm stream 契约测试 |
| `tests/orchestration/test_llm_executor_stream.py` | 新建：LLMExecutor 流式分支 |

---

## Task DAG（依赖顺序）

```
T1 StreamChunk ──► T2 Protocol.stream ──► T3 Router.stream ──► T4 ctx.stream+emit_run_event
                                          │                    │
                                          ▼                    ▼
                              T5 openai stream ──► T6 LLMExecutor 流式分支 ──► T7 集成+回归
                              T5b glm stream
                              T5c 占位 provider
```

---

## Task 1: StreamChunk 模型 + Protocol.stream 声明

**Files:**
- Modify: `hanflow/models/providers/base.py`
- Test: `tests/models/test_stream_chunk.py`（新建）

- [ ] **Step 1: 写失败测试**

创建 `E:\opensource\hanflow\tests\models\test_stream_chunk.py`：
```python
"""StreamChunk model tests (§design StreamChunk)."""
import pytest
from hanflow.models.providers.base import StreamChunk, TokenUsage


def test_stream_chunk_minimal():
    """中间 chunk：只有 delta，usage/finish_reason 为 None。"""
    c = StreamChunk(delta="hello")
    assert c.delta == "hello"
    assert c.usage is None
    assert c.finish_reason is None


def test_stream_chunk_final():
    """末尾 chunk：带 usage + finish_reason。"""
    u = TokenUsage(input_tokens=10, output_tokens=20, total_tokens=30, cost_usd=0.01, latency_ms=100.0)
    c = StreamChunk(delta="", usage=u, finish_reason="stop")
    assert c.usage == u
    assert c.finish_reason == "stop"


def test_stream_chunk_empty_delta_allowed():
    """空 delta 合法（纯 usage chunk）。"""
    c = StreamChunk(delta="")
    assert c.delta == ""
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /e/opensource/hanflow && python -m pytest tests/models/test_stream_chunk.py -v`
Expected: FAIL — `ImportError: cannot import name 'StreamChunk'`

- [ ] **Step 3: 实现 StreamChunk + Protocol.stream**

读 `hanflow/models/providers/base.py`，在 `ModelResponse` 类定义之后、`ModelProvider` Protocol 之前，加 StreamChunk：
```python
class StreamChunk(BaseModel):
    """One chunk of a streaming LLM response (§design StreamChunk).

    Intermediate chunks carry only `delta`; the final chunk carries `usage` + `finish_reason`.
    """
    delta: str = ""
    model_used: str = ""
    provider: str = ""
    usage: TokenUsage | None = None
    finish_reason: str | None = None
    raw: dict[str, Any] | None = None
```

然后在 `ModelProvider` Protocol 的 `complete` 方法后加 `stream`：
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

确认文件顶部 import 含 `AsyncIterator`（从 typing 或 collections.abc）。若缺，加 `from collections.abc import AsyncIterator`。

- [ ] **Step 4: 运行测试，确认通过**

Run: `python -m pytest tests/models/test_stream_chunk.py -v`
Expected: 3 PASS。

- [ ] **Step 5: 确认现有 provider 仍满足 Protocol（runtime_checkable 不破坏）**

Run: `python -m pytest tests/models/test_providers_fake.py -v`
Expected: 现有测试 PASS（stream 是新增方法，isinstance 不破坏；FakeProvider 已有 stream）。

- [ ] **Step 6: Commit**

```bash
cd /e/opensource/hanflow
git add hanflow/models/providers/base.py tests/models/test_stream_chunk.py
git commit -m "feat(models): add StreamChunk model + ModelProvider.stream protocol"
```

---

## Task 2: ModelProvider Protocol stream 已声明（合并进 Task 1）

> Task 1 Step 3 已把 stream 加进 Protocol。此 Task 仅做验证确认，无独立代码。

- [ ] **Step 1: 确认 Protocol 含 stream**

Run: `cd /e/opensource/hanflow && python -c "from hanflow.models.providers.base import ModelProvider; print('stream' in dir(ModelProvider))"`
Expected: `True`

---

## Task 3: ModelRouter.stream() + 首token前fallback

**Files:**
- Modify: `hanflow/models/router.py`
- Test: `tests/models/test_router_stream.py`（新建）

- [ ] **Step 1: 写失败测试（含 fallback 两场景）**

创建 `E:\opensource\hanflow\tests\models\test_router_stream.py`：
```python
"""ModelRouter.stream tests (§design Router.stream + fallback×stream)."""
import pytest
from hanflow.core.errors import HanflowError, ModelTimeoutError
from hanflow.models.providers.base import StreamChunk, TokenUsage
from hanflow.models.router import ModelRouter
from hanflow.observability.trace import FakeTraceExporter


def _make_router(primary, fallback=None):
    """构造 router：primary provider + 可选 fallback chain。"""
    providers = {"primary": primary}
    if fallback is not None:
        providers["fallback"] = fallback
    # router 构造：providers dict + strategies（含 fallback chain 配置）
    # 查 router.py 实际构造签名对齐；以下为示意，实现时按真实签名调整
    return ModelRouter(
        providers=providers,
        trace=FakeTraceExporter(),
        # ... 其它必要参数按 router.py 现有测试的构造方式 ...
    )


class _FakeProvider:
    """测试用 provider，按 stream_chunks / fail_at 控制行为。"""
    def __init__(self, name, chunks, fail_at=None):
        self.name = name
        self._chunks = chunks  # list[StreamChunk]
        self._fail_at = fail_at  # int：在第 N 个 chunk 前 raise（None=不失败）

    async def stream(self, model, messages, **kwargs):
        for i, c in enumerate(self._chunks):
            if self._fail_at is not None and i == self._fail_at:
                raise ModelTimeoutError(f"{self.name} fail at {i}")
            yield c

    async def complete(self, model, messages, **kwargs):
        raise NotImplementedError


@pytest.mark.asyncio
async def test_stream_basic():
    """正常流式：聚合所有 chunk。"""
    chunks = [StreamChunk(delta="a"), StreamChunk(delta="b", usage=TokenUsage(
        input_tokens=1, output_tokens=2, total_tokens=3, cost_usd=0.0, latency_ms=1.0), finish_reason="stop")]
    router = _make_router(_FakeProvider("primary", chunks))
    out = [c async for c in router.stream([{"role": "user", "content": "hi"}], prefer=("primary", "x"))]
    assert [c.delta for c in out] == ["a", "b"]
    assert out[-1].finish_reason == "stop"


@pytest.mark.asyncio
async def test_stream_fallback_before_first_token():
    """首 token 前失败 → 切 fallback provider（重试成功）。"""
    chunks = [StreamChunk(delta="ok")]
    primary = _FakeProvider("primary", [StreamChunk(delta="x")], fail_at=0)  # 第 0 个前就 fail
    fb = _FakeProvider("fallback", chunks)
    router = _make_router(primary, fb)
    out = [c async for c in router.stream([{"role": "user", "content": "hi"}], prefer=("primary", "x"))]
    assert [c.delta for c in out] == ["ok"]  # 来自 fallback


@pytest.mark.asyncio
async def test_stream_no_fallback_after_first_token():
    """首 token 后失败 → 不 fallback，直接抛 HanflowError。"""
    primary = _FakeProvider("primary", [StreamChunk(delta="a"), StreamChunk(delta="b")], fail_at=1)
    router = _make_router(primary)
    with pytest.raises(HanflowError):
        [c async for c in router.stream([{"role": "user", "content": "hi"}], prefer=("primary", "x"))]
```

> 实现时先读 `tests/models/` 现有 router 测试，对齐 `_make_router` 的真实构造方式（strategies/trace 参数）。

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /e/opensource/hanflow && python -m pytest tests/models/test_router_stream.py -v`
Expected: FAIL — `AttributeError: 'ModelRouter' object has no attribute 'stream'`

- [ ] **Step 3: 实现 Router.stream + _stream_with_prefetch_fallback**

读 `hanflow/models/router.py`，在 `complete` 方法后加：
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
    """Streaming variant of complete (§design Router.stream).

    Fallback only allowed before first token (peek first chunk; if it fails,
    try next provider; once first chunk yielded, no fallback on mid-stream errors).
    """
    from hanflow.models.providers.base import StreamChunk
    request = RoutingRequest(messages=messages, role=role, task_type=task_type,
                             sensitivity=sensitivity, prefer=prefer,
                             run_budget_remaining=run_budget_remaining)
    async with self.trace.span("llm.stream", kind="llm", role=role, task_type=task_type):
        candidates = self._collect_candidates(request)
        chosen = self._arbitrate(candidates, request)
        async for chunk in self._stream_with_prefetch_fallback(chosen, request, kwargs):
            yield chunk

async def _stream_with_prefetch_fallback(
    self, chosen, request, kwargs,
) -> AsyncIterator[StreamChunk]:
    """Peek first chunk; on HanflowError before first yield, try fallback chain."""
    fallback_chain = self._fallback_chain()
    tried = [chosen]
    # 尝试 chosen + fallback，直到首 chunk 成功
    for cand in [chosen] + fallback_chain:
        if cand in tried[:-1] and cand is not chosen:
            continue
        provider = self.providers.get(cand.provider)
        if provider is None:
            continue
        try:
            it = provider.stream(cand.model, request.messages, **kwargs)
            first = await it.__anext__()
        except HanflowError:
            continue  # 首 token 前失败，试下一个
        # 首 chunk 成功，commit 后续（不再 fallback）
        yield first
        async for chunk in it:
            yield chunk
        return
    raise ModelTimeoutError("all providers failed before first stream token", retryable=True)
```

> 注意：`_fallback_chain()` / `_collect_candidates` / `_arbitrate` 是 router 现有方法，复用。实现时读 router.py 确认它们的名字和签名（可能与上面假设略有出入，以源码为准）。`ModelTimeoutError` 的 `retryable` 是类属性（默认 True）；若需中途 False，实例后 `err.retryable = False`（见 P4b 轻微 #1）。

- [ ] **Step 4: 运行测试，确认通过**

Run: `python -m pytest tests/models/test_router_stream.py -v`
Expected: 3 PASS。

- [ ] **Step 5: Commit**

```bash
cd /e/opensource/hanflow
git add hanflow/models/router.py tests/models/test_router_stream.py
git commit -m "feat(models): add ModelRouter.stream with prefetch-fallback (pre-first-token only)"
```

---

## Task 4: RuntimeContext.stream + emit_run_event

**Files:**
- Modify: `hanflow/core/context.py`（Protocol）
- Modify: `hanflow/orchestration/context_impl.py`（实现）
- Test: `tests/orchestration/test_context_stream.py`（新建）

- [ ] **Step 1: 写失败测试**

创建 `E:\opensource\hanflow\tests\orchestration\test_context_stream.py`：
```python
"""RuntimeContext.stream + emit_run_event tests (§design §4/§5a)."""
import asyncio
import pytest
from hanflow.models.providers.base import StreamChunk, TokenUsage
from hanflow.sdk import RunEvent


class _FakeRouter:
    async def stream(self, messages, *, prefer=None, **kwargs):
        yield StreamChunk(delta="a")
        yield StreamChunk(delta="b", usage=TokenUsage(
            input_tokens=1, output_tokens=1, total_tokens=2, cost_usd=0.0, latency_ms=1.0),
            finish_reason="stop")


@pytest.mark.asyncio
async def test_ctx_stream_delegates_to_router():
    """ctx.stream 解析 named model 后委托 router.stream。"""
    from hanflow.orchestration.context_impl import RuntimeContextImpl
    router = _FakeRouter()
    ctx = RuntimeContextImpl(router=router, named_models={"strong": ("primary", "gpt-4o")},
                             trace=__import__("hanflow.observability.trace", fromlist=["FakeTraceExporter"]).FakeTraceExporter())
    out = [c async for c in ctx.stream([{"role": "user", "content": "hi"}], prefer="strong")]
    assert [c.delta for c in out] == ["a", "b"]


@pytest.mark.asyncio
async def test_emit_run_event_pushes_to_queue():
    """emit_run_event 直推 run_handle_queue（有 queue 时）。"""
    from hanflow.orchestration.context_impl import RuntimeContextImpl
    q: asyncio.Queue = asyncio.Queue()
    ctx = RuntimeContextImpl(router=_FakeRouter(), named_models={},
                             trace=__import__("hanflow.observability.trace", fromlist=["FakeTraceExporter"]).FakeTraceExporter(),
                             run_handle_queue=q)
    await ctx.emit_run_event(RunEvent(kind="llm_token", node_id="n1", data={"delta": "x"}))
    ev = q.get_nowait()
    assert ev.kind == "llm_token"
    assert ev.data == {"delta": "x"}


@pytest.mark.asyncio
async def test_emit_run_event_silent_when_no_queue():
    """无 queue（子 agent / 测试）时静默丢弃，不抛错。"""
    from hanflow.orchestration.context_impl import RuntimeContextImpl
    ctx = RuntimeContextImpl(router=_FakeRouter(), named_models={},
                             trace=__import__("hanflow.observability.trace", fromlist=["FakeTraceExporter"]).FakeTraceExporter(),
                             run_handle_queue=None)
    await ctx.emit_run_event(RunEvent(kind="llm_token", node_id="n1", data={}))  # 不抛
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /e/opensource/hanflow && python -m pytest tests/orchestration/test_context_stream.py -v`
Expected: FAIL — `AttributeError: stream` / `emit_run_event`

- [ ] **Step 3: 实现 Protocol（core/context.py）**

读 `hanflow/core/context.py`，在 `complete` 方法声明后加 `stream`，在 `event` 后加 `emit_run_event`：
```python
async def stream(
    self, messages: list[Any], *, role: str | None = None, task_type: str | None = None,
    sensitivity: SensitivityLevel = "public", prefer: str | None = None, **kwargs: Any,
) -> AsyncIterator["StreamChunk"]: ...

# 在 event 方法后加：
async def emit_run_event(self, event: "RunEvent") -> None: ...
```
（用字符串前向引用避免循环 import；或 `from __future__ import annotations` 已开则直接写类型。）

- [ ] **Step 4: 实现 RuntimeContextImpl（context_impl.py）**

读 `hanflow/orchestration/context_impl.py`。在 `__init__` 加参数，在 `complete` 后加 `stream`，在 `event` 后加 `emit_run_event`：
```python
def __init__(self, ..., run_handle_queue: asyncio.Queue | None = None):
    # ... 现有初始化 ...
    self._run_handle_queue = run_handle_queue

async def stream(self, messages, *, prefer=None, **kwargs):
    resolved = self._resolve_named_model(prefer) if prefer else None
    async for chunk in self._router.stream(messages, prefer=resolved, **kwargs):
        yield chunk

async def emit_run_event(self, event) -> None:
    if self._run_handle_queue is not None:
        await self._run_handle_queue.put(event)
    # 无 queue 时静默丢弃
```
确认 `__init__` 现有签名（可能有很多参数），把 `run_handle_queue` 加到末尾带默认 None（不破坏现有调用）。

- [ ] **Step 5: 运行测试，确认通过**

Run: `python -m pytest tests/orchestration/test_context_stream.py -v`
Expected: 3 PASS。

- [ ] **Step 6: Commit**

```bash
cd /e/opensource/hanflow
git add hanflow/core/context.py hanflow/orchestration/context_impl.py tests/orchestration/test_context_stream.py
git commit -m "feat(core): add RuntimeContext.stream + emit_run_event (llm_token push to RunHandle queue)"
```

---

## Task 5: Provider stream 实现（openai + glm + 4 占位 + Fake 对齐）

**Files:**
- Modify: `hanflow/models/providers/openai.py`, `glm.py`, `anthropic.py`, `ollama.py`, `deepseek.py`, `vllm.py`, `fake.py`
- Modify: `tests/models/test_providers_fake.py`
- Test: `tests/models/test_providers_stream.py`（新建）

- [ ] **Step 1: 改 FakeProvider.stream 返回类型 + 更新其测试**

读 `hanflow/models/providers/fake.py`，把现有 `stream` 改为返回 `AsyncIterator[StreamChunk]`：
```python
async def stream(self, model: str, messages: list[Any], **kwargs: Any):
    """Yield StreamChunks (§design StreamChunk alignment)."""
    from hanflow.models.providers.base import StreamChunk
    if self.fail_with is not None:
        raise self.fail_with
    for tok in self.stream_tokens or []:
        yield StreamChunk(delta=tok)
```

读 `tests/models/test_providers_fake.py`，把 stream 断言从 `chunks == ["a","b","c"]` 改为：
```python
chunks = [c async for c in provider.stream("m", [])]
assert [c.delta for c in chunks] == ["a", "b", "c"]
```

- [ ] **Step 2: 写 openai/glm stream 契约测试**

创建 `tests/models/test_providers_stream.py`：
```python
"""openai/glm provider stream contract tests (§design §6, mock SDK)."""
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from hanflow.core.errors import ModelTimeoutError
from hanflow.models.providers.base import StreamChunk


class _FakeDelta:
    def __init__(self, content): self.content = content
class _FakeChoice:
    def __init__(self, delta, finish=None): self.delta = delta; self.finish_reason = finish
class _FakeChunk:
    def __init__(self, choices, usage=None):
        self.choices = choices; self.usage = usage
    def model_dump(self): return {"fake": True}


@pytest.mark.asyncio
async def test_openai_stream_parses_chunks():
    from hanflow.models.providers.openai import OpenAIProvider
    provider = OpenAIProvider(api_key="sk-test")
    # mock AsyncOpenAI().chat.completions.create(stream=True) 返回 async iterator
    fake_chunks = [_FakeChunk([_FakeChoice(_FakeDelta("hel"))]),
                   _FakeChunk([_FakeChoice(_FakeDelta("lo"), finish="stop")])]
    async def _aiter():
        for c in fake_chunks: yield c
    with patch.object(provider, "_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(return_value=_aiter())
        out = [c async for c in provider.stream("gpt-4o", [{"role": "user", "content": "hi"}])]
    assert "".join(c.delta for c in out) == "hello"
    assert out[-1].finish_reason == "stop"


@pytest.mark.asyncio
async def test_openai_stream_wraps_connection_error():
    from hanflow.models.providers.openai import OpenAIProvider
    provider = OpenAIProvider(api_key="sk-test")
    with patch.object(provider, "_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(side_effect=Exception("connect refused"))
        with pytest.raises(ModelTimeoutError):
            [c async for c in provider.stream("gpt-4o", [])]


@pytest.mark.asyncio
async def test_glm_stream_parses_chunks():
    from hanflow.models.providers.glm import GLMProvider
    provider = GLMProvider(api_key="x")
    fake_chunks = [_FakeChunk([_FakeChoice(_FakeDelta("你"))]),
                   _FakeChunk([_FakeChoice(_FakeDelta("好"), finish="stop")])]
    async def _aiter():
        for c in fake_chunks: yield c
    with patch.object(provider, "_client") as mock_client:
        mock_client.chat.completions.create = AsyncMock(return_value=_aiter())
        out = [c async for c in provider.stream("glm-4", [])]
    assert "".join(c.delta for c in out) == "你好"


@pytest.mark.asyncio
@pytest.mark.parametrize("modname", ["anthropic", "ollama", "deepseek", "vllm"])
async def test_placeholder_providers_raise_not_implemented(modname):
    import importlib
    mod = importlib.import_module(f"hanflow.models.providers.{modname}")
    # 找 provider 类（每个文件有一个主类）
    cls = next(v for k, v in vars(mod).items() if isinstance(v, type) and "Provider" in k)
    provider = cls(api_key="x") if "api_key" in cls.__init__.__code__.co_varnames else cls()
    with pytest.raises(NotImplementedError):
        [c async for c in provider.stream("m", [])]
```

> 实现时先读 openai.py/glm.py 现有 complete() 确认 client 字段名（`_client` vs 别的）和构造方式，调整 mock。

- [ ] **Step 3: 运行测试，确认失败**

Run: `cd /e/opensource/hanflow && python -m pytest tests/models/test_providers_stream.py tests/models/test_providers_fake.py -v`
Expected: FAIL（stream 未实现 / Fake 断言旧）。

- [ ] **Step 4: 实现 openai.stream + glm.stream（含 HanflowError 包装）**

读 `openai.py`，在 `complete` 后加（按 design §6 伪代码，含 try/except）：
```python
async def stream(self, model: str, messages: list[Any], **kwargs: Any):
    """Stream chunks (§design §6 openai). Wraps SDK errors as ModelTimeoutError."""
    from hanflow.core.errors import ModelTimeoutError
    from hanflow.models.providers.base import StreamChunk, TokenUsage
    try:
        s = await self._client.chat.completions.create(
            model=model, messages=messages, stream=True,
            stream_options={"include_usage": True}, **kwargs,
        )
    except Exception as e:
        raise ModelTimeoutError(f"openai stream connect failed: {e}") from e  # retryable=True (类属性默认)
    try:
        async for chunk in s:
            delta = chunk.choices[0].delta.content if chunk.choices else ""
            if getattr(chunk, "usage", None):
                yield StreamChunk(delta=delta or "", usage=TokenUsage(
                    input_tokens=chunk.usage.prompt_tokens, output_tokens=chunk.usage.completion_tokens,
                    total_tokens=chunk.usage.total_tokens, cost_usd=0.0, latency_ms=0.0),
                    finish_reason=chunk.choices[0].finish_reason if chunk.choices else None,
                    raw=chunk.model_dump())
            else:
                yield StreamChunk(delta=delta or "")
    except Exception as e:
        err = ModelTimeoutError(f"openai stream mid-flight failed: {e}")
        err.retryable = False  # 中途失败不重试（见 P4b 轻微 #1）
        raise err from e
```

读 `glm.py`，加对称的 stream（按 design §6 glm 伪代码，async 直接迭代，含 try/except；GLM usage 字段名 P6 实测核实，先按 openai 类比，若不同再调）。

- [ ] **Step 5: 实现 4 个占位 provider 的 stream**

对 `anthropic.py`/`ollama.py`/`deepseek.py`/`vllm.py` 各加：
```python
async def stream(self, model: str, messages: list[Any], **kwargs: Any):
    raise NotImplementedError("stream() for <provider> lands in next cycle (2026-W30+)")
    yield  # pragma: no cover — 满足 async generator 签名
```

- [ ] **Step 6: 运行测试，确认全通过**

Run: `python -m pytest tests/models/test_providers_stream.py tests/models/test_providers_fake.py -v`
Expected: 全 PASS。

- [ ] **Step 7: Commit**

```bash
cd /e/opensource/hanflow
git add hanflow/models/providers/*.py tests/models/test_providers_stream.py tests/models/test_providers_fake.py
git commit -m "feat(models): implement provider.stream (openai+glm real, 4 placeholders, fake aligned)"
```

---

## Task 6: LLMExecutor 流式分支 + Hanflow.run 注入 queue

**Files:**
- Modify: `hanflow/orchestration/nodes/leaf.py`
- Modify: `hanflow/sdk.py`（Hanflow.run 构造 ctx 时传 run_handle_queue）
- Test: `tests/orchestration/test_llm_executor_stream.py`（新建）

- [ ] **Step 1: 写失败测试**

创建 `E:\opensource\hanflow\tests\orchestration\test_llm_executor_stream.py`：
```python
"""LLMExecutor streaming branch tests (§design §5)."""
import pytest
from hanflow.core.dsl import WorkflowNode
from hanflow.orchestration.nodes.leaf import LLMExecutor
from hanflow.models.providers.base import StreamChunk, TokenUsage
from hanflow.sdk import RunEvent


class _StreamCtx:
    """Fake ctx：记录 emit_run_event 调用，stream 返回固定 chunks。"""
    def __init__(self, chunks):
        self._chunks = chunks
        self.events = []
    async def stream(self, messages, **kwargs):
        for c in self._chunks: yield c
    async def emit_run_event(self, event):
        self.events.append(event)


@pytest.mark.asyncio
async def test_llm_stream_branch_emits_tokens_and_aggregates():
    chunks = [StreamChunk(delta="hel"), StreamChunk(delta="lo",
               usage=TokenUsage(input_tokens=1, output_tokens=1, total_tokens=2,
                                 cost_usd=0.0, latency_ms=1.0), finish_reason="stop")]
    ctx = _StreamCtx(chunks)
    node = WorkflowNode(id="n1", type="LLM",
                        config={"prompt": "hi", "stream": True, "model": "strong"})
    result = await LLMExecutor().run(ctx, node, {})
    assert result.output["content"] == "hello"
    assert len(ctx.events) == 2  # 两个 delta 各一个 llm_token
    assert all(e.kind == "llm_token" for e in ctx.events)
    assert ctx.events[0].data["delta"] == "hel"


@pytest.mark.asyncio
async def test_llm_non_stream_branch_unchanged():
    """无 stream 配置 → 走原 complete 分支（不走 stream）。"""
    class _CompleteCtx:
        async def complete(self, messages, **kwargs):
            from hanflow.models.providers.base import ModelResponse, TokenUsage
            return ModelResponse(content="full", usage=TokenUsage(
                input_tokens=1, output_tokens=1, total_tokens=2, cost_usd=0.0, latency_ms=1.0),
                model_used="m", provider="p")
    ctx = _CompleteCtx()
    node = WorkflowNode(id="n2", type="LLM", config={"prompt": "hi"})
    result = await LLMExecutor().run(ctx, node, {})
    assert result.output["content"] == "full"
```

> 读 `WorkflowNode` / `NodeConfig` 现有构造方式，对齐 `config=` 字段名（可能是 `config` 或别的）。

- [ ] **Step 2: 运行测试，确认失败**

Run: `cd /e/opensource/hanflow && python -m pytest tests/orchestration/test_llm_executor_stream.py -v`
Expected: FAIL。

- [ ] **Step 3: 实现 LLMExecutor 流式分支**

读 `hanflow/orchestration/nodes/leaf.py`，在 `run` 方法里加 `cfg.get("stream")` 分支（按 design §5 伪代码，含 emit_run_event）：
```python
async def run(self, ctx, node, inputs):
    cfg = _cfg(node)
    template = cfg.get("template") or cfg.get("prompt", "")
    prompt = interpolate(template, inputs)
    messages = [{"role": "user", "content": prompt}]
    prefer = cfg.get("model")
    role = cfg.get("role")
    if cfg.get("stream"):                            # 流式分支
        from hanflow.sdk import RunEvent
        content_parts, final_usage, first_model = [], None, None
        async for chunk in ctx.stream(messages, role=role, prefer=prefer, sensitivity=node.sensitivity):
            if chunk.delta:
                content_parts.append(chunk.delta)
                await ctx.emit_run_event(RunEvent(kind="llm_token", node_id=node.id, data={"delta": chunk.delta}))
            if chunk.usage is not None:
                final_usage = chunk.usage
            if chunk.model_used and not first_model:
                first_model = chunk.model_used
        return AtomResult(
            output={"content": "".join(content_parts), "model": first_model,
                    "usage": final_usage, "chunk_count": len(content_parts)},
            next_action=NextAction(type="continue"),
        )
    # ... 原有 ctx.complete 非流式分支不变 ...
    resp = await ctx.complete(messages, role=role, prefer=prefer, sensitivity=node.sensitivity)
    return AtomResult(output={"content": resp.content, "model": getattr(resp, "model_used", None)},
                      next_action=NextAction(type="continue"))
```

- [ ] **Step 4: Hanflow.run 注入 run_handle_queue**

读 `hanflow/sdk.py`，找 `Hanflow.run` 里构造 `RuntimeContextImpl` 的位置（约 L160+），加 `run_handle_queue=handle._queue`：
```python
ctx = RuntimeContextImpl(..., run_handle_queue=handle._queue)
```
（现有 node_start/node_end 事件仍由 sdk.py 直接 put，不冲突；llm_token 经 ctx.emit_run_event 走同一 queue。）

- [ ] **Step 5: 运行测试，确认通过**

Run: `python -m pytest tests/orchestration/test_llm_executor_stream.py -v`
Expected: 2 PASS。

- [ ] **Step 6: Commit**

```bash
cd /e/opensource/hanflow
git add hanflow/orchestration/nodes/leaf.py hanflow/sdk.py tests/orchestration/test_llm_executor_stream.py
git commit -m "feat(orchestration): LLMExecutor streaming branch + wire run_handle_queue in Hanflow.run"
```

---

## Task 7: 集成回归 + make ci

**Files:** 无新代码，全量回归。

- [ ] **Step 1: 跑 make ci（ruff + mypy --strict + pytest）**

Run: `cd /e/opensource/hanflow && make ci`
Expected: 全绿。若有 mypy 类型错误（如 AsyncIterator 注解、Protocol 方法签名），逐个修。

- [ ] **Step 2: 跑 charter-check --diff（关键验证！本 cycle 改动应全合规）**

```bash
cd /e/opensource/hanflow-evolve
bash scripts/charter-check/charter-check.sh --diff
```
Expected: exit 0（本 cycle 改动全部合规：async IO、Pydantic、经 ctx、无跨层）。**这是 charter-check 守护的核心验证——合法改动不被误报。** 若 FAIL，按输出修（可能是占位 provider 的 stream 不是 async def、或某处直连跨层 import）。

- [ ] **Step 3: 回归测试汇总**

Run: `cd /e/opensource/hanflow && python -m pytest tests/ -q`
Expected: 全绿，无回归（现有 complete 路径不破）。

- [ ] **Step 4: 最终 Commit（若有 lint/type 修复）**

```bash
git status
# 若有未提交修复：
git add -A && git commit -m "chore: ci green + charter-check --diff passes for streaming cycle"
```

---

## 完成定义（DoD）

1. ✅ `ModelProvider` Protocol 声明 `async def stream()`；`StreamChunk` 为 Pydantic BaseModel。
2. ✅ `ModelRouter.stream()` 实现，含首token前fallback；单测覆盖（basic + fallback 两场景）。
3. ✅ `RuntimeContext.stream()` + `emit_run_event()` 暴露；单测覆盖。
4. ✅ openai + glm provider 的 `stream()` 实现（含 HanflowError 包装），契约测试（mock）通过。
5. ✅ 其余 4 provider 的 `stream()` 占位 `NotImplementedError`（明确标记 next cycle）。
6. ✅ `LLMExecutor` 在 `config.stream: true` 时走流式，emit llm_token，聚合 AtomResult。
7. ✅ `Hanflow.run` 注入 handle._queue，RunHandle.stream() 能收到 llm_token。
8. ✅ FakeProvider.stream 返回 StreamChunk，现有测试同步更新。
9. ✅ `make ci` 全绿（ruff + mypy --strict + pytest）。
10. ✅ **`charter-check --diff` 全绿**（本 cycle 改动全部合规，验证守护不误报合法改动）。

---

## Spec Coverage 自检

| design 章节 | 任务 |
|---|---|
| StreamChunk 模型 | T1 |
| Protocol.stream 声明 | T1/T2 |
| Router.stream + prefetch-fallback | T3 |
| RuntimeContext.stream + emit_run_event | T4 |
| LLMExecutor 流式分支 | T6 |
| openai/glm stream 实现（含错误包装） | T5 |
| 4 占位 provider | T5 |
| FakeProvider 对齐 | T5 |
| Hanflow.run 注入 queue | T6 |
| 错误处理（首token前/后 fallback） | T3 |
| 数据流（emit_run_event → queue） | T4/T6 |
| 测试策略（9 项） | T1/T3/T4/T5/T6 |
| charter-check --diff 验证 | T7 |

全部 design 章节有对应任务，无遗漏。
