# ADR-0007: Fix charter-check --diff to compare against cycle base (master), not HEAD

- 日期: 2026-07-17
- 状态: accepted
- 关联 cycle: 2026-W29-1.0.2
- 相关 fitness function: none（改的是 _lib.sh list_py_files diff 模式，非 5 条检查逻辑）
- 清零截止: n/a

## 背景 (Context)

2026-W29-1.0.2 cycle P6 Task 1 实现后，P7 验证跑 `charter-check --diff` 发现 **scanned 0 files**——
所有检查空跑。根因：`_lib.sh:list_py_files` 的 diff 模式用 `git diff HEAD`（只看未提交的工作树改动），
但 LOOP P6 是 **commit-per-task**（每个 Task 单独 commit），P7 跑 --diff 时改动已全部提交，
工作树干净，故 diff 为空。

P7 真正需要的是**对比 cycle base（hanflow 仓库 master，即 cycle 开始前的状态）到当前 HEAD**
的累计改动，而非工作树未提交改动。

## 决策驱动因素 (Decision Drivers)

1. --diff 在提交后场景必须能看到 cycle 改动，否则 P7 守护失效（空跑 = 形同虚设）
2. 修复不改检查语义（仍是"增量守门"），只改"增量"的定义（工作树 → cycle base..HEAD）
3. 向后兼容：独立 worktree 无 master 时回退 HEAD

## 备选方案 (Considered Options)

1. diff 模式对比 master..HEAD（cycle base），无 master 回退 HEAD
2. 引入显式 --base <ref> 参数让用户指定 base commit
3. 保持 HEAD diff，要求 P7 在 commit 前跑

## 各方案优劣 (Pros/Cons)

### 方案1：master..HEAD + 回退
- 优：零配置，符合 LOOP 约定（master 是默认 cycle base）；自动回退保兼容
- 劣：硬编码 master（若某项目用 main，需调）

### 方案2：显式 --base
- 优：灵活
- 劣：增加参数复杂度；LOOP 每次要传 base

### 方案3：commit 前跑
- 优：不改脚本
- 劣：违背 commit-per-task 节奏；P7 想重跑已不可能

## 决策 (Decision)

选 方案1。`list_py_files` diff 模式改为 `git diff master..HEAD`，master 不存在时回退 HEAD。

## 后果 (Consequences)

- 正面：--diff 在 commit-per-task 场景正确工作，P7 守护有效
- 负面：硬编码 master（hanflow 仓库用 master，符合；若有项目用 main 需后续泛化）
- 引入的合规豁免: n/a
