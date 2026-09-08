# ADR-0008: 引入 mcp SDK v2 主依赖实现远程工具传输(WebSocket 永久占位)

- 日期: 2026-09-08
- 状态: accepted
- 关联 cycle: 2026-W37-1.3.0
- 相关 fitness function: errors | async | pydantic
- 清零截止: n/a

## 背景 (Context)

`hanflow/tools/transport.py` 自框架早期即声明 5 种传输(stdio/sse/http/websocket/
inprocess),但 `_RemoteConnection` 四个远程子类一直为空壳:`call_tool` 直接
`NotImplementedError`,`list_tools` 恒 `[]`,`_build_client` 探测 SDK 后返回占位
dict——**远程 MCP 工具调用在生产不可用**,且连续 2 个周期为 source_stub 高信号
(LEARNINGS「下次优先」#3)。官方 `mcp` Python SDK 已发布 v2.2.0(2026-07-28 协议
修订线,GA 稳定),stdio / Streamable HTTP / SSE-legacy 三传输均有现成客户端实现,
实现条件成熟(v1→v2 为 major rework:`streamablehttp_client` 改名
`streamable_http_client`、异常体系重组、`McpError` 迁移,已装包逐项实测,见
cycle design §0)。

## 决策驱动因素 (Decision Drivers)

1. 生产可用性(远程工具生态缺口) > 实现自主可控 > 依赖面最小
2. 错误契约稳定(HanflowError-only) — SDK 异常体系 v1→v2 已剧变一次,不可让它穿透边界
3. 维护成本长期分摊(协议演进归官方 SDK)
4. 零 YAML 迁移(TransportKind 与 mcp_servers 结构不变)

## 备选方案 (Considered Options)

1. **方案 A**: 官方 `mcp` SDK v2 全量接入 — stdio + http(Streamable HTTP) + sse
   三传输真实实现,WebSocket 显式占位
2. **方案 B**: 最小 stdio-only — 仅本地子进程传输,http/sse 继续占位
3. **方案 C**: 自研协议层 — 不依赖 SDK,自行实现 MCP JSON-RPC + Streamable HTTP

## 各方案优劣 (Pros/Cons)

### 方案A
- 优: 三传输一次到位(stdio 本地 + http 生产 remote 主路径);协议演进由 SDK 承担;
  会话管理(`mcp-session-id` header / resumption / reconnect)免费获得;与 pydantic
  基建同源
- 劣: 新主依赖 + 传递依赖树(anyio/httpx2/sse-starlette/pywin32 等);SDK v2 较新,
  API 仍有演进风险(锁定 `>=2.2.0,<3` 缓解)

### 方案B
- 优: 改动最小
- 劣: 「remote」名不副实(stdio 为本地子进程),远程工具生态缺口依旧,主题价值打折

### 方案C
- 优: 完全可控,零第三方依赖
- 劣: 重复造轮子;协议每次修订(2025-06/2025-11/2026-07-28 已三版)成本永久自担;
  无用户可见增益

## 决策 (Decision)

选**方案 A**。`mcp>=2.2.0,<3` 进入 `[project].dependencies` **主依赖**(非
optional extra):远程工具调用是 tools 层框架特性,与 pydantic/langgraph 同级承重;
对比 aiodocker 仅服务 DOCKER 沙箱可选档而走 extra。SDK 异常在 transport 边界统一
包装为 HanflowError 子类(MCPConfigError / MCPConnectionError / ToolExecutionError),
不依赖 SDK 异常类型(契约稳定,v1→v2 异常体系剧变即为例证)。

**WebSocket 永久占位**:MCP 协议规范(2026-07-28 及此前各版)未定义 websocket
传输,官方 SDK 亦无 WS 客户端。`TransportKind` 保留 `"websocket"` 字面量(删值属
YAML 配置破坏),`WebSocketConnection.connect()` 显式抛
`NotImplementedError("MCP protocol defines no websocket transport; use http
(Streamable HTTP) or stdio")`(CHARTER §4 占位惯例);`MCPBus.start()` 对其
隔离捕获(`except (HanflowError, NotImplementedError)`),不阻断总线。

## 后果 (Consequences)

- 正面: 远程 MCP 工具调用生产可用(list_tools/call_tool 真实化);bus `_external`
  接线补全(注释中的 "Task 2" 销账);错误契约三场景落地(配置/连接/工具执行)
- 负面: 安装面增大(mcp 及传递依赖);SDK 升级 major 版本时需再过一轮适配评审
- 中性: config/工厂校验错误类型 `ValueError`→`MCPConfigError`(minor breaking,
  CHANGELOG 注明);裸用 transport 的连接失败从静默(health=False)变显式抛出
- 引入的合规豁免: n/a
- 附记(实测结论): v2 会话头 `mcp-session-id` 仍在使用(社区早期"已移除"说法不准),
  resumption/reconnect 由 `streamable_http` transport 自动管理,hanflow 无需干预
