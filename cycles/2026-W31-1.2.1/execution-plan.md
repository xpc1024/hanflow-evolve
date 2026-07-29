# Execution Plan — cycle 2026-W31-1.2.1

> 本周期为"实现先行"模式:修复在确认方向前已完成并验证。本文件事后记录实际执行的步骤序列。

## 执行序列(全部 ✅ 已完成)

### Step 0:基线确认
- [x] `ruff check .` → 15 errors(全在 api/routes + tests/api)
- [x] `ruff format --check .` → 25 文件
- [x] `mypy hanflow` → 28 errors
- [x] `pytest -q` → 411 passed(已绿)

### Step 1:集成贡献者 PR #5
- [x] `git stash`(暂存本地修复)
- [x] `git fetch github && git merge github/main`(Fast-forward,无冲突)
- [x] `git stash pop`(恢复修复)
- [x] 合并后重测:pytest 417 passed(PR #5 新增 6 个 stream 测试)

### Step 2:A 组 — ruff check --fix(7 个自动修)
- [x] `ruff check --fix .` → 7 fixed(I001/F401)
- [x] 影响:`webhooks.py`、`workflows.py`、`test_schema.py`、`test_workflows_phase14.py`

### Step 3:B 组 — 手动 lint(8 个)
- [x] `observe.py` F841:删未读 `result` 赋值,保留 `_get_result()` 调用
- [x] `schema.py` E501 ×2:`cases`/`actions` 字典拆行
- [x] `workflows.py` E501 ×3:LLM lambda 拆行 + SSE payload 提取中间变量
- [x] `test_workflows_phase14.py` E501 + E741:`client.stream` 拆参数,`l`→`line`

### Step 4:C 组 — ruff format(25 文件)
- [x] `ruff format .` → 25 reformatted(含 isolation/runtime/core 上周期漏 format 文件)

### Step 5:D 组 — mypy(28 → 0)
- [x] `base.py`:加 `__all__` 重导出声明(16 attr-defined 解决)
- [x] `docker_provisioner.py`:`_import_aiodocker` 返回注解 + `TYPE_CHECKING` stub
- [x] `pyproject.toml`:`[[tool.mypy.overrides]] module="aiodocker" ignore_missing_imports`
- [x] `workflows.py`:`inputs`/`_mock_output`/`mock_map`/`dry_run`/`generate` 类型补全
- [x] `webhooks.py`:`payload: dict[str, Any]`

### Step 6:迭代收紧
- [x] 修 UP037(docker_provisioner 去引号,因 `__future__ annotations`)
- [x] 修新增 I001(workflows.py 加 `Callable` 后导入排序)
- [x] `ruff format .`(收尾)

### Step 7:提交
- [x] 建 feature 分支 `evolve/2026-W31-1.2.1`
- [x] 排除运行时 `workflows/*.yaml`(gitignore 规则),纳入 `.gitkeep`
- [x] 纳入 `uv.lock`(上周期 aiodocker extra 进锁的合理更新)
- [x] commit `3178eb3`

## 验收门槛(下一节 test-report 记录证据)
- [x] `ruff check .` = 0
- [x] `ruff format --check .` = clean
- [x] `mypy hanflow` = 0
- [x] `pytest -q` = 417 passed, 5 skipped
- [x] `charter-check --diff` = GREEN
- [x] `smoke-test` = 4/4 PASS
