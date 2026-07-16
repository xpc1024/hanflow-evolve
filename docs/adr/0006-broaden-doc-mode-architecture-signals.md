# ADR-0006: Broaden charter-check --doc architecture-change signal regex

- 日期: 2026-07-17
- 状态: accepted
- 关联 cycle: 2026-W29-1.0.2
- 相关 fitness function: none（改的是 charter-check.sh --doc 模式，非 5 条代码检查）
- 清零截止: n/a

## 背景 (Context)

在 2026-W29-1.0.2 cycle 的 P3b audit_direction 阶段，首次实战运行 `charter-check.sh --doc` 发现
**漏检**：direction.md 明确讨论了"ModelProvider Protocol 扩展"（加 `stream()` 方法、影响多模块），
这是 CHARTER §6 触发条件第 1/4 类的架构变更，但 `--doc` 报告"no architecture-change signals"。

根因：现有正则 `(新增|删除|迁移|替换|重构).*(模块|包|层|依赖)` 只匹配"动作词+修饰词"的组合，
无法识别"Protocol 扩展"、"加方法到契约"、"接口扩展"等常见架构变更表述。

## 决策驱动因素 (Decision Drivers)

1. `--doc` 的价值在于抓架构变更信号让 AUDIT Layer-2 复核 ADR 必要性；漏检等于失效
2. v1 正则基于猜测，实战暴露覆盖不足；应据真实文档语言扩展
3. 宁可多 WARN（Layer-2 会复核），不可漏检（漏检无补救）

## 备选方案 (Considered Options)

1. 扩展正则，加入 Protocol/契约/接口/方法 相关模式
2. 保持现状，靠 Layer-2 fresh-context subagent 语义兜底
3. 改 direction 措辞凑现有正则

## 各方案优劣 (Pros/Cons)

### 方案1：扩展正则
- 优：信号检测覆盖真实文档语言；信号→Layer-2 复核链完整
- 劣：可能多 WARN（但 Layer-2 会判，可接受）

### 方案2：靠 Layer-2 兜底
- 优：不改脚本
- 劣：--doc 形同虚设（漏检=Layer-1 无信号=依赖 Layer-2 全读全文，违背分层）

### 方案3：改 direction 措辞
- 优：零脚本改动
- 劣：治标不治本，每个 direction 都要凑正则，不可持续

## 决策 (Decision)

选 方案1。在现有正则追加模式：
- `(扩展|扩展.*Protocol|扩展.*契约|扩展.*接口)` — Protocol/契约扩展
- `(加|新增|增加).*(方法|字段|属性).*(Protocol|契约|接口|基类)` — 契约方法扩展
- `(影响模块|影响.*模块)` — 影响模块表（多模块改动信号）

## 后果 (Consequences)

- 正面：--doc 能抓到 Protocol 扩展/契约方法变更/多模块影响等常见架构变更信号
- 负面：WARN 略增（Layer-2 复核，非阻断）
- 中性：属 charter-check 自身演进，本 ADR 留痕
- 引入的合规豁免: n/a
