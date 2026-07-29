# Test Report: cycle 2026-W31-1.2.1 (clear pre-existing tech debt)

- 日期: 2026-07-29
- branch: `evolve/2026-W31-1.2.1` (hanflow 仓库)
- 测试员: LOOP P9 verify
- base: `github/main` @ 40cf349(含贡献者 PR #5: anthropic/ollama/deepseek/vllm stream())

## 质量门总览(全部 GREEN)

| 门 | 命令 | 修复前 | 修复后 |
|---|---|---|---|
| ruff check | `ruff check .` | ❌ 15 errors | ✅ **All checks passed!** |
| ruff format | `ruff format --check .` | ❌ 25 文件 | ✅ **200 files already formatted** |
| mypy | `mypy hanflow` | ❌ 28 errors | ✅ **Success: no issues found in 114 source files** |
| pytest | `pytest -q` | ✅ 411 passed | ✅ **417 passed, 5 skipped** |
| charter-check | `--diff` | GREEN(上个周期) | ✅ **GREEN 5/5(errors/registry/pydantic-data/async-api/layering)** |
| smoke-test | `.` | 4/4 | ✅ **4/4 PASS** |

## 全量 pytest 摘要

```
417 passed, 5 skipped, 2 warnings in 10.45s
```

| 类别 | 数量 | 说明 |
|---|---|---|
| **passed** | 417 | 基线 411 + PR #5 新增 6 个 stream 测试,无回归 |
| **skipped** | 5 | 4 个 docker 契约测试(no daemon) + 1 个 integration test |

PR #5 贡献者新增测试(anthropic/ollama/deepseek/vllm stream 解析 + 错误包装)全部通过,
验证 `base.py` 加 `__all__` 重导出修复未破坏 provider 对 `StreamChunk/TokenUsage` 的引用。

## charter-check 证据

```
$ bash scripts/charter-check/charter-check.sh --diff
=== charter-check (mode=diff, hanflow=E:/opensource/hanflow) ===
--- errors ---        OK: errors passed (scanned 13 files)
--- registry ---      OK: registry passed (scanned 13 files)
--- pydantic-data --- OK: pydantic-data passed (scanned 13 files)
--- async-api ---     OK: async-api passed (scanned 13 files)
--- layering ---      OK: layering passed (scanned 13 files)
=== charter-check: exit 0 ===
```

### 过程中发现并修复的 charter 回归

初版修复在 `docker_provisioner.py` 加了 `TYPE_CHECKING` stub `class DockerError(Exception)`,
触发 charter errors 守护(§2 不变量 1: 所有异常须继承 HanflowError)。已改用 `type[Any]`
返回注解(配合 pyproject `ignore_missing_imports`),既不触发 charter,又保持 mypy 绿。

## smoke-test 证据

```
$ bash scripts/smoke-test.sh .
=== smoke-test: hanflow=E:/opensource/hanflow ===
PASS [1/4] hanflow importable
PASS [2/4] DSL validation works
PASS [3/4] static workflow with FakeProvider
PASS [4/4] API app buildable
=== smoke-test: 0 failure(s) ===
```

## commits(feature 分支)

- `3178eb3` fix(lint,typecheck): clear pre-existing tech debt blocking S0 gates
- `3286806` refactor(isolation): drop DockerError stub, use type[Any] for aiodocker

## 结论

S0 三道质量门(ruff check / ruff format / mypy)从全红恢复为全绿,pytest 无回归,
charter-check + smoke-test 双守护通过。可以进入 release(1.2.0 → 1.2.1)。
