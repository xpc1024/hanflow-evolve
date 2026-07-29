# Design — cycle 2026-W31-1.2.1

## 设计原则

所有改动**只动注解 / 格式 / 导入 / 导出声明**,不改运行时逻辑。分四组机械修复:

### A 组:ruff 自动可修(7 个,`--fix` 安全)
- I001 导入排序(`webhooks.py`、`workflows.py`、`test_schema.py`、`test_workflows_phase14.py`)
- F401 删未用 import(`webhooks.py` 的 `publish`、`workflows.py` 的 `os`)— 已确认无引用
- 实现:`ruff check --fix .`

### B 组:手动 lint(8 个,E501/E741/F841)
- `observe.py:26` F841:`result = _get_result(...)` 读后即弃 → 删赋值,保留 `_get_result()`
  调用(不破坏 404 校验副作用)
- `schema.py` / `workflows.py` E501:拆行或提取中间变量(`payload = json.dumps(...)`)
- `test_workflows_phase14.py` E501 + E741(`l` → `line`)

### C 组:ruff format(25 文件)
- `ruff format .` 一次性重排,纯空白/换行。含上周期漏 format 的 isolation/runtime/core 文件。

### D 组:mypy(28 → 0)
1. **`base.py` 重导出修复**:加
   ```python
   __all__ = ["ModelProvider", "ModelResponse", "StreamChunk", "TokenUsage"]
   ```
   → 解决 16 个 attr-defined。这是本周期**唯一涉及契约语义**的改动,但 `__all__` 只显式声明
   已有的重导出意图,不改变实际可导入符号,对运行时零影响。
2. **`docker_provisioner.py`**:
   - `_import_aiodocker() -> tuple[type[Docker], type[DockerError]]` 加返回注解
   - `TYPE_CHECKING` 块声明最小 `Docker`/`DockerError` stub(因 aiodocker 无 py.typed)
   - 配合 `pyproject.toml` 加 `[[tool.mypy.overrides]] module="aiodocker" ignore_missing_imports`
3. **`api/routes/workflows.py`**:
   - `inputs: dict` → `dict[str, Any]`、`_mock_output(node_type, cfg: dict[str, Any]) -> dict[str, Any]`
   - `mock_map: dict[str, Callable[[], dict[str, Any]]]`(消除 `fn()` 返回 object 推断)
   - `dry_run(...) -> StreamingResponse`、`generate() -> AsyncGenerator[str, None]`
4. **`api/routes/webhooks.py`**:`payload: dict` → `dict[str, Any]`

## 层级不变量(charter §2)

- 不新增 `core → isolation` 反向 import(grep 守护)
- `base.py` 的 `StreamChunk/TokenUsage` 仍来自 `core.result`(core 层定义,modesl 层回引),
  本次只加 `__all__` 声明,不改变 import 方向
- charter-check `--diff` GREEN

## 风险评估

- **低**:全部是注解/格式机械修复,无逻辑分支变更
- **唯一语义点**:`observe.py` 删 F841 的 `result` 赋值——但该变量本就未读,调用副作用(404
  校验)完整保留,测试 `test_observe_*` 覆盖
- **回归防护**:pytest 411→417 全绿,charter-check + smoke-test 双重守护
