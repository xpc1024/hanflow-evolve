# 语义化版本 (Semantic Versioning) 规范与判断规则

> 本文档是 contribute-pr S6 版本号自动升级的判断依据。
> 基于 [SemVer 2.0.0 官方规范](https://semver.org/),无需再联网搜索。
> AI 根据本文档规则 + 代码 diff 自主判断版本号如何 bump。

---

## 1. SemVer 2.0.0 核心规则

版本号格式:**MAJOR.MINOR.PATCH**(如 1.2.3),各段递增规则:

| 段 | 何时递增 | 兼容性 | 例子 |
|----|---------|--------|------|
| **MAJOR**(X.0.0) | **不兼容的 API 变更**(breaking change) | ❌ 破坏性,用户代码可能要改 | 删除/重命名公开 API、改 DSL schema 破坏现有工作流、改配置项含义 |
| **MINOR**(1.X.0) | **向后兼容的新功能** | ✅ 安全升级 | 新增 CLI 命令、新增 DSL 节点类型、新增 REST 端点、新增配置项 |
| **PATCH**(1.0.X) | **向后兼容的 bug 修复** | ✅ 安全升级 | 修 bug、修错误码、补文档、内部重构(不改公开 API) |

**核心原则**:版本号传达的是**兼容性**,不是改动大小。一个很大的内部重构(只要不改公开 API)是 PATCH;一个很小但破坏兼容的改动(如改一个参数名)是 MAJOR。

---

## 2. contribute-pr 的版本判断规则

contribute-pr 根据 feature 分支的代码 diff + commit message 判断 bump 类型:

### 2.1 MAJOR(X.0.0)—— 破坏性变更

命中以下任一即 MAJOR:
- commit message 含 `BREAKING CHANGE` 或 `!`(conventional commits 的 breaking 标记,如 `feat!: ...` / `BREAKING CHANGE: ...`)
- 删除或重命名公开 API(CLI 命令删除、DSL 节点类型删除、REST 端点删除)
- 改变现有 API 的行为/签名(参数名改、返回值结构变、错误码含义变)
- DSL schema 破坏性变更(现有工作流会报错)

### 2.2 MINOR(1.X.0)—— 向后兼容新功能

命中以下任一即 MINOR(且不触发 MAJOR):
- commit message prefix 是 `feat:`(新功能)
- 新增 CLI 命令(不删旧的)
- 新增 DSL 节点类型(不删旧的)
- 新增 REST 端点(不删旧的)
- 新增配置项(不改旧的含义)

### 2.3 PATCH(1.0.X)—— 向后兼容修复

命中以下任一即 PATCH(且不触发 MAJOR/MINOR):
- commit message prefix 是 `fix:` / `docs:` / `refactor:` / `chore:` / `style:` / `perf:` / `test:` / `build:` / `ci:`
- bug 修复(不改公开 API)
- 文档更新
- 内部重构(不改公开 API)
- 性能优化(不改公开 API)

### 2.4 判断优先级

**MAJOR > MINOR > PATCH**。如果一次改动同时含 breaking 和新功能,取 MAJOR(破坏性优先,
保证用户知道可能不兼容)。

### 2.5 边界:contribute-pr 不做 MAJOR?

诚实考虑:社区贡献者的 PR 一般**不该引入 breaking change**(那是维护者的重大决策)。
如果 AI 判断某贡献是 MAJOR(breaking),contribute-pr 应该**警告并暂停**,让贡献者确认:
"本次改动似乎是破坏性的(版本将升 X.0.0)。社区贡献一般不引入 breaking change,
请确认这是有意为之,或调整为向后兼容。"

---

## 3. 版本号 bump 计算

给定当前版本 `MAJOR.MINOR.PATCH` 和 bump 类型:

| bump | 新版本 |
|------|--------|
| MAJOR | `(MAJOR+1).0.0` |
| MINOR | `MAJOR.(MINOR+1).0` |
| PATCH | `MAJOR.MINOR.(PATCH+1)` |

例子(当前 1.2.1):
- MAJOR → 2.0.0
- MINOR → 1.3.0
- PATCH → 1.2.2

---

## 4. AI 判断输入/输出

**输入**(home-sync 收集):
- feature 分支所有 commit message(用于 prefix + BREAKING 检测)
- 代码 diff 摘要(改了哪些公开 API:CLI/DSL/REST/config)

**输出**:
- `BUMP_TYPE`: major | minor | patch
- `NEW_VERSION`: 计算后的新版本号
- `BUMP_REASON`: 判断依据(如"feat: 新增 RAG cache 节点 → MINOR")

---

## 5. 来源

- [Semantic Versioning 2.0.0 官方规范](https://semver.org/)
- [Conventional Commits 1.0.0](https://www.conventionalcommits.org/)(`!` / `BREAKING CHANGE` 标记)
