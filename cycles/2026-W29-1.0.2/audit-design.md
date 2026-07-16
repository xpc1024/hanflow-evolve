# AUDIT — design.md (2026-W29-1.0.2 LLM streaming) — 第 2 轮

> 审核身份：P4b AUDIT Layer-2（fresh context，第 2 轮复核——验证第 1 轮 3 个严重问题的修订是否真正修复）
> 审核对象：`cycles/2026-W29-1.0.2/design.md`（已按第 1 轮意见修订）
> 审核日期：2026-07-15
> 审核基准：`CHARTER.md`（§2 不变量 / §3 依赖矩阵 / §5 禁止模式 / §6 ADR 7 类）、hanflow 源码（`E:/opensource/hanflow/hanflow/`，逐文件交叉核实修订点）

## 审核结论

- 整体: **通过**（可进 P6 code）
- 第 1 轮 3 个严重问题: **全部已修**（逐一验证见下）
- 新引入严重问题: **0**
- 新引入轻微问题: **1**（errors 构造函数不含 retryable kwarg，P6 实现时补；不阻断）
- **ADR 必要性最终结论: 仍无需 ADR**（新增 `emit_run_event` 是内部 ctx 方法非公开 SDK；`StreamChunk` 仍不进 `__all__`）

判定依据：3 个严重全修 + 无新严重 = 通过。唯一新发现是 `retryable` 关键字参数的构造语法瑕疵（轻微，P6 可补，不影响 design 决策正确性）。

源码交叉验证（支撑本轮判定的关键事实，均为本次 fresh 核实）：
- `HanflowError.__init__`（errors.py:28-42）签名仅 `(message, *, run_id, node_id, span_id, details)`——**不含 `retryable` 参数**；`retryable` 是类属性（ModelTimeoutError: `retryable = True`，errors.py:71）✓
- `ModelTimeoutError` / `RateLimitError` / `MCPConnectionError` 复用 errors.py:69-95 既有子类，design 未新增错误类 ✓
- Router fallback `except HanflowError`（router.py:121）属实——provider 层包装成 HanflowError 子类后 fallback 可触发 ✓
- `ctx.event`（context_impl.py:148-149）委托 `trace.event`（trace.py:88-91，只 `sp.events.append(SpanEvent)`，不推 queue）属实——design 新增 `emit_run_event` 是必要修复 ✓
- `RunHandle._queue` 现有生产者全在 sdk.py（line 183/197/201/208/226/227）；构造 RuntimeContextImpl（sdk.py:151-162）**当前不传 queue**——design §5a 说要注入，是合理新增改动 ✓
- `glm.py:38` 现状 `await client.chat.completions.create(...)`（async）属实——design 改 async 迭代正确 ✓
- `openai.py:39` 现状 `await client.chat.completions.create(...)`（async，无 stream）属实 ✓
- `__init__.py` `__all__`（8 符号）不含 `StreamChunk`/`RuntimeContext`/`emit_run_event` ✓

---

## 第 1 轮严重问题逐一验证

### 严重 #1 [A3] 错误包装承诺与伪代码矛盾 —— 已修

**原问题**：§6 openai/glm 伪代码无 try/except，SDK 原生异常逃逸，Router `except HanflowError`（router.py:121）fallback 不触发。

**修订验证（design §6 line 156-205）**：
- **openai.py stream（line 163-183）**：双层 try/except 已补齐。
  - 连接阶段（`await client...create`）包在 try（line 165-170），失败抛 `ModelTimeoutError(..., retryable=True)`（line 171）——retryable=True 合理（连接失败可重试，首 token 前 fallback 允许）。
  - 迭代阶段（`async for chunk in stream`）包在独立 try（line 172-181），中途失败抛 `ModelTimeoutError(..., retryable=False)`（line 182）——retryable=False 合理（首 token 后已 yield 部分内容，重试会重复输出，与错误处理章 #2 line 258-259 的"首 token 后不 fallback"语义一致）。
- **glm.py stream（line 187-203）**：同样双层 try/except（连接 `retryable=True` line 194，中途 `retryable=False` line 200），结构与 openai 对称。
- **包装落点**：明确在 provider `stream()` 内部（与错误处理章 #1 line 256 承诺一致），非 Router 层 `except Exception`。Router `_stream_with_prefetch_fallback` 的 `except HanflowError` 现可正确触发 fallback。与第 1 轮 A3 的矛盾（两处自相矛盾）已消除。
- **retryable 语义合理性**：连接失败 retryable=True（可 fallback/可重试），中途失败 retryable=False（不 fallback，避免重复输出）——逻辑正确，与 errors.py 既有的 retryable 契约（"retryable=True 可自动重试"）方向一致。

**结论：已修。** 包装承诺与伪代码一致，retryable 标志语义合理，Router fallback 链路闭合。

（注：伪代码 `ModelTimeoutError(..., retryable=True/False)` 中 retryable kwarg 的构造语法问题，见下方"新引入轻微问题 #1"，属独立细节，不影响本严重问题的"已修"判定——核心修复目标"补 try/except 包装成 HanflowError 子类"已达成。）

### 严重 #2 [C3] 数据流断链 —— 已修

**原问题**：design 称 `ctx.event("llm_token")` → RunHandle._queue，但 `ctx.event` 只往 trace span 写，不推 queue。llm_token 无生产者。

**修订验证（design §5a line 129-154，line 234-248）**：
- **新机制引入**：`RuntimeContext` Protocol 新增 `emit_run_event(event: RunEvent)`（line 139），与 `ctx.event`（trace 标记）**职责分离**——line 134/154 明确区分两者：`ctx.event` 保持原 trace span 语义不变，`emit_run_event` 专司直推 queue。
- **实现自洽（line 142-150）**：RuntimeContextImpl 持有 `_run_handle_queue`（由 `__init__` 新增参数注入）；`emit_run_event` 实现：有 queue 则 `await self._run_handle_queue.put(event)`，无 queue 静默丢弃（line 146-149）——降级语义正确（子 agent / 测试无 handle 时不阻塞主路径）。
- **注入点正确**：§5a line 152 指明 `Hanflow.run`（sdk.py:160+）构造 RuntimeContextImpl 时传 `handle._queue`。核实 sdk.py:151-162 现状确实未传 queue——是合理新增改动，且 sdk.py 已是 `_queue` 的合法持有者（line 63 创建、183/197/201 生产），注入路径成立。
- **数据流图更新**：line 234-246 已更新为 `ctx.emit_run_event(RunEvent(kind="llm_token"))` 直推 `RunHandle._queue`（line 241），并保留 `ctx.event("llm.stream.chunk")` 作并行 trace（line 242）——两条通道互不冲突，职责清晰。line 248 明确说明 `RunEvent(kind="llm_token")` 由本 cycle 经 `emit_run_event` 生产，`RunHandle.stream()` 消费者（sdk.py:68-74）已通，无需改消费者。
- **executor 生产点（§5 line 111-114）**：LLMExecutor 流式分支内 `await ctx.emit_run_event(RunEvent(kind="llm_token", node_id=node.id, data={"delta": chunk.delta}))`——生产者就位。

**结论：已修。** 数据流闭环成立：LLMExecutor → ctx.emit_run_event → handle._queue → RunHandle.stream()。机制自洽（持有 queue 直推、无 queue 静默丢弃、注入点正确）。第 1 轮 C3 的"断链"与"两可矛盾"均已消除。

### 严重 #3 [D1] glm 同步包装基于错误事实 —— 已修

**原问题**：design 把 glm SDK 当同步处理（`asyncio.to_thread + list()` 物化），但 glm.py:38 已 async。list() 物化丧失流式语义。

**修订验证（design §6 line 185-205）**：
- **改为 async 直接迭代**：line 190 `stream = await client.chat.completions.create(model=..., stream=True, ...)`，line 196 `async for chunk in stream: ...`——**删掉了 `asyncio.to_thread` 和 `list()` 物化**，与 openai 路径（line 166/173）同构。流式语义保留（逐 chunk yield）。
- **事实标注**：line 185 注释"实测 complete() 已 await，SDK 支持 async create"；line 205 明确标注"**GLM SDK 事实待 P6 实现时二次确认**"，并给出降级路径——若实测发现 glm SDK 流式只返回同步 iterator，则在 provider 内部用 `asyncio.to_thread` 包装**单个 next() 调用**（逐个转换，非 list() 物化），保持流式语义。降级方案正确（逐个转换 ≠ 物化整个流）。
- **与现状对齐**：glm.py:38 现状 `await client.chat.completions.create(...)` 属实，design 不再基于"同步 SDK"的错误前提。

**结论：已修。** glm stream 走 async 迭代，不物化；事实前提修正；降级方案合理。第 1 轮 D1 的"基于错误事实的设计错误"已消除。

---

## 新引入问题

### 轻微 #1：`ModelTimeoutError(retryable=...)` 构造语法与 errors.py 契约不符

**发现**：design §6 伪代码四处（line 171/182/194/200）写 `ModelTimeoutError(f"...", retryable=True/False)`。但 `HanflowError.__init__`（errors.py:28-42）签名仅 `(message, *, run_id, node_id, span_id, details)`——**不接受 `retryable` kwarg**。`retryable` 是类属性（ModelTimeoutError 类级 `retryable = True`，errors.py:71）。P6 实现者若照抄伪代码，会抛 `TypeError: __init__() got an unexpected keyword argument 'retryable'`。

**严重度判定：轻微（非严重）**。理由：
1. 核心修复目标（第 1 轮 A3）是"补 try/except 包装成 HanflowError 子类"，伪代码已达成——包装落点、双层 try、fallback 可触发均正确。
2. retryable 的**语义设计**正确（连接失败=True，中途=False），问题仅在"如何把 per-instance 的 retryable 传进去"的实现语法。
3. P6 修正路径清晰且低风险，三选一即可：（a）扩 `HanflowError.__init__` 接受可选 `retryable` 参数（改基类签名，但属内部类、非公开 SDK，不触发 ADR 第 4/7 类）；（b）实例化后赋值 `err.retryable = False`；（c）新增 `StreamMidFlightError(ModelTimeoutError)` 子类（类级 `retryable=False`）。
4. 不阻断 design 决策，可在 P6 实现/PR 阶段修正。

**建议**：design §6 伪代码处补一句注："`retryable` 当前为 HanflowError 类属性（errors.py:71），P6 实现时通过扩 `__init__` 或实例后赋值传入 per-instance retryable；伪代码 `retryable=` 为意图标注。" —— 非强制，P6 实现者读 errors.py 即可发现。

---

## 其他检查（修订是否引入新问题 / 破坏原 pass 项）

- **A 类（架构合规）**：emit_run_event 落 `core/context.py` Protocol + `orchestration/context_impl.py` 实现，经 ctx 访问、不跨层（orchestration→models 仍走 ctx 注入，依赖矩阵不破）。stream() 镜像 complete()，无新违规。runtime_checkable 论证（§2 line 54）措辞虽仍非最精确，但第 1 轮已降为轻微且不阻断。**未破坏 A 类原 pass 项。**
- **B 类（完整性）**：影响模块表（line 298-310）已更新，含 `sdk.py` 注入 queue、`context_impl.py` 加 emit_run_event、`core/context.py` 加两个 Protocol 方法——与修订内容一致，无遗漏。测试策略（line 268-276）新增第 6/7 条覆盖 emit_run_event 机制 + 错误包装，覆盖面充分。**未破坏 B 类原 pass 项。**
- **C 类（自洽）**：emit_run_event 机制自洽——Protocol 加方法（line 139）、ctx 持有 queue（line 143）、有 queue 直推/无 queue 静默丢弃（line 146-149）。`spawn_agent`（context_impl.py:159-179）构造 child ctx 时不传 queue，子 agent 的 emit_run_event 静默丢弃——**正确且自洽**（子 agent 不应向父 run queue 推 token）。RuntimeContext.stream Protocol 签名（§4 line 85-88）仍用 `**kwargs` 吸收 role/task_type/sensitivity（第 1 轮 C1 轻微，未修但不阻断）。**未破坏 C 类原 pass 项。**
- **D 类（复杂度）**：glm 改 async 迭代降低复杂度（删 to_thread+list）。emit_run_event 是最小新增（一个 Protocol 方法 + 一个 ctx 字段），无过度设计。**未破坏 D 类原 pass 项。**
- **E 类（历史 + ADR）**：见下方 ADR 复核。

**结论：修订未破坏原通过的 A/B/C/D/E 各项，未引入新严重问题。**

---

## ADR 必要性复核（第 2 轮）

第 1 轮结论"无需 ADR"。本轮核实**修订（新增 emit_run_event + StreamChunk 仍不进 __all__）是否改变此结论**：

- **第 7 类（公开 API/契约变更）——重点复核新增 emit_run_event**：
  - `emit_run_event` 是否进公开 SDK？**否**。它落 `core/context.py` 的 `RuntimeContext` Protocol（不在 `__init__.py` `__all__`，8 符号核实不含 RuntimeContext/emit_run_event），是内部 ctx 契约（atoms/executors 经它访问），与现有 `ctx.event`/`ctx.complete` 同级，非终端用户签名。✗ 触发。
  - 公开流式入口 `Hanflow.run(stream=)`（sdk.py:114）+ `RunHandle.stream()`（sdk.py:68）+ `RunEvent.kind="llm_token"`（sdk.py:47）**本已预留**，本 cycle 是"接通内部生产者"，非新增公开签名。✗ 触发。
  - `StreamChunk` 是否进 `__all__`？**否**。落 `models/providers/base.py`（line 28 明确），内部扩展点，不进公开导出（`__init__.py` 核实）。✗ 触发。
- **第 4 类（错误基类契约）——复核 retryable 新发现**：轻微 #1 若用方案 (a) 扩 `__init__` 接受 retryable，是给基类加**可选参数**（向后兼容，不破坏现有 code/retryable/run_id/node_id/span_id 契约），且 retryable 仍复用 ModelTimeoutError 既有子类（非新增错误类）。不构成"改错误基类契约"的 ADR 触发——属纯实现补全。✗ 触发。（注：即便 design 现状伪代码用 retryable=，也只是实现层瑕疵，design 决策层未承诺改基类签名。）
- **第 1/2/3/5/6 类**：均不触发（同第 1 轮——14 顶层包不变、依赖矩阵零变化、不换核心依赖、不改 fitness function、不改 CHARTER）。

**结论：仍无需 ADR。** 新增 `emit_run_event` 是内部 ctx 方法（非公开 SDK 签名），`StreamChunk` 仍不进 `__all__`，错误包装复用既有子类。七类触发无一命中。第 1 轮判定经第 2 轮修订核实后**依然成立**。本 cycle 属 §6 末段"纯实现改动（加函数/补技术债）"，可走 LOOP 自动流进 P6。

---

## 最终判定

**通过。**

- 第 1 轮 3 个严重问题（A3 错误包装矛盾 / C3 数据流断链 / D1 glm 同步包装）**全部已修**，证据充分（伪代码 + 数据流图 + 源码交叉核实）。
- 新引入 1 个轻微问题（retryable kwarg 构造语法），P6 实现时修正即可，不阻断。
- 未破坏原通过的 A/B/C/D/E 各项，未引入新严重问题。
- ADR 必要性：**仍无需**。

design 可进 P6（code 实现）。P6 实现时注意：errors.py 的 retryable 传入方式（见轻微 #1），以及 §6 line 205 标注的 GLM SDK async stream 事实二次确认。
