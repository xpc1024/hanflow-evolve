# Design — 2026-W37-1.3.0 · MCP remote transport

- **cycle**: 2026-W37-1.3.0
- **direction**: cycles/2026-W37-1.3.0/direction.md (Gate1 approved)
- **date**: 2026-09-08
- **SDK 探查**: mcp 2.2.0 已装 venv 实测(v2 major rework,API 与 v1 不同,见下)

## 0. SDK v2 实测事实 (P5 装包核实, 设计依据)

| 项 | v2 实测结果 |
|---|---|
| 版本 | `mcp==2.2.0`(PyPI 镜像最新 v2 线;Python 3.13.11 venv 装机成功) |
| stdio | `mcp.client.stdio.stdio_client(server: StdioServerParameters[command/args/env/cwd/...], errlog=stderr)` → async ctx mgr,yield `(read, write)` |
| http | **`mcp.client.streamable_http.streamable_http_client(url, *, http_client=None, terminate_on_close=True)`**(v1 的 `streamablehttp_client` 已改名)→ async ctx mgr,yield `(read, write)` |
| sse | `mcp.client.sse.sse_client(url, headers=None, timeout=5.0, sse_read_timeout=300.0, ..., auth=None)` → async ctx mgr(yield 形状 v1 为三元组,统一按下标取前二) |
| session | `ClientSession(read, write, read_timeout_seconds=None)` async ctx mgr;进入后**必须先 `await initialize()`**;`list_tools()→ListToolsResult(tools=[Tool{name,title?,description,input_schema,output_schema?}])`;`call_tool(name, arguments=...)→CallToolResult{content, structured_content, is_error, ...}`;**无 close 方法**(退出 ctx 即关) |
| 异常 | `McpError` 已不在 `mcp.shared.exceptions`;错误散布 `ErrorData`/`StreamableHTTPError`/`JSONRPCError` 等 → **包装策略不依赖 SDK 异常类型**,统一 `except Exception` 外圈(契约稳定) |
| websocket | v2 无 WS 客户端传输(协议规范亦无)→ 保持占位 |

## 1. 架构定位

改动全部落在 **tools 层**(transport.py + bus.py)与 **core 错误层级**(新增 2 个子类,
CHARTER 统一错误层级 #1 的自然扩展)。不触碰 core→tools 依赖方向(tools 依赖 core,
mcp 为外部第三方依赖,与 pydantic/langgraph 同级)。`MCPConnection` Protocol 五成员
签名**零变更**——本周期把"协议的远程实现"从空壳变为真实,总线与其余层无感。

## 2. 组件分解 (T1–T5)

### T1 core/errors.py — 新增 2 个错误类

```python
class MCPConfigError(HanflowError):      # code="MCP_CONFIG_INVALID", retryable=False
class ToolExecutionError(HanflowError):  # code="TOOL_EXEC_FAILED",    retryable=False
```

复用既有 `MCPConnectionError` (MCP_CONN_FAILED, retryable=True) 承载连接/握手失败。

### T2 hanflow/tools/transport.py — `_RemoteConnection` 真实化

**核心机制: `contextlib.AsyncExitStack` 桥接**。SDK 客户端是两层 async ctx mgr
(transport ctx → ClientSession ctx),而 `MCPConnection` 协议是扁平生命周期;
ExitStack 把"进入"折叠进 `connect()`、"退出"折叠进 `close()`,失败自动回滚半开栈:

```python
class _RemoteConnection:
    def __init__(self, config: MCPServerConfig) -> None:
        self.config = config
        self._stack: AsyncExitStack | None = None
        self._session: Any = None          # mcp ClientSession;SDK 类型经 Any 边界(LEARNINGS 先例)
        self._healthy: bool = False

    async def connect(self, config: MCPServerConfig) -> None:
        self._validate_config()                        # 子类校验 → MCPConfigError (不吞)
        stack = AsyncExitStack()
        try:
            streams = await stack.enter_async_context(self._open_transport())
            read, write = streams[0], streams[1]       # 兼容 sse 可能的三元组
            self._session = await stack.enter_async_context(
                ClientSession(read, write, read_timeout_seconds=self.config.timeout_seconds)
            )
            await self._session.initialize()           # MCP 握手
        except HanflowError:
            await stack.aclose(); raise
        except Exception as exc:
            await stack.aclose()
            self._healthy = False
            raise MCPConnectionError(
                f"mcp {self.transport} connect failed: {exc}",
                details={"transport": self.transport},
            ) from exc
        self._stack = stack; self._healthy = True
```

- `list_tools()`: `session.list_tools()` → 每个 SDK `Tool` 适配为
  `ToolDescriptor(name=t.name, server=self.config.name or "", description=t.description or "",
  input_schema=t.input_schema, output_schema=t.output_schema)`。未连接 → `MCPConnectionError`。
- `call_tool()`: `session.call_tool(name, arguments=args)`;`result.is_error=True` →
  `ToolExecutionError`(消息含工具名 + content 文本摘要);否则返回
  `result.structured_content if not None else result.content`。
- `close()`: `if self._stack: await self._stack.aclose()`;置空;`_healthy=False`(幂等)。
- `health()`: 返回 `_healthy`。

**子类只 override 两个 hook**(`_validate_config` + `_open_transport`):

| 子类 | `_validate_config` | `_open_transport` |
|---|---|---|
| `StdioConnection` | 无 command → `MCPConfigError` | `stdio_client(StdioServerParameters(command, args, env))` |
| `HTTPConnection` | 无 url → `MCPConfigError` | `streamable_http_client(url, http_client=factory(headers) 若有 headers/auth 否则 None)` |
| `SSEConnection` | 无 url → `MCPConfigError` | `logger.warning("sse transport deprecated by MCP spec; prefer http")` 后 `sse_client(url, headers=headers or None)` |
| `WebSocketConnection` | — | **override `connect()` 直接 raise NotImplementedError("MCP protocol defines no websocket transport; use http (Streamable HTTP) or stdio")**(CHARTER §4;override 是因基类 connect 会包装异常,占位须原样抛出) |

**`MCPServerConfig` 增 1 字段** `name: str | None = None`(bus 从 `mcp_servers` dict
的 key 注入;YAML 零变化,default None)。存量 `ValueError`(四传输 + 工厂 inprocess
缺 builtin + unknown transport)全部替换为 `MCPConfigError`。

### T3 hanflow/tools/bus.py — `_external` 接线 (注释中的 "Task 2")

现状 `MCPBus.start()` 是 no-op、`_external` 恒空——transport 再真实也到不了总线。
本任务接线(仅外部连接部分,builtin 路径不动):

- `__init__`: 遍历 `servers` 中 `transport != "inprocess"` 的配置,
  `build_connection(cfg)` 构造连接存 `self._external[name]`,并回填 `cfg.name = name`。
- `start()`: 对每个 external 且 `config.lazy is False` 的执行 `await conn.connect(cfg)`;
  `except HanflowError → logger.warning`(失败隔离:不健康但不阻断其余 server 启动,
  维持 docstring "failures are isolated, never block the bus" 契约)。`lazy=True` 不预连,
  延迟到 `tool_call`/`list_tools` 首次访问时 connect(同 try/except 隔离)。
- `stop()`: 追加 `for conn in self._external.values(): await conn.close()`。
- `tool_call` 重试/destructive 逻辑**零改动**(connection 层已把 SDK 异常翻译为
  HanflowError;`except HanflowError: raise` 透传给 orchestration 的 on_error 策略,
  重试决策正确留在上层——分层不变)。

### T4 pyproject.toml — 依赖

`uv add "mcp>=2.2.0,<3"`(主依赖;取舍理由 ADR-0008 固化)。

### T5 测试 (TDD, 先红后绿)

- **fixture** `tests/tools/mcp_echo_server.py`: 用 mcp SDK server 侧(v2 API,P6 时以
  `import mcp.server...` 实测为准)实现单工具 echo server,`stdio` 方式以
  `command=sys.executable, args=[fixture路径]` 拉起真实子进程。
- `test_transport.py` 扩充:
  - **stdio 集成**(真实子进程,不标 integration——无网络依赖):
    connect → list_tools ≥1 且 ToolDescriptor.server 正确 → call_tool("echo") 回显
    → close → health False;
  - config 缺字段: stdio 无 command / http 无 url / sse 无 url → `MCPConfigError`;
  - WS: `connect()` 抛 `NotImplementedError`(消息含 protocol 原因);
  - 既有 2 处断言更新: inprocess 缺 builtin `ValueError`→`MCPConfigError`;
    stdio 命令不存在 → `pytest.raises(MCPConnectionError)` 且 health False。
- `test_bus.py` 扩充: mcp_servers 含 stdio echo server → `start()` 后
  `list_tools()` 含远端工具、`tool_call("ext.echo", ...)` ok=True、`stop()` 干净退出
  (失败隔离: 配一个坏 server + 一个好 server,`start()` 不抛)。
- http/sse 真实链路: `@pytest.mark.integration`(默认跳过,与 docker marker 同策略)。

## 3. 接口契约 (对外不变 + 内部明确)

| 接口 | 变化 |
|---|---|
| `MCPConnection` Protocol | **零变更**(五成员签名不动) |
| `build_connection(config, *, builtin=None)` | 签名不变;错误类型 ValueError→MCPConfigError |
| `MCPServerConfig` | +`name: str \| None = None`(注入式,非 YAML 字段) |
| `MCPBus.start/stop` | 语义增强:连接/断开 external;签名不变 |
| `TransportKind` | 不变(`"http"` = MCP Streamable HTTP) |

## 4. 数据流

```
YAML mcp_servers: {ext: {transport: stdio, command: python, args: [echo_server.py]}}
  → MCPBus.__init__: build_connection → _external["ext"] (cfg.name="ext" 注入)
  → start(): connect → ExitStack[ stdio_client(ctx) → ClientSession(ctx) → initialize() ]
  → list_tools(): SDK Tool[] → ToolDescriptor(server="ext", ...)
  → tool_call("ext.echo", {msg}): session.call_tool → is_error? ToolExecutionError : structured/content
  → stop(): stack.aclose() → 子进程退出, health=False
失败路径: config 错→MCPConfigError(直抛,非重试);握手/IO 错→MCPConnectionError(retryable)
         远端工具逻辑错→ToolExecutionError(非重试);未预期 SDK 异常→MCPConnectionError 兜底
```

## 5. 错误处理

矩阵中全部异常均为 **`HanflowError` 子类**(CHARTER 统一错误层级 #1:稳定 code +
retryable 标志 + 上下文),SDK 异常不穿透 transport 边界:

| 场景 | 异常 | code | retryable | 抛出层 |
|---|---|---|---|---|
| stdio 无 command / http·sse 无 url / inprocess 缺 builtin / unknown transport | MCPConfigError | MCP_CONFIG_INVALID | ✗ | 工厂+connect |
| 子进程起不来 / URL 连不上 / 握手失败 / IO 断 | MCPConnectionError | MCP_CONN_FAILED | ✓ | connect/call |
| 远端工具 is_error=True | ToolExecutionError | TOOL_EXEC_FAILED | ✗ | call_tool |
| SDK 未预期异常 | MCPConnectionError 兜底 | MCP_CONN_FAILED | ✓ | 外圈 except |

## 6. 测试策略

TDD(P6 每任务红→绿);新增 fixture 为**真实子进程** stdio echo server(非 mock),
Windows/Proactor loop 兼容性由此实测背书;http/sse 走 integration marker 离线跳过;
全量门 = `ruff check` + `ruff format --check` + `mypy --strict` + `pytest`
(marker 默认跳过不计失败)。mcp 2.2.0 自带类型(pydantic 基建),strict 直接可用。

## 7. 前端影响

无(web/ 不在影响面;site 同步仅版本号,release 阶段处理)。

## 8. 迁移兼容

- `TransportKind` 与 YAML `mcp_servers` 结构零变化 → 老配置无感升级。
- 行为增强(非破坏): list_tools `[]`→真实清单;call_tool `NotImplementedError`→真实调用。
- Minor breaking(CHANGELOG 注明): config 校验/工厂错误类型 `ValueError`→`MCPConfigError`
  (均非 HanflowError 子类→调用方 `except ValueError` 需改;仓库内 2 处测试同步更新,
  全仓 grep 无其他捕获点)。
- `mcp` 进入主依赖:安装面 +mcp 及其传递依赖(anyio/httpx2/sse-starlette 等,均为
  主流维护包;Windows 有 pywin32 轮子,本机装机已验证)。
