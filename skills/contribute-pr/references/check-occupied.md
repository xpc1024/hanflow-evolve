# 去重钩子(check-occupied)

contribute-pr 在选题阶段的去重机制,防止贡献者与他人或历史贡献撞主题。

---

## 触发时机

`scripts/check-occupied.sh` 在 **prioritize 之后、human_topic/plan 之前**(阶段 2.5)执行。

- 输入:prioritize 产出的候选主题列表(从 .contribute/state.yaml.artifacts 或 signals 读)
- 输出:每个候选的占用状态 + 总体建议(可进 plan / 有冲突需确认)

---

## 两级匹配(P1 只实现 Level 1,Level 2 留 P2)

### Level 1:精确匹配〔P1,本阶段实现〕

匹配**确定性标识**,命中即硬 skip:

- `evolve/*` 分支名(上游 hanflow/hanflow-home 的 open PR 头分支)
- `contrib-*` 分支名(社区贡献的分支,值带 contrib- 前缀)
- PR 标题里的 contribution_id(如 `contrib-2026-W30-001`)
- CONTRIBUTIONS.md 中 status=open 记录的 theme 字段

**命中 → 标 `OCCUPIED`(硬冲突,直接 skip)**

理由:同分支/同 ID 是确定冲突,继续会撞分支或重复主题,必须 skip。

### Level 2:语义近似〔P2,MVP 可后置,本阶段不实现〕

取候选的 affected_modules + 关键词,与所有 open+merged PR 标题计算 token 重叠率
(Jaccard ≥ 0.6 触发)。

**注**:0.6 阈值是初始猜测值,非校准值,需实测调参。P1 跑通积累真实撞主题案例后,
P2 再实现 Level 2 并校准阈值。

**命中 → 标 `LIKELY_DUPLICATE`(降权 + 向贡献者提示,让其确认是否仍继续,而非硬 skip)**

---

## 数据源

```bash
# 主源:上游 GitHub(分布式真相,所有贡献者机器一致)
gh pr list --repo xpc1024/hanflow --state all --limit 200 \
  --json number,title,headRefName,state
gh pr list --repo xpc1024/hanflow-home --state all --limit 200 \
  --json number,title,headRefName,state

# 辅源:本地 CONTRIBUTIONS.md(离线 + 本机已发未上游化的记录)
# grep 解析 status/theme 字段
```

**两个仓库都查**——文档 PR 也算占用(避免 A 发功能 PR、B 又发同主题文档 PR)。

**gh 不可用时降级**:若 `gh auth status` 失败,只读本地 CONTRIBUTIONS.md,输出 WARN:

```
WARN: gh 未认证,未查上游 GitHub,去重不完整(跨贡献者去重失效)。
      建议先 gh auth login 或提供 PAT。本机档案去重仍生效。
```

**不硬阻断**——贡献者可能离线先选题,只降级提示。

---

## status 与去重的联动(结合 refresh-status 的状态)

| CONTRIBUTIONS.md 中 status | check-occupied 对该主题的处理 |
|---------------------------|------------------------------|
| `open` | **OCCUPIED(硬 skip)** —— 活跃 PR 进行中,撞分支风险高 |
| `merged` | 不占用,但记为已交付 —— 提示"此功能已于 <date> 由 @x 合并,做增强版请说明差异" |
| `closed` | 不占用,记为已拒 —— 提示"此主题曾被 @y 提交未合并,查看 <pr_url> 了解原因" |

三分法比"open=占用、其余=释放"更准——merged 的主题不是锁死,而是有上下文(谁做过、做到
什么程度),新贡献者可做增量而非重复造轮子。

---

## P1 实现说明

- `scripts/check-occupied.sh`:只实现 Level 1(分支名/ID/theme 字符串精确匹配)
- Level 2 的 fuzzy 匹配(token 化 + Jaccard)**不实现**,留 P2
- Level 1 跑通后,积累真实撞主题案例,再决定 Level 2 的阈值和实现方式

---

## 输出示例

```
=== check-occupied (Level 1) ===
数据源: GitHub PR (hanflow: 12, hanflow-home: 3) + 本地 CONTRIBUTIONS.md (5 条)

候选主题检查:
  [1] rag-retrieval-caching → OCCUPIED (open PR #42, 分支 evolve/contrib-2026-W30-001)
  [2] stub-observe → 已 merged (PR #38, 2026-07-25 by @bob), 可做增强版
  [3] model-routing-fallback → 空闲
  [4] dsl-syntax-validator → 空闲

建议: 2 个空闲主题可选([3][4]),1 个已交付可增量([2]),1 个硬冲突 skip([1])
```
