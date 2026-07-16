# ADR-0004: Allow async-api check to exempt checkpoint.py LangGraph stubs

- 日期: 2026-07-16
- 状态: accepted
- 关联 cycle: 2026-W30-1.0.2
- 相关 fitness function: async-api
- 清零截止: v1.1.0

## 背景 (Context)

`hanflow/persistence/checkpoint.py:82/85/88` 定义 sync `put()`/`get_tuple()`/`list()`，
命中 async-api 检查的 IO 方法名模式。但这 3 个方法是 LangGraph `BaseCheckpointSaver`
抽象基类**强制**的 sync 签名——它们只 `raise NotImplementedError("Hanflow uses async checkpoint API only")`。
真实的 async 实现在同文件的 `aput`/`aget_tuple`/`alist`（行 60-79）。

## 决策驱动因素 (Decision Drivers)

1. LangGraph 基类契约强制 sync 签名，无法删除
2. Hanflow 运行时只调 async 版本，sync stub 是死代码（满足类型系统）

## 备选方案 (Considered Options)

1. 豁免 sync stub（它们 raise NotImplementedError，非真实 IO）
2. 用 `# sync-bridge` 注释豁免（脚本内置机制）
3. 不豁免（永久 FAIL）

## 各方案优劣 (Pros/Cons)

### 方案1：ADR 白名单豁免
- 优：可见、有清零计划（v1.1.0 前评估是否能改用 Protocol 而非继承基类）
- 劣：需跟踪

### 方案2：sync-bridge 注释
- 优：就地标注
- 劣：这些不是真正的 asyncio.run 边界，注释语义不准

### 方案3：不豁免
- 优：无债
- 劣：基类契约强制，永久 FAIL 不可解决

## 决策 (Decision)

选 方案1。v1.1.0 前评估：若 LangGraph 后续放宽基类要求或 Hanflow 改用 Protocol 组合（不继承），则移除 stub。

## 后果 (Consequences)

- 正面：async-api 检查对增量代码立即生效
- 负面：3 个 sync stub 存续至 v1.1.0
- 引入的合规豁免: hanflow/persistence/checkpoint.py（put/get_tuple/list LangGraph BaseCheckpointSaver 强制 sync 签名，清零截止 v1.1.0）
