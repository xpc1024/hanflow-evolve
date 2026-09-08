# Execution Plan — 2026-W37-1.3.0 · MCP remote transport

- **design**: cycles/2026-W37-1.3.0/design.md (Gate2 approved, audit 9/9)
- **branch**: `evolve/2026-W37-1.3.0` (自 main 切出)
- **门**: 每任务 TDD 红→绿;任务完成即 commit(conventional commits,具体文件 add)

## Task DAG

```
T0 branch + uv add mcp
   └→ T1 core/errors (+2 类)                    [独立, 最小]
        └→ T2 transport 重写 (依赖 T1; 红测试先行)
             ├→ T2a _RemoteConnection 骨架 + config 校验 (MCPConfigError)
             ├→ T2b stdio 真实传输 + echo fixture (集成)
             ├→ T2c http/sse 传输 + ws 占位
             └→ T2d ToolDescriptor 适配 + annotations 最小映射 (None 守卫)
                  └→ T3 bus _external 接线 (start/stop/lazy + 隔离)
                       └→ T4 全量门 (ruff/format/mypy strict/pytest)
                            └→ T5 收尾: CHANGELOG + LEARNINGS 销账 + design §9 记账
```

## 任务清单 (原子化)

### T0 — 分支与依赖 (0.5h)
1. `git checkout -b evolve/2026-W37-1.3.0` (hanflow 仓库, base=main@68995b0)
2. `uv add "mcp>=2.2.0,<3"` → pyproject + uv.lock 落盘;`uv sync` 后 import mcp 成功
3. commit: `feat(tools): add mcp sdk v2 dependency (ADR-0008)`

### T1 — 错误类 (0.5h)
1. 红: tests/core/test_errors.py 增 `MCPConfigError`/`ToolExecutionError` 断言
   (code 常量 + retryable=False + isinstance HanflowError)
2. 绿: core/errors.py 按既有模式(类属性覆盖 code/retryable)加 2 类
3. commit: `feat(core): add MCPConfigError + ToolExecutionError (TOOL_EXEC_FAILED)`

### T2a — transport 骨架 + config 校验 (1h)
1. 红: test_transport.py — stdio 无 command / http 无 url / sse 无 url →
   `pytest.raises(MCPConfigError)`;inprocess 缺 builtin / unknown transport →
   `MCPConfigError`(更新既有 2 处断言: ValueError→MCPConfigError)
2. 绿: 重写 `_RemoteConnection`(AsyncExitStack 骨架 + `_validate_config` hook +
   `MCPConfigError` 直抛);四子类校验迁移;工厂错误替换
3. commit: `feat(tools): transport config validation via MCPConfigError + exitstack skeleton`

### T2b — stdio 真实传输 + echo fixture (1.5h)
1. fixture: `tests/tools/mcp_echo_server.py`(mcp SDK server 侧 v2 API,P6 先探查
   `mcp.server` 挂载方式;echo 工具 + 一只带 destructive annotation 的工具供 T2d 用)
2. 红: connect → list_tools ≥2 且 `ToolDescriptor.server == 名字` → call_tool echo
   回显 → close → health False;命令不存在 → `MCPConnectionError` 且 health False
   (更新既有 stdio health 测试)
3. 绿: `_open_transport` stdio 实现(stdio_client + StdioServerParameters)
4. commit: `feat(tools): real stdio transport via mcp sdk (echo fixture integration)`

### T2c — http/sse + ws 占位 (1h)
1. 红: ws connect → NotImplementedError(消息含 protocol 原因);http/sse 缺 url
   已在 T2a;sse 构造 + logger.warning 断言(caplog);http url 连不上 →
   MCPConnectionError(marker=integration 或本地 socket 拒连,取稳定者)
2. 绿: streamable_http_client + create_mcp_http_client(headers, auth→Bearer)/
   sse_client + deprecation warning / WS override connect
3. commit: `feat(tools): http (streamable) + sse transports, websocket explicit placeholder`

### T2d — 适配与映射 (0.5h)
1. 红: list_tools 返回 ToolDescriptor 字段齐(name/server/description/input_schema);
   destructive 工具 annotations=={"destructive": True};无 annotations 工具不炸
   (None 守卫);call_tool is_error=True → ToolExecutionError(echo server 提供
   failing 工具);structured_content 优先、退 content
2. 绿: `_to_descriptor` 适配 + `result.is_error` 分支
3. commit: `feat(tools): ToolDescriptor adaptation + destructive annotation mapping`

### T3 — bus 接线 (1h)
1. 红: test_bus.py — servers 含 stdio echo + 坏 server(command 不存在) + ws
   server(non-lazy): start() 不抛;list_tools 含远端工具;tool_call("ext.echo")
   ok=True;stop() 幂等;lazy=True 的首调冒泡 MCPConnectionError(坏配置)
2. 绿: __init__ 构造 _external + name 回填;start() 隔离捕获
   `except (HanflowError, NotImplementedError)`;stop() 追加关闭;lazy 首连
3. commit: `feat(tools): wire external mcp connections into MCPBus start/stop (Task 2)`

### T4 — 全量门 (1h)
1. `uv run ruff check .` + `uv run ruff format --check .`
2. `uv run mypy --strict hanflow` (114 文件基线 + 本次改动)
3. `uv run pytest -q`(integration/docker marker 默认跳过;记录 skip 数)
4. 失败 → 修复 → 重跑(auto_fix_max_retries=3)
5. commit(如有修复): `fix(tools): gate cleanup`

### T5 — 收尾 (0.5h)
1. hanflow CHANGELOG.md Unreleased→1.3.0 段(feat + minor breaking 注记)
2. hanflow-evolve LEARNINGS:#3/#5/#9 销账(行首 ~~)+ §9 记账入「下次优先」
3. commit(hanflow): `docs(changelog): 1.3.0 minor — mcp remote transport`
   commit(evolve): `cycle(2026-W37-1.3.0): P7 code complete`

## 详细测试计划

| 层 | 用例 | 类型 |
|---|---|---|
| 单元 | 错误类 code/retryable;config 校验 4 路;工厂 2 路;ws 占位消息 | 快,无 IO |
| 契约 | MCPConnection Protocol runtime_checkable 过 build 产物;未连接调用 → MCPConnectionError | 快 |
| 集成 | stdio 真实子进程 echo(增/destructive/failing/无注解 4 工具);close 幂等;命令不存在 | 中,子进程 |
| 集成 | bus: 好+坏+ws 三 server 共存启动;lazy 冒泡;tool_call 端到端 | 中 |
| marker | http/sse 真实 server 链路 | integration,跳过 |

## DoD (完成定义)

- [ ] design T1–T5 全部落地,验收标准 1–6 满足(direction)
- [ ] 全量门 4 件套 0 error 0 warning(mypy strict 含新文件)
- [ ] 新增测试全绿;既有测试仅 2 处**有意**更新(ValueError→MCPConfigError 等),
  其余零改动零回归
- [ ] hanflow 分支单主题提交链,无未关联文件混入(git add 具体文件)
- [ ] evolve 侧 state/artifacts 同步;LEARNINGS 销账完成
