# Test Report — 2026-W37-1.3.0 · MCP remote transport

- **branch**: `evolve/2026-W37-1.3.0`(hanflow,base main@68995b0)
- **date**: 2026-09-08
- **verdict**: ✅ 全部通过(426 passed / 5 skipped 预期 / 4 门 0 error)

## 1. 全量门(命令与输出摘录)

| 门 | 命令 | 结果 |
|---|---|---|
| Lint | `uv run ruff check .` | `All checks passed!` |
| Format | `uv run ruff format --check .` | `201 files already formatted` |
| Types | `uv run mypy --strict hanflow` | `Success: no issues found in 114 source files` |
| Tests | `uv run pytest -q` | `426 passed, 5 skipped, 1 warning in 15.27s` |

Skip 明细(全部为 marker 预期跳过,非失败):4× docker(无 daemon/镜像)、
1× integration(需 HANFLOW_INTEGRATION=1)。

已知无害 warning:1× `PytestUnraisableExceptionWarning`——mcp SDK stdio 管道在
Windows Proactor loop 下的 GC 时序(unclosed transport `__del__`);所有测试均
显式 `close()` 且断言 `health()=False`,非资源泄漏,属 SDK/anyio 在 Windows 的
解释器关闭时序,不阻断。

## 2. 架构契约守护(增量)

```
bash scripts/charter-check/charter-check.sh --diff
→ registry: OK · errors: OK · pydantic-data: OK · async-api: OK · layering: OK
→ charter-check: exit 0
```

## 3. 行为化 smoke(真跑工作流)

```
bash scripts/smoke-test.sh <evolve_home>
PASS [1/4] hanflow importable
PASS [2/4] DSL validation works
PASS [3/4] static workflow with FakeProvider
PASS [4/4] API app buildable
=== smoke-test: 0 failure(s) ===
```

## 4. 本周期新增测试(关键用例)

- **stdio 真实子进程集成**(`test_stdio_roundtrip_with_real_echo_server`):
  connect → health=True → list_tools(4 工具,ToolDescriptor.server/description/
  input_schema 适配,nuke→destructive 映射,plain→None 守卫)→ call_tool echo
  structured 回显 → boom→ToolExecutionError → close×2 幂等 → health=False →
  后续调用 MCPConnectionError。
- **config 校验契约**:stdio 缺 command / http 缺 url / sse 缺 url →
  MCPConfigError;工厂 inprocess 缺 builtin → MCPConfigError(既有断言
  ValueError 有意更新)。
- **WS 占位**:connect 抛 NotImplementedError(消息含协议原因)。
- **bus 接线**:`test_bus_wires_external_stdio_server`(好 stdio + 坏 command +
  websocket 三 server 共存,start 不抛,list_tools 聚合跳过坏 server,tool_call
  端到端 ok=True);`test_bus_lazy_connect_bubbles_on_first_call`(lazy 首调
  冒泡 HanflowError)。
- **错误类**:code 唯一性 + retryable 标志(test_errors.py 16 用例)。

## 5. 依赖解析实测记录(T0 排障)

- 根因链:`requires-python >=3.11` 无上界 → uv 解析 3.15+ split → zhipuai 无版本;
  zhipuai 全系 pin `pyjwt<2.9.0` 与 mcp 的 `pyjwt[crypto]>=2.10.1` 硬冲突。
- 解法:cap `<3.14` + zhipuai 下界 `>=2.1.5` + `[tool.uv] override-dependencies
  = ["pyjwt[crypto]>=2.10.1"]`(risk 局部 glm extra,ADR-0008/CHANGELOG 注明);
  override 初版丢 crypto extra 导致 `import mcp` 缺 cryptography,补 extra 修复。

## 6. 分支提交链(10 commits,单主题)

```
03b8df3 style(tools): ruff import sort
dbfaebc..feat/fix/test/refactor/docs 链 — 见 git log
e2d3b6f feat(tools): add mcp sdk v2 dependency (ADR-0008)
```

diff --stat(main):10 文件,+840/−770(uv.lock 占大头);运行时代码 3 文件
(transport.py 211+ / bus.py 58+ / errors.py 14+)。

## 7. 自我审查发现并已修复

1. (audit 后自查)`create_mcp_http_client` 试图走公开导入 → mypy attr-defined
   (模块未显式 re-export)→ 回退唯一真实路径 `mcp.shared._httpx_utils`(注释
   注明私有性)。
2. E501 行宽 + import 排序 + `command` None 收窄(assert)——门清理 commit。

## 8. DoD 核对

- [x] design T1–T5 落地,direction 验收 1–6 满足(7 ADR-0008 已落;8/9 属
      release/learn 阶段动作)
- [x] ruff/format/mypy strict/pytest 0 error(mypy 114 文件 0 issue)
- [x] 既有测试仅 2 处有意更新(契约变更),其余零回归(426 passed)
- [x] 提交链单主题、具体文件 add、无产物混入
- [ ] evolve LEARNINGS 销账(本 commit 完成)、BACKLOG Done 追加(release 后)
