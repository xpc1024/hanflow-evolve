# 专家路由与核心判定器 (route-experts.md)

> 单一真相源: P3(周期级核心判定 + 专家路由)与 P6(任务级核心判定)共用本文件的
> 核心面定义。改核心面只改本文件,P3/P6 同步生效。

## 1. 核心面 (Core Surface)

依据 CHARTER §3 的 14 个顶层包枚举(core/atoms/orchestration/models/memory/runtime/
isolation/persistence/tools/retrieval/observability/workflows/api/cli)。

```yaml
# 触及任一即核心
core_packages:
  - core              # L0 底座, 改动影响全局
  - runtime           # 组合根, 业务逻辑下沉面
  - isolation         # 沙箱隔离 (亦属 security_surfaces)
  - persistence       # 数据持久化, 数据安全与一致性
  - memory            # 状态/记忆, 数据流闭环

# 不进核心面的包 (供追溯, 仍路由领域专家, 只是不额外触发安全/性能专家):
#   atoms / orchestration (L2 计算与编排)
#   models / tools / retrieval / workflows (L4 数据访问层)
#   observability (横切)
#   api / cli (顶层薄入口)

security_surfaces:    # 安全边界面 (与包无关, 按语义判定)
  - sandbox / 隔离
  - 认证 / 鉴权
  - 凭证处理
  - 外部网络 IO
  - 反序列化
```

## 2. 核心判定 (两粒度, 共用核心面)

```yaml
# 周期级 (P3 用): 满足任一即核心周期
is_core_cycle:
  - 任一 Task 的 affected files 命中 core_packages 或 security_surfaces
  - target_version 为 BREAKING (major)
  - P2b 人工标记 core (force-overview, 仅可强制为 core)

# 任务级 (P6 用): 不含 major/人工标记 (那是周期属性)
is_core_task:
  - 该 Task 的 affected files 命中 core_packages 或 security_surfaces
```

**核心归因规则**:自动检测(核心面)是主;P2b 人工标记是 force-overview,**只能强制
为 core,不能把自动判为 core 的强制降级**(安全保守)。

## 3. 专家路由表 (P3 执行)

读 direction.md 影响模块 → 匹配下表 → 写入 direction.md 的 "专家路由" 字段:

```yaml
# 写入 direction.md 的字段
expert_routing:
  design_experts: [...]      # 必派 (含至少一位领域 + QA 恒派)
  core: true|false           # is_core_cycle 结果
  conditional: [...]         # 仅 core=true 时追加 security/performance
```

匹配规则:
- 影响 ∈ {core, orchestration, runtime, persistence, api, cli, atoms, workflows} → **backend-architect**
- 影响 web/ 或 schema.py 或 hanflow-home → **frontend-designer**
- 影响 Pydantic schema / 状态机 / memory / retrieval / models → **data-modeler**
- 影响 isolation / CI / 版本 / GitHub-sync / 容器 → **devops-engineer**
- (恒) → **qa-architect**
- core == true → 追加 **security-engineer**, **performance-engineer**

## 4. 派发约定

- 专家 prompt 文件: `references/experts/<role>.md`
- 占位符接口(唯一): `{PAYLOAD}` / `{CONTEXT}` / `{ROUTING}`
- 派发方式: Agent 工具(general-purpose), **fresh context**(专家未参与设计/代码)
- 派发前填占位符: `{PAYLOAD}`=被审对象(方向草案/设计草案/git diff),
  `{CONTEXT}`=direction 目标 + 影响模块, `{ROUTING}`=本周期 expert_routing 字段
- **输出语言**: 每次派发的 prompt 末尾必须追加 "所有输出用中文"(subagent 默认可能切英文,
  专家 prompt 文件虽是中文, 仍需显式约束, 见 SKILL.md 输出语言全局约束)
