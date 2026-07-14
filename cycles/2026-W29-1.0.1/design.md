# 设计: 补全所有 CLI stub 命令

## 元信息
- 周期: 2026-W29-1.0.1
- direction.md: 已 Gate 1 确认
- 涉及前端: 否 (纯 CLI/后端)

---

## 1. 架构定位

本次改动归入 hanflow 6 层架构的 **L1 Delivery 层** (CLI 入口)。新增一个轻量 HTTP client (`hanflow/cli/client.py`) 属于 L1 的辅助层,不修改 L2-L6。

```
L1 Delivery
  ├── cli/main.py          (修改: 替换 17 个 stub)
  ├── cli/client.py        (新增: HTTP client)
  ├── api/                 (不改)
  └── sdk.py               (可能加 list_tools accessor)
```

设计约束遵循:
- **Protocol-based**: 不引入新继承体系,client 是普通 class
- **HanflowError-only**: client 错误包装为 HanflowError 子类 (CLIConnectionError)
- **全 async def**: HTTP client 用 async,CLI 命令用 `asyncio.run()` 包装 (与现有 `run` 命令一致)

---

## 2. 组件分解

### 组件 A: `hanflow/cli/client.py` (新增)

**职责**: 封装对 hanflow REST API 的 HTTP 调用,处理错误映射。

```python
class CliClient:
    """轻量 HTTP client, 调用 hanflow REST API."""
    
    def __init__(self, base_url: str | None = None):
        # base_url 从 HANFLOW_BASE_URL 环境变量读, 默认 "http://localhost:8000"
        self.base_url = base_url or os.environ.get("HANFLOW_BASE_URL", "http://localhost:8000")
    
    async def list_runs(self) -> list[dict]:
        """GET /api/runs → list of RunSummary dicts."""
    
    async def get_run(self, run_id: str) -> dict:
        """GET /api/runs/{run_id} → RunSummary dict. 404 → raises."""
    
    async def cancel_run(self, run_id: str) -> dict:
        """DELETE /api/runs/{run_id} → {"cancelled": bool}. 404 → raises."""
    
    async def approve(self, run_id: str, decided_by: str, form: dict | None = None) -> dict:
        """POST /api/runs/{run_id}/approve."""
    
    async def edit(self, run_id: str, decided_by: str, edited_value: Any, form: dict | None = None) -> dict:
        """POST /api/runs/{run_id}/edit. 422 if edited_value missing (handled by caller)."""
    
    async def reject(self, run_id: str, decided_by: str, reason: str, form: dict | None = None) -> dict:
        """POST /api/runs/{run_id}/reject."""
    
    async def reroute(self, run_id: str, decided_by: str, reroute_target: str, reason: str | None = None, form: dict | None = None) -> dict:
        """POST /api/runs/{run_id}/reroute."""
    
    async def get_trace(self, run_id: str) -> dict:
        """GET /api/runs/{run_id}/trace."""
    
    async def get_artifacts(self, run_id: str) -> list[dict]:
        """GET /api/runs/{run_id}/artifacts."""
    
    async def stream_logs(self, run_id: str) -> AsyncIterator[dict]:
        """GET /api/runs/{run_id}/stream (WebSocket). yields RunEvent dicts until __done__."""
```

**错误处理**:
- HTTP 404 → `CLIError(f"run not found: {run_id}")` (HanflowError 子类)
- HTTP 409 → `CLIError(f"conflict: {detail}")`
- HTTP 422 → `CLIError(f"validation error: {detail}")`
- 连接失败 → `CLIError(f"cannot connect to {base_url}; is 'hanflow serve' running?")`

**依赖**: httpx (已是 hanflow 依赖,见 pyproject.toml)。WebSocket 用 `httpx` 不直接支持,用标准库或 `websockets`。考虑到 logs 命令的复杂度,简化为:用 httpx 的长连接 SSE-like 轮询不可行(API 是 WS not SSE),所以 logs 用 httpx ws 扩展或降级为 `status` 轮询。

**logs 简化决策**: 本周期 logs 命令用 HTTP 轮询 `GET /api/runs/{run_id}` 每 2 秒一次,直到 status 变为终态 (succeeded/failed/cancelled),打印状态变化。真实 WS 流式留后续周期(需加 websockets 依赖)。这是 YAGNI——先让命令可用。

### 组件 B: `hanflow/cli/main.py` (修改)

**职责**: 替换 17 个 stub 循环为真实 typer 命令。

替换 `main.py:112-138` 的 stub 循环,为每个命令写独立的 `@app.command()` 函数。删除 `_stub` 循环。

### 组件 C: `hanflow/core/errors.py` (修改,最小)

新增一个 CLI 错误类型:

```python
class CLIError(HanflowError):
    """CLI 操作错误 (连接失败/资源不存在/冲突等)."""
    code = "CLI_ERROR"
```

### 组件 D: `hanflow/sdk.py` (修改,最小)

为 `tools` 命令加 public accessor:

```python
class Hanflow:
    # ... 已有代码 ...
    
    async def list_tools(self, server: str | None = None) -> list[dict]:
        """列出可用工具 (public accessor for CLI)."""
        await self._ensure_components()
        tools = await self._bus.list_tools(server)
        return [t.model_dump() for t in tools]
```

---

## 3. 接口契约

### 3.1 CLI 命令签名 (typer)

每个命令的参数、输出格式、错误行为:

#### run 管理 (HTTP client)

```python
@app.command()
def runs(limit: int = typer.Option(20, "--limit", "-n")) -> None:
    """List recent runs."""
    # 输出: 表格格式 run_id | status | workflow_name
    
@app.command()
def status(run_id: str) -> None:
    """Show run status."""
    # 输出: run_id, status, result (if any)

@app.command()
def cancel(run_id: str) -> None:
    """Cancel a run."""
    # 输出: "cancelled: {run_id}" 或错误

@app.command()
def logs(run_id: str, interval: int = typer.Option(2, "--interval")) -> None:
    """Poll run status until terminal (simplified WS replacement)."""
    # 每 interval 秒查询一次, 打印状态变化, 终态时停止

@app.command()
def trace(run_id: str) -> None:
    """Render a run trace."""
    # 输出: trace 数据 (当前为 None, 提示 "trace data limited")
    
@app.command()
def artifacts(run_id: str) -> None:
    """List run artifacts."""
    # 输出: artifact 列表 (id | kind | source_node)
```

#### HITL 审批 (HTTP client)

```python
@app.command()
def approve(run_id: str, decided_by: str = typer.Option("cli", "--by")) -> None:
    """Approve a HITL gate."""
    
@app.command()
def edit(run_id: str, value: str = typer.Option(..., "--value"), decided_by: str = typer.Option("cli", "--by")) -> None:
    """Edit a HITL gate."""
    
@app.command()
def reject(run_id: str, reason: str = typer.Option(..., "--reason"), decided_by: str = typer.Option("cli", "--by")) -> None:
    """Reject a HITL gate."""
    
@app.command()
def reroute(run_id: str, target: str = typer.Option(..., "--target"), reason: str = typer.Option("", "--reason"), decided_by: str = typer.Option("cli", "--by")) -> None:
    """Reroute a HITL gate."""

@app.command()
def resume(run_id: str, decided_by: str = typer.Option("cli", "--by")) -> None:
    """Resume a paused run (alias for approve)."""
```

#### 本地命令 (SDK direct)

```python
@app.command()
def tools(server: str = typer.Option("", "--server", "-s")) -> None:
    """List available tools."""
    # 调用 asyncio.run(Hanflow().list_tools(server or None))

@app.command()
def config_show() -> None:
    """Show resolved config."""
    # 注意: 命令名是 "config", 函数名 config_show 避免 import 冲突
    # 调用 load_config(validate=False), 打印 model_dump_json(indent=2)
```

#### Group B 降级命令

```python
@app.command()
def metrics(run_id: str) -> None:
    """Show run metrics."""
    typer.secho("metrics: aggregation not yet wired (RunResult.usage not populated)", fg=typer.colors.YELLOW)
    # 仍尝试调 get_run, 打印 usage 字段 (全零)

@app.command()
def search(query: str, store: str = typer.Option("", "--store")) -> None:
    """Search a retrieval store."""
    typer.secho("search: retrieval not configured; use 'hanflow index' first (planned)", fg=typer.colors.YELLOW)

@app.command()
def eval() -> None:
    """Evaluate a workflow on a dataset."""
    typer.secho("eval: eval framework not yet implemented (planned)", fg=typer.colors.YELLOW)

@app.command()
def datasets() -> None:
    """List eval datasets."""
    typer.secho("datasets: eval framework not yet implemented (planned)", fg=typer.colors.YELLOW)

@app.command()
def worker() -> None:
    """Start a worker process."""
    typer.secho("worker: multi-worker mode not yet available; use 'hanflow serve' (planned)", fg=typer.colors.YELLOW)
```

### 3.2 HTTP 调用映射

| CLI 命令 | HTTP 方法 + 路径 | 请求体 | 响应 |
|---------|-----------------|--------|------|
| runs | GET /api/runs | - | `list[{run_id, status, result, ...}]` |
| status | GET /api/runs/{id} | - | `{run_id, status, result, ...}` |
| cancel | DELETE /api/runs/{id} | - | `{cancelled: bool}` |
| logs | GET /api/runs/{id} (轮询) | - | `{run_id, status, ...}` |
| trace | GET /api/runs/{id}/trace | - | `{run_id, trace_tree, ...}` |
| artifacts | GET /api/runs/{id}/artifacts | - | `list[{id, kind, ...}]` |
| approve | POST /api/runs/{id}/approve | `{decided_by, form?}` | `{run_id, status: "resumed"}` |
| edit | POST /api/runs/{id}/edit | `{decided_by, edited_value, form?}` | 同上 |
| reject | POST /api/runs/{id}/reject | `{decided_by, reason, form?}` | 同上 |
| reroute | POST /api/runs/{id}/reroute | `{decided_by, reroute_target, reason?, form?}` | 同上 |
| resume | POST /api/runs/{id}/approve | `{decided_by}` | 同上 (approve 别名) |

---

## 4. 数据流

### HTTP 命令流程 (以 `status` 为例)

```
用户: hanflow status abc-123
    │
    ▼
typer 调用 status(run_id="abc-123")
    │
    ▼
client = CliClient()  # 读 HANFLOW_BASE_URL
asyncio.run(client.get_run("abc-123"))
    │
    ▼
httpx.get(f"{base_url}/api/runs/abc-123")
    │
    ├─ 200 → 打印 run_id + status + result
    ├─ 404 → CLIError("run not found: abc-123") → typer.Exit(1)
    └─ 连接失败 → CLIError("cannot connect...") → typer.Exit(1)
```

### 本地命令流程 (以 `tools` 为例)

```
用户: hanflow tools
    │
    ▼
asyncio.run(Hanflow().list_tools())
    │
    ▼
hf._ensure_components() → hf._bus.list_tools()
    │
    ▼
打印表格: name | server | description
```

### logs 轮询流程

```
用户: hanflow logs abc-123
    │
    ▼
loop:
    status = client.get_run("abc-123")
    if status != prev_status: print(f"[{time}] {status}")
    if status in (succeeded, failed, cancelled): break
    sleep(interval)
print("run ended: {status}")
```

---

## 5. 错误处理

遵循 hanflow 的 **HanflowError-only** 异常表面:

```python
# hanflow/core/errors.py 新增
class CLIError(HanflowError):
    code = "CLI_ERROR"
```

CLI 命令的错误处理模式 (统一):

```python
@app.command()
def status(run_id: str) -> None:
    client = CliClient()
    try:
        result = asyncio.run(client.get_run(run_id))
    except CLIError as e:
        typer.secho(f"ERROR: {e}", fg=typer.colors.RED, err=True)
        raise typer.Exit(1)
    typer.secho(f"{result['run_id']}: {result['status']}", fg=typer.colors.CYAN)
```

HTTP 错误码映射:
- 连接拒绝 → `CLIError(f"cannot connect to {base_url}; is 'hanflow serve' running?")`
- 404 → `CLIError(f"run not found: {run_id}")`
- 409 → `CLIError(f"conflict: {detail}")`
- 422 → `CLIError(f"validation: {detail}")` (理论上 CLI 参数已校验,不应到这)
- 其他 5xx → `CLIError(f"server error: {status} {detail}")`

---

## 6. 测试策略

### 单元测试 (pytest + CliRunner)

每个命令至少一个测试,使用 `typer.testing.CliRunner`:

```python
# tests/cli/test_cli.py 扩展

# --- HTTP 命令测试 (mock httpx) ---
def test_runs_command_lists_runs(monkeypatch):
    """mock CliClient.list_runs 返回固定数据, 验证输出格式."""
    
def test_status_command_shows_run(monkeypatch):
    """mock CliClient.get_run, 验证输出."""
    
def test_status_command_404_exits_nonzero(monkeypatch):
    """mock CliClient.get_run raise CLIError, 验证 exit_code=1 + stderr."""

def test_cancel_command(monkeypatch): ...
def test_approve_command(monkeypatch): ...
def test_reject_requires_reason(monkeypatch): ...
def test_edit_requires_value(monkeypatch): ...

# --- 本地命令测试 ---
def test_tools_command(monkeypatch):
    """mock Hanflow.list_tools, 验证输出."""

def test_config_command(monkeypatch):
    """mock load_config, 验证 JSON 输出."""

# --- Group B 降级测试 ---
def test_metrics_shows_not_wired_message(): ...
def test_search_shows_not_configured(): ...
def test_eval_shows_not_implemented(): ...
def test_worker_shows_use_serve(): ...

# --- 边界 ---
def test_all_commands_no_longer_say_delegates_to_sdk():
    """关键回归测试: 17 个命令的输出不含 'delegates to SDK'."""
```

**mock 策略**: 用 `monkeypatch.setattr` 替换 `CliClient` 的方法或 `Hanflow.list_tools`,不启动真实 server。这与现有测试风格一致(现有 `test_cli.py` 不启动 server)。

### 行为化 smoke (scripts/smoke-test.sh)

现有 smoke 已验证 `hanflow` 可 import + DSL 验证 + API app 可构建。本次不扩展 smoke(CLI 命令需要 server 运行,smoke 不启动 server)。

### 回归检查

- 现有 5 个 CLI 测试保持通过
- `test_cli_help_lists_commands` 可能需更新(当前断言不完整,不含新命令)

---

## 7. 前端影响

无。本次纯 CLI/后端改动,不涉及 web/ 目录。

---

## 8. 迁移兼容

- **向后兼容**: 17 个命令的名称和 `--help` 文本不变,只是从"什么都不做"变成"真的工作"或"明确的降级提示"
- **无破坏性变更**: 不修改任何现有 API 端点、SDK 方法、数据模型
- **新依赖**: 无(httpx 已是 hanflow 依赖;logs 用轮询不加 websockets)
- **版本号**: patch (1.0.0 → 1.0.1),符合 direction.md 的 version_impact

---

## 附录: 关键源码位置

| 文件 | 行 | 说明 |
|------|-----|------|
| hanflow/cli/main.py | 112-138 | stub 循环 (将被替换) |
| hanflow/cli/main.py | 25-156 | 已实现的 7 个命令 (不动) |
| hanflow/api/routes/runs.py | 20 | `_runs` registry |
| hanflow/api/routes/runs.py | 64-100 | list/get/cancel 端点 |
| hanflow/api/routes/hitl.py | 52-162 | DecisionBody + 4 个 HITL 端点 |
| hanflow/api/routes/observe.py | 24-39 | trace/artifacts 端点 |
| hanflow/sdk.py | 89+ | Hanflow 类 |
| hanflow/tools/bus.py | 83-92 | list_tools() |
| hanflow/config.py | 96-130 | load_config() |
| hanflow/core/errors.py | - | HanflowError 基类 |
| tests/cli/test_cli.py | - | 现有 5 个测试 |
