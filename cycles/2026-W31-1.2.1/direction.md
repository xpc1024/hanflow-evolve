# Direction — cycle 2026-W31-1.2.1

- **theme_id**: `clear-preexisting-tech-debt-s0-gates`
- **source**: `human_override`(用户明确要求优先修复遗留技术债)
- **version**: 1.2.0 → **1.2.1**(patch,纯 fix)
- **site_sync_needed**: false(无新特性 / CLI / API 变化)
- **started**: 2026-07-29

## 背景

CI 门(`make ci = lint + typecheck + test`)在 S0 阶段失败。用户指出"失败全在无关的
api/routes 等预存技术债"。本周期目标是**让三道质量门重新变绿**,解除对后续特性开发的阻塞。

## 失败基线(实测,合并 PR #5 之前)

| 门 | 命令 | 结果 | 根因分布 |
|---|---|---|---|
| ruff check | `ruff check .` | ❌ 15 errors | `api/routes/{observe,schema,webhooks,workflows}.py` + `tests/api/{test_schema,test_workflows_phase14}.py`(全预存) |
| ruff format | `ruff format --check .` | ❌ 25 文件 | 含上周期 DOCKER 新写的 `isolation/`、`runtime/build_sandbox.py`、`core/sandbox_contract.py`(提交前漏 format) |
| mypy | `make typecheck` | ❌ 28 errors | 3 类根因(见下) |
| pytest | `make test` | ✅ 411 passed | 已绿 |

## mypy 28 错的 3 类根因(均非误报)

1. **`StreamChunk`/`TokenUsage` 重导出 attr-defined(16 errors)**
   `models/providers/base.py:20` 用 `from hanflow.core.result import StreamChunk, TokenUsage`
   做 back-compat 重导出(因 core 不能依赖 models,故类型定义在 core 再回引),但模块**无
   `__all__`** → mypy strict 不认隐式重导出 → 13 个 provider/router 文件全报 attr-defined。
   **这是真实契约 bug**,影响面最大。

2. **`docker_provisioner.py` 无类型注解(5 errors)**
   `_import_aiodocker()` 缺返回注解 → 3 处 `no-untyped-call`;`aiodocker` 库无 py.typed
   marker → `import-not-found`。上周期(2026-W30-1.1.1)LEARNINGS 记录 mypy 因环境阻塞跑不起来,
   故这些注解缺失当时未暴露。

3. **`api/routes/{workflows,webhooks}.py` 缺泛型/注解(7 errors)**
   `dict` 应为 `dict[str, Any]`,`dry_run`/`_mock_output` 缺返回注解。

## 集成贡献者 PR #5

拉取 main 时合并了 GitHub PR #5(`iajie/evolve/contrib-2026-W31-001`):
给 anthropic/ollama/deepseek/vllm provider 实现 `stream()`。Fast-forward 合入,与本次修复
**几乎不重叠**(本次只动 `base.py` 加 `__all__`,provider 文件本身未改)。合并后引入 6 个新
stream 测试(411 → 417 passed)。

## 方向决策

- **范围**:仅修预存技术债,不引入新功能,不动 DSL/编译器/核心运行时逻辑。
- **手法**:注解补全 + 格式化 + 导入整理 + 导出声明。零行为变更。
- **版本**:patch 1.2.1(纯 fix,无 feat/BREAKING)。
- **验收标准**:`ruff check 0` + `ruff format clean` + `mypy 0` + `pytest 全绿(不回归)`
  + `charter-check GREEN` + `smoke-test 4/4`。
