# 执行计划: 补全所有 CLI stub 命令

## 任务列表 (原子化, 每任务单 commit)

### Task 0: 新增 CLIError + CliClient 基础
- 文件: hanflow/core/errors.py (加 CLIError), hanflow/cli/client.py (新建)
- TDD: 先写 test_cli.py 的 client 测试 (mock httpx)
- 验收: CliClient 可实例化, list_runs/get_run/cancel_run/approve/edit/reject/reroute/trace/artifacts 方法存在

### Task 1: 实现 run 管理命令 (runs/status/cancel/logs/trace/artifacts)
- 文件: hanflow/cli/main.py (替换 6 个 stub)
- TDD: 每个命令一个测试 (mock CliClient)
- 验收: 命令输出格式正确, 404 时 exit_code=1

### Task 2: 实现 HITL 命令 (approve/edit/reject/reroute/resume)
- 文件: hanflow/cli/main.py (替换 5 个 stub)
- TDD: 测试 approve 成功 + reject 缺 reason 报错 + edit 缺 value 报错
- 验收: HITL 命令调正确 API 端点

### Task 3: 实现本地命令 (tools/config)
- 文件: hanflow/cli/main.py (替换 2 个 stub), hanflow/sdk.py (加 list_tools accessor)
- TDD: mock Hanflow.list_tools + mock load_config
- 验收: tools 列出工具, config 输出 JSON

### Task 4: 实现 Group B 降级命令 (metrics/search/eval/datasets/worker)
- 文件: hanflow/cli/main.py (替换 5 个 stub)
- TDD: 验证输出含 "not yet" / "not configured" / "planned"
- 验收: 5 个命令输出明确降级信息

### Task 5: 删除 stub 循环 + 回归测试
- 文件: hanflow/cli/main.py (删除 _stub 循环), tests/cli/test_cli.py
- TDD: 关键回归测试 — 17 命令输出不含 "delegates to SDK"
- 验收: make ci 全绿

## 测试计划

### 单元测试 (mock-based, 不启动 server)
- 每个 Group A 命令: mock CliClient 方法, 验证输出格式 + 错误处理
- 每个 Group B 命令: 验证降级消息
- 回归: 无 "delegates to SDK" 残留

### 行为化 smoke
- make ci (lint + mypy strict + pytest) 全绿

## 完成定义 (DoD)
- [ ] 17 个 stub 全部替换
- [ ] make ci 全绿
- [ ] 无 "delegates to SDK" 残留
- [ ] CLIError 是 HanflowError 子类
- [ ] mypy --strict 通过
