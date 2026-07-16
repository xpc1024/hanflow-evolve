# ADR-0003: Allow errors check to exempt core/expr.py ExprError

- 日期: 2026-07-16
- 状态: accepted
- 关联 cycle: 2026-W30-1.0.2
- 相关 fitness function: errors
- 清零截止: v1.1.0

## 背景 (Context)

`hanflow/core/expr.py:31` 定义 `class ExprError(Exception)`，未继承 `HanflowError`。
这是 charter §2 不变量 1（统一错误层级）的存量违规，先于 charter 存在。

## 决策驱动因素 (Decision Drivers)

1. 表达式求值模块（expr）是 DSL 内部子语言，其错误当前未纳入框架错误层级
2. 立即修复需评估 ExprError 的调用方与 code 语义，非本 cycle 范围

## 备选方案 (Considered Options)

1. 暂时豁免，v1.1.0 前重构 ExprError → HanflowError 子类
2. 立即将 ExprError 改为 HanflowError 子类

## 各方案优劣 (Pros/Cons)

### 方案1：暂时豁免
- 优：不阻断 charter-check 启用
- 劣：技术债存续至 v1.1.0

### 方案2：立即修复
- 优：无债
- 劣：需追溯 ExprError 所有 raise/except 点，超出本 cycle 范围

## 决策 (Decision)

选 方案1。v1.1.0 前重构 ExprError 为 HanflowError 子类并补 code/retryable 字段。

## 后果 (Consequences)

- 正面：errors 检查对增量代码立即生效
- 负面：ExprError 存续至 v1.1.0
- 引入的合规豁免: hanflow/core/expr.py（ExprError 存量违规，清零截止 v1.1.0）
