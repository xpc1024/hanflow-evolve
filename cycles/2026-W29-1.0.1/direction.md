# 迭代方向: 补全所有 CLI stub 命令

## 元信息
- 周期: 2026-W29
- 目标版本: 1.0.1 (patch — bugfix/stub 补全,无新 API)
- BACKLOG 主题 ID: T-cli-completion
- 主题分数: 35 (human_override)
- source: human_override (开发者预设)

## 动机

hanflow CLI (`hanflow/cli/main.py`) 有 17 个命令仍是 `delegates to SDK` 黄色 stub —— 它们只打印一行提示,什么都不做。这严重影响了 CLI 的可用性:用户无法通过命令行管理 run、审批 HITL、查看 trace/artifacts。

这些命令对应的 REST API 端点大多已实现 (`api/routes/runs.py`、`hitl.py`、`observe.py`),只是 CLI 没有调用它们。本周期把这 17 个 stub 全部变成真实可用的命令。

信号来源: 1 个 `cli_stub` 信号 (`hanflow/cli/main.py:136`) + LEARNINGS "高优先级债: ~17 个 CLI 命令是 stub"。

## 目标 (in scope)

将 17 个 stub 命令分为两组处理:

### Group A — 真实实现 (12 个命令, SDK/API ready)

这些命令的 REST API 已存在,CLI 通过 HTTP client 调用即可:

| 命令 | API 端点 | 说明 |
|------|---------|------|
| `runs` | `GET /api/runs` | 列出最近 runs |
| `status <run_id>` | `GET /api/runs/{id}` | 查看 run 状态 |
| `cancel <run_id>` | `DELETE /api/runs/{id}` | 取消 run |
| `logs <run_id>` | `GET /api/runs/{id}/stream` (WS) | 流式查看 run 日志 |
| `trace <run_id>` | `GET /api/runs/{id}/trace` | 查看 run trace (注意: trace_tree 当前为 None, 命令仍实现但提示数据有限) |
| `artifacts <run_id>` | `GET /api/runs/{id}/artifacts` | 列出 run artifacts |
| `approve <run_id>` | `POST /api/runs/{id}/approve` | 审批 HITL |
| `edit <run_id>` | `POST /api/runs/{id}/edit` | 编辑 HITL (需 --value) |
| `reject <run_id>` | `POST /api/runs/{id}/reject` | 拒绝 HITL (需 --reason) |
| `reroute <run_id>` | `POST /api/runs/{id}/reroute` | 重路由 HITL (需 --target) |
| `resume <run_id>` | POST approve (generic) | resume 作为 approve 的别名/快捷方式 |

**本地命令 (不需要 server, 直接调 SDK):**

| 命令 | SDK 方法 | 说明 |
|------|---------|------|
| `tools` | `MCPBus.list_tools()` | 列出可用工具 (需加 public accessor) |
| `config` | `load_config()` | 显示解析后的配置 |

### Group B — 优雅降级 (5 个命令, SDK 也 stub)

这些命令的后端尚未实现。CLI 命令存在但输出明确的"尚未支持"信息:

| 命令 | 状态 | CLI 行为 |
|------|------|---------|
| `metrics` | RunResult.usage 未填充 | 打印 usage 字段(全零)+ 提示"metrics aggregation not wired" |
| `search` | SearchProvider 未接入 Hanflow | 提示"retrieval not configured; use `hanflow index` first" |
| `eval` | 完全无后端 | 提示"eval framework not yet implemented (planned)" |
| `datasets` | 完全无后端 | 同上 |
| `worker` | 多 worker 是 Phase 17 延迟项 | 提示"multi-worker mode not yet available; use `hanflow serve`" |

## 非目标 (out of scope)

- **不实现 Group B 的后端**: metrics aggregation / search wiring / eval framework / worker process 各自是独立大主题,留后续周期
- **不重构 CLI 为单独子命令包**: 保持单文件 `main.py`,只替换 stub 循环为真实实现
- **不加 `--base-url` 全局选项的完整配置体系**: 用环境变量 `HANFLOW_BASE_URL` (默认 `http://localhost:8000`),简单够用
- **不动 `serve` / `validate` / `compile` / `run` / `new` / `doctor` / `index`**: 这 7 个已实现,不改

## 实现路径 (推荐方案)

**方案 A (推荐): HTTP client + 本地 SDK 混合**

- 新增 `hanflow/cli/client.py`: 轻量 HTTP client (用 httpx,已是 hanflow 依赖),封装对 REST API 的调用
- `--base-url` 从 `HANFLOW_BASE_URL` 环境变量读 (默认 `http://localhost:8000`)
- run 管理/HITL/observe 类命令 → HTTP client (需要 server 运行)
- tools/config → 本地 SDK (不需要 server)
- Group B → 优雅降级提示

**方案 B: 全部本地 SDK** — 不现实,因为 CLI 进程和 server 进程独立,in-process registry 无法跨进程访问。

## 影响模块

- `hanflow/cli/main.py` — 替换 stub 循环为真实命令实现
- `hanflow/cli/client.py` — **新增**, HTTP client
- `hanflow/sdk.py` — 可能需加 `list_tools()` public accessor (若 `_bus` 不便暴露)
- `tests/cli/test_cli.py` — 为每个命令加测试

## 风险评估

| 风险 | 等级 | 缓解 |
|------|------|------|
| httpx 调用 server 需 server 运行 | 低 | 测试用 pytest fixture 启动 test server 或 mock |
| logs 命令需 WebSocket client | 中 | 用 httpx 的 ws 支持或 websockets 库;若复杂可降级为轮询 GET status |
| trace 数据为 None (后端 stub) | 低 | 命令实现但提示"trace data limited; wire LocalTraceProvider in future" |
| Group B 用户期望 | 低 | 明确的"not yet supported"消息,不误导 |

**整体风险: 低** — 都是调用已有 API,无架构变更,无破坏性改动。

## 验收标准

- [ ] 17 个 stub 全部替换为真实实现或明确的降级提示
- [ ] Group A 的 12 个命令有对应测试 (调用 mock HTTP 或 test server)
- [ ] `make ci` (lint + mypy strict + pytest) 全绿
- [ ] `hanflow runs` / `hanflow status <id>` / `hanflow approve <id>` 等命令可对运行中的 server 工作
- [ ] Group B 5 个命令输出清晰的 "not yet supported" 而非 "delegates to SDK"
- [ ] 无新增 TODO/stub (除 Group B 的明确降级提示)
- [ ] smoke-test.sh 通过
