# Design — 2026-W34-1.2.4 · loop-toolchain-state-sync-and-signal-filter

- **cycle**: 2026-W34-1.2.4 (Gate 1 approved)
- **date**: 2026-08-20
- **上游**: direction.md (P3b audit PASS, 0 严重/3 轻微)

## 架构定位

本周期**不涉及 hanflow 六层架构**(dsl/core/api/runtime/tools/observability),
改动对象是 hanflow-evolve 仓库的 LOOP 信号采集工具链:

```
LEARNINGS.md ──collect_learnings()──▶ signals.json ──score-signals.py──▶ scored.json ──update-backlog.sh──▶ BACKLOG.md
                ▲ 本次唯一代码改动点                                                        (下游自动受益)
```

修复位置在采集端(管道最上游),下游打分/排序零改动。

## 组件分解

| 组件 | 文件 | 改动类型 |
|------|------|---------|
| 采集过滤器 | scripts/signal-gather.sh `collect_learnings()` (L217-258) | 修改: +行首 `~~` 判定 |
| 过滤测试 | tests/test-signal-gather.bats | 新增: 1 个 @test (3 类断言) |
| 知识库销账 | LEARNINGS.md「下次优先」 | 修改: #1/#2 标完成, 清理滞留已完成子项 |
| 自证重采 | cycles/2026-W34-1.2.4/signals.json | 重新生成 |
| 回归确认 | tests/test-version-bump.bats (既有) | 仅运行, 零改动 |

## 接口契约

`collect_learnings(learnings_file) -> list[signal]` 签名不变。行为变更:

```python
# 现状 (signal-gather.sh L244-246):
body = lm.group(1).strip()
if not body:
    continue
idx += 1            # ← 所有条目(含已完成)都被编号采集

# 变更后:
body = lm.group(1).strip()
if not body:
    continue
if body.startswith("~~"):
    continue        # ← 行首删除线 = 已完成条目, 跳过且不占用 learning:N 编号
idx += 1
```

契约要点:
- 判定对象是 `body`(剥离列表前缀 `- `/`N. ` 并 strip 后的正文首字符)
- **仅行首 `~~` 触发**;正文任意位置出现 `~~`/`✓`/「已修」不触发(防误杀
  learning:2 型边界条目)
- 已完成条目不占用 `learning:N` 序号(idx 在过滤后自增),剩余条目连续编号

## 数据流

1. fixture LEARNINGS.md「## 下次优先」段 → `collect_learnings()` → 过滤行首
   `~~` 条目 → signals.json
2. score-signals.py 消费 signals.json:learnings-priority 主题 member 数
   19→11,member_score 相应回落,不再虚高霸占队首
3. update-backlog.sh 重排 BACKLOG(无需改动,自动反映)

## 错误处理

- **HanflowError 不适用**: 本周期改动对象为 hanflow-evolve 采集脚本
  (bash+内嵌 python), 不在 hanflow 运行时内执行, 错误语义沿用脚本现有
  约定(采集端宽松降级, 见下), 不引入 hanflow 异常体系。
- LEARNINGS.md 缺失/无「下次优先」段: 现状返回 `[]`,行为不变(过滤逻辑在
  段内解析循环中,无段则不执行)
- body 为空: 现状 continue,不变
- 过滤后段落全为已完成条目 → 返回 `[]`,与「无条目」同构,下游兼容

## 测试策略

**新增 bats 用例** `"filters completed (strikethrough) LEARNINGS entries"`:

fixture(fake-evolve/LEARNINGS.md「下次优先」段, 5 条):
```
1. ~~旧 bug~~ ✓ 已修 (2026-W31)          → 跳过 (行首 ~~)
2. - ~~另一旧账~~ ✓ 已完成 (v1.2.0)       → 跳过 (行首 ~~)
3. **[高] 真实待办甲**                     → 保留
4. **[高] signal-gather 过滤** —— 混入已完成项 (score-signals bug 已修) → 保留 (边界: 正文含"已修"但行首无 ~~)
5. ~~**[中] 旧账乙**~~ ✓ 已恢复            → 跳过
```

断言(沿用现有用例的 env-var + python -c 风格):
- learnings 信号总数 == 3(条目 3/4/5 中的 3、4)
- 无任何信号 text 以 `~~` 开头
- 边界条目(含「已修」字样者)在结果中
- 保留条目 id 连续: learning:1, learning:2

**回归**: 全量 `bats tests/` + `pytest tests/test-score-signals.py` +
既有 `test-version-bump.bats`(覆盖 state 回写, direction 目标 4)。

## 前端影响

无。不涉及 web/、schema.py、DSL、REST/WS。

## 迁移兼容

- signals.json schema 不变(仅条目减少),score-signals.py / update-backlog.sh
  零适配
- LEARNINGS.md 约定不变: 完成项继续用行首 `~~` 划线(既有维护习惯, 工具现在
  正式承认该约定)
- 历史 cycles/*/signals.json 不回溯重采(每周期快照语义, 仅本周期起重采)

## 与 direction 验收标准对照

| direction 验收 | 设计落点 |
|---------------|---------|
| 1. bats 3 类用例 | 测试策略 fixture 条目 1/2/5(跳过)、3(保留)、4(边界保留) |
| 2. 重采 learning=11 | 数据流 §2 + 自证重采组件 |
| 3. 全套测试绿 | 测试策略回归段 |
| 4. LEARNINGS #1/#2 销账 | 组件分解知识库销账行 |
| 5. hanflow 零提交 | 架构定位(改动仅 evolve 侧) |
| 6. release 不发空 tag | 无代码落点, release 阶段执行决策 |
