# AUDIT: direction.md (2026-W30-1.1.1, docker-sandbox)

- 审核时间: 2026-07-20T10:30:00+08:00
- 审核员: independent subagent (fresh context)
- Layer 1 规则检查: PASS (5 章节齐全 — 动机 / 目标 / 非目标 / 实现路径 / 影响模块 / 风险评估 / 验收标准 全在)

## 审核结论
- 整体: 需修订 (2 严重 / 3 轻微)

发现的 2 个严重问题均集中在"方向文档自称合规、但留有一处未声明的依赖倒置前提"与"影响模块表与非目标条目互相矛盾"。两者都可在 P3(design) 阶段澄清后清零,无需更换主题或重写方向,但**必须回 P3 修订后才能放行进 P4b/design**。

源码探查佐证:动机段引用的 `isolation/sandbox.py:70-72`(:147-148)、`tools/builtin/code_exec.py:48`、`RunSandbox.create()` 位置、4 处契约缺口全部与 hanflow 实际源码一致,事实部分准确。

## 逐项判定

### A. 架构合规性

- [pass] 6 层定位: `SandboxProvisioner` Protocol + `ProvisionedSandbox` 在 `core/sandbox_contract.py`(L0);`LocalProvisioner/DockerProvisioner/K8sProvisioner` 在 `isolation/`(L4);`build_sandbox` 在 `runtime/`(组合根)。对应矩阵行 iscore(L0,只依赖自身) / isolation→core ✓ / runtime→isolation ✓。分层映射正确。
- [pass] Protocol-based: `SandboxProvisioner` 为 Protocol,与既有 `TraceExporter` Protocol 同型(方向文档自引 precedent 合理)。契约/实现分离清晰。
- [pass] HanflowError-only: 新增 `SandboxError(HanflowError)` + 4 个稳定 code(`SANDBOX_PROVISION_FAILED/ SANDBOX_TIMEOUT/ SANDBOX_DEP_MISSING/ SANDBOX_DESTROY_FAILED`)+ `retryable` 语义(timeout retryable / dep_missing 非 retryable),满足不变量 #1。已对照 `core/errors.py` 现有 13 个子类模式,一致。
- [pass] RuntimeContext/组合根注入: `runtime/build_sandbox.py` 作组合根读 config 选 provisioner 注入 `RunSandbox`,正是 §3 描述的"只有组合根直接 import 具体 L4 模块去构造 ctx"模式。
- [pass] DSL 单一真相源: 本 cycle 不触碰 DSL/Compiler/Registry(不变量 #4 不涉及),config.yaml 仅追加 `isolation` 段,无 schema 破坏。
- [pass] LangGraph 薄运行时: 不涉及。
- **[fail] 依赖矩阵隐含违规(未声明前提)**: 方向文档反复声称"契约是 L0""依赖倒置合规(§3)""charter-check 全绿",但 `SandboxProvisioner.provision(run_sandbox) -> ProvisionedSandbox` 的参数类型 `RunSandbox`、其字段类型 `SandboxResources`、以及 `SandboxMode` 枚举**当前全部定义在 `isolation/sandbox.py`(L32-80,经源码核实)**。若 `core/sandbox_contract.py` 以 `RunSandbox` 作为 `provision()` 形参类型注解,则 `core/sandbox_contract.py` 必须 `from hanflow.isolation.sandbox import RunSandbox` —— 这正是矩阵中 **core 行 × isolation 列 = ✗** 的反向依赖,直接违背 CHARTER §3 依赖矩阵与 §2"core 只依赖自身"。方向文档未声明如何化解(是把 `RunSandbox/SandboxResources/SandboxMode` 上移到 core?还是 Protocol 用结构性类型/`TYPE_CHECKING`?)。"全绿"断言依赖一个未写明的前提,属 A 类隐患。**→ 必须在 design 显式定方案。**

### B. 完整性

- [pass] 覆盖 direction 全部目标: 7 项目标(in scope)逐项有对应影响模块行 + 验收标准条目,可追溯。
- [pass] 有错误处理: `SandboxError` + 4 code + retryable 语义 + lazy import 触发 `SANDBOX_DEP_MISSING`(非静默),覆盖 provision/timeout/destroy/依赖缺失四类失败。
- [pass] 有测试策略: fake provisioner 跑全链路单测 + `DockerProvisioner` 契约测试 `skipif(no docker daemon)` 守护,CI 在无 daemon 环境仍绿。策略合理。
- [partial] 有迁移兼容: "RunSandbox 字段向后兼容(provisioner 可选注入)" + config 默认 `mode=local` 已声明;但 **4 处 `RunSandbox.create()` 调用点(`tests/isolation/test_sandbox.py` × 4)的迁移路径散落在路径 A 的"劣"段与验收 #2**,无独立迁移矩阵。轻微。
- [pass] 有非目标: 7 条非目标(K8S / Firecracker / per-agent 容器 / 镜像构建 / scheduler / API-CLI / egress 引擎)清晰且每条说明理由。

### C. 自洽性

- [pass] 接口输入输出匹配(主链): `config.yaml → build_sandbox → provisioner.provision() → ProvisionedSandbox(container_id/exec_interface/teardown_hook) → code_exec 返回 {stdout,stderr,returncode}`。主数据流闭环、形状与现有 `_exec_local` 同构。
- [pass] 组件依赖无环(主链): core ← isolation ← runtime,无环。
- **[fail] dedicated_sandbox 自相矛盾**: 
  - **非目标 #3** 明确写:"per-agent 容器——CHARTER §2.5 明确 sandbox 是 per-run…本 cycle 不引入 per-agent 容器(违反不变量)"。
  - 但 **影响模块表** `isolation/sandbox.py` 行写:"`spawn_agent` 的 dedicated_sandbox 分支调 provisioner"。
  - 而源码 `isolation/sandbox.py:142-148` 的 `dedicated_sandbox=True + DOCKER/K8S` 分支语义恰恰是"为该子 agent 单独 provision 容器"(注释 `real provisioning in Phase 8/10`)。若按影响模块表"wired",即实现 per-agent 容器 → 同时违背 **非目标 #3** 与 **CHARTER §2.5 per-run 不变量**;若按非目标 #3"不引入",则影响模块表那条改动是误导。
  - 另:`目标(in scope)` 7 条**均未列** dedicated_sandbox / spawn_agent 的 per-agent provisioning,影响模块却提及 → 目标/影响模块也对不齐。
  - **→ 必须 P3 澄清:dedicated_sandbox 分支要么删除/保持占位(符合非目标 #3),要么显式改为"复用 run container + 分配 subdir"(符合 §2.5),不可新 provision per-agent 容器。**
- [pass] 命名一致: `SandboxProvisioner/LocalProvisioner/DockerProvisioner/K8sProvisioner`、`SandboxError/SANDBOX_*`、`build_sandbox` 命名风格统一,与既有 `SandboxMode/SandboxResources/RunSandbox` 不冲突。
- [pass] 字段语义留 design: `ProvisionedSandbox.exec_interface/teardown_hook` 字段未定具体类型,风险评估段已标注"design 阶段定字段",可接受。

### D. 复杂度控制

- [partial] K8sProvisioner stub 轻微 YAGNI: 本 cycle 不实现 K8S 却新增 `K8sProvisioner` 文件 + `NotImplementedError` 占位。轻微过度设计嫌疑,但被两件事正当化:(1) 既有 `SandboxMode.K8S` 枚举已存在,契约要求该档有显式失败而非静默;(2) §4 编码规范要求占位用 `NotImplementedError("...lands in Phase 10")` 显式标记。**可保留**,但建议 design 说明"是否复用 isolation/sandbox.py 既有的 stub 表达,而非新开文件",以免文件膨胀。
- [pass] 复杂度匹配主题: DOCKER 隔离是生产安全边界,3 路径对比 + Provisioner 抽象 + 资源限额映射 + 测试守护,复杂度与主题量级相当,未越界。
- [pass] 路径 B/C 否决理由充分: B 违反依赖倒置 + 模型不纯;C 破坏 Pydantic 扁平契约并引 StreamChunk 前车之鉴(LEARNINGS #1),否决有据。

### E. 历史一致性

- [pass] 不与 LEARNINGS 冲突: 直接命中 LEARNINGS"下次优先[1] DOCKER sandbox 落地"+"高优先级技术债 DOCKER/K8S 占位符"+"演进优先填补占位"三条;并显式尊重 §2.5 per-run 不变量(非目标 #3)、Windows 路径痛点(风险评估:DOCKER 仅 Linux 验证、Windows 走 fake+LOCAL)、上个 cycle StreamChunk 教训(路径 C 否决理由)。历史对齐度高。
- [pass] 不与现有 specs 冲突: 关联 `§13.6 / §5.3 / CHARTER §2.5` 引用正确;Phase 编号"Phase 8(DOCKER)/ Phase 10(K8S)"与 `isolation/sandbox.py` docstring "wired in Phase 8/10" 一致。
- [note] 源码自身小瑕疵(非方向文档之过): `code_exec.py:48` 错误信息写 "Phase 7" 而 sandbox docstring 写 "Phase 8/10" —— 这是 hanflow 源码内部 Phase 编号不一致,方向文档采用 "Phase 8/10" 框架是正确的;建议本 cycle 顺手把 `code_exec.py:48` 的 "Phase 7" 文案对齐为 "Phase 8"(属轻微清理)。

## 建议修订

1. (严重 / A 类) **化解 core→isolation 反向依赖**: 在 design 显式选定其一并写入契约:(a) 把 `SandboxMode/SandboxResources/RunSandbox` 上移到 `core/sandbox_contract.py`(它们是纯 Pydantic 数据模型、无 IO,符合 core 定位,且能让 `SandboxProvisioner` 合法引用);或 (b) `SandboxProvisioner.provision()` 形参改用 core 内定义的结构性 Protocol(如 `SandboxView`)+ `TYPE_CHECKING` 注解,避免运行时 import。不清此条,"charter-check 全绿"断言不成立。
2. (严重 / C 类) **消除 dedicated_sandbox 自相矛盾**: 在 design 明确 `spawn_agent` 的 `dedicated_sandbox=True` 分支**不 provision per-agent 容器**,而是复用 run container + 在容器内分配 subdir(符合 §2.5);相应修订方向文档影响模块表 `isolation/sandbox.py` 行的措辞,并从 `目标(in scope)` 中显式纳入或排除该项,使目标/影响模块/非目标三者一致。
3. (轻微 / B 类) 补一节"迁移兼容矩阵":列出 `tests/isolation/test_sandbox.py` 4 处 `RunSandbox.create()` 调用点的具体改法(保留 `create()` 作 LOCAL 快捷方式 vs 改走组合根),避免 execute 阶段临时调整。
4. (轻微 / D 类) design 评估 `K8sProvisioner` 是否新开文件:若既有 `isolation/sandbox.py` 注释式 stub 已够,可不上新文件,降低 YAGNI 噪声。
5. (轻微 / 清理) 顺手把 `tools/builtin/code_exec.py:48` 的 "Phase 7" 文案对齐为 "Phase 8",与 sandbox docstring 一致。

## 摘要(附 direction.md 末尾用)

整体需修订(2 严重 / 3 轻微),主题选择与历史对齐优秀,但放行前必须清两条:(1) `SandboxProvisioner` 契约在 core 却引用 isolation 定义的 `RunSandbox`,隐含 core→isolation 反向依赖,须 design 明确上移模型或改用结构性 Protocol;(2) 影响模块表"spawn_agent dedicated_sandbox 分支调 provisioner"与非目标 #3"不引入 per-agent 容器"自相矛盾,须澄清为"复用 run container + subdir"。两条均可在 P3 修订后清零,主题无需更换。

## 复审 (round 2)

- 复审时间: 2026-07-20T11:45:00+08:00
- 复审员: independent subagent (fresh context, round 2)
- 触发: 严重问题修订后重审
- 复审基线: direction.md(修订版,日期 2026-07-20)+ CHARTER §2/§3 + 源码 `hanflow/isolation/sandbox.py`

### 严重问题 #1 (A 类: core→isolation 反向依赖)
- 判定: **已清零**
- 证据:
  - 目标 #1(direction.md L26):"把 `SandboxMode / SandboxResources / RunSandbox` 三个纯 Pydantic 数据模型(无 IO,符合 core 定位)**从 `isolation/sandbox.py` 上移到 `core/sandbox_contract.py`**...契约与所有数据类型**全部在 core 内自洽引用**,无 core→isolation 反向依赖(矩阵合规)。`isolation/sandbox.py` 改为 `from hanflow.core.sandbox_contract import RunSandbox, ...` 复用(L4→L0 合规)"。
  - 路径 A 优势段(L52):"契约 + 全部数据类型在 core 内自洽引用,isolation 改为复用 core(L4→L0)"。
  - 影响模块表(L95/L98):`core/sandbox_contract.py`(新)"承接从 isolation 上移的 `SandboxMode/SandboxResources/RunSandbox`";`isolation/sandbox.py`(瘦身)"移除定义(上移 core)+ re-export 兼容"。
  - 风险评估(L116,本次审核修订后标注):"`SandboxProvisioner` 契约在 `core/sandbox_contract.py`,**必须**与它引用的 `RunSandbox/SandboxResources/SandboxMode` 同处 core...类型上移后 core 仍不 import 任何 L4,合规"。
  - 验收标准 #1(L135)与新增 #14(L148):"`SandboxMode/SandboxResources/RunSandbox` 也定义在 `core/sandbox_contract.py`(从 isolation 上移)";"**无 core→isolation 反向 import**:`core/sandbox_contract.py` 不 import `hanflow.isolation.*`(由 charter-check layering 规则守护)"。
- 理由: 修订采用了 round 1 建议的方案 (a)——把三个纯数据模型(经源码核实 `sandbox.py:32-57`,均为 Pydantic BaseModel/StrEnum,无 IO,符合 core 定位)整体上移到 core,使 `SandboxProvisioner.provision(run_sandbox)` 的形参类型 `RunSandbox` 在 core 内自洽引用;isolation 改为 L4→L0 复用 + re-export 保向后兼容。core 行 × isolation 列 = ✗ 的反向依赖隐患被根除,且新增验收 #14 用 charter-check layering 规则做硬守护。方案与既有 `TraceExporter` Protocol 模式同型,precedent 充分。修订一致地贯穿目标/路径/影响模块/风险/验收 5 处,无遗漏。

### 严重问题 #2 (C 类: dedicated_sandbox 自相矛盾)
- 判定: **已清零**
- 证据:
  - 新增目标 #7(L32):"`spawn_agent` 的 `dedicated_sandbox=True` 分支**不 provision per-agent 容器**(符合 CHARTER §2.5 + 非目标 #3),而是**复用 run container + 在容器内分配 subdir**...该分支当前是 `pass` 占位(`sandbox.py:142-148`),本 cycle 把它接到 `ProvisionedSandbox` 的 subdir 分配逻辑上"。
  - 非目标 #3(L39,修订后追加澄清):"`dedicated_sandbox=True` 分支只复用 run container + 在容器内分配 subdir(目标 #7),**不为单个子 agent 新 provision 容器**"。
  - 影响模块表 `isolation/sandbox.py` 行(L98,原"调 provisioner"措辞已改):"`spawn_agent` 的 `dedicated_sandbox=True` 分支**复用 run container + 容器内分配 subdir**(不 provision per-agent 容器)"。
  - 风险评估(L117,新增):"`dedicated_sandbox=True` 分支必须严格'复用 run container + 容器内 subdir',不得新 provision per-agent 容器(违反 CHARTER §2.5)。design 阶段在接口签名上强制此语义(`provision()` 只接受 run 级 `RunSandbox`,不接受 per-agent spec)"。
  - 验收标准 #8(L142):"`spawn_agent` 的 `dedicated_sandbox=True` 分支复用 run container + 容器内 subdir,不 provision per-agent 容器(单测验证:dedicated=True 时只多一个 subdir,container 数量不增)"。
- 理由: 原 round 1 抓的三处不一致(目标未列 / 影响模块"调 provisioner" / 非目标"不引入")现已全部对齐到同一语义——"复用 run container + 容器内 subdir,不 provision per-agent 容器"。源码 `sandbox.py:142-148` 的 `dedicated_sandbox + DOCKER/K8S` 分支(注释 `real provisioning in Phase 8/10`)经修订后接到 subdir 分配,而非 per-agent provisioning,与 CHARTER §2.5 per-run 不变量一致。修订甚至更进一步:在风险评估用接口签名(`provision()` 只接 run 级 `RunSandbox`)强制此语义,并在验收 #8 用可测断言(container 数量不增)守护——比 round 1 要求的"三处一致"更稳。

### 新引入问题扫描
- **无新 A/C/E 类严重问题**。详扫如下:
  - **A 类(架构)**:类型上移后 `core/sandbox_contract.py` 仅引用 core 内类型,无跨层 import;`SandboxProvisioner` 为 Protocol,与既有 `TraceExporter` 同型(round 1 已认 pass);isolation→core ✓、runtime→isolation ✓(组合根)均合规。验收 #14 用 charter-check layering 守护,无新违规面。
  - **C 类(自洽)**:目标 #1/#7、非目标 #3、影响模块表、风险评估、验收 #1/#8/#14 全链一致;主数据流 `config → build_sandbox → provisioner.provision() → ProvisionedSandbox → code_exec` 闭环无歧义。
  - **E 类(历史)**:Phase 8(DOCKER)/ Phase 10(K8S)编号与 `sandbox.py` docstring "wired in Phase 8/10" 一致;`code_exec.py:48` 的 "Phase 7" 文案对齐已纳入目标 #4 + 验收 #6。
  - **附带清掉的 round 1 轻微项**:B 类"迁移兼容矩阵"已新增独立章节(L119-131,列 5 处调用点 + DOCKER 新路径);D 类 K8sProvisioner 是否新开文件已在影响模块/验收 #4 标注"design 阶段评估是否复用 sandbox.py 既有 stub 而非新文件";E 类 Phase 7→8 清理已纳入目标 #4。
  - **观察项(非阻断,留给 design 注意)**:`RunSandbox.create()` 作为 LOCAL 向后兼容快捷方式随类型一起落在 core,该方法调用 `workspace_mgr.workspace_for(run_id)` 属轻微 IO 边界;但 (a) 这是既有行为保留而非新增,(b) `workspace_for()` 仅做路径分配无磁盘写入,(c) 方向文档已明确"provisioner 不进模型字段"且 provisioner 才是新 clean path、`create()` 仅为 legacy shim。不构成 A 类违规,design 阶段可考虑在 docstring 标注"deprecated shortcut, prefer build_sandbox()"以降噪。

### 复审判定
- 整体: **通过** (剩余 0 严重 / 0 强制轻微;1 观察项留 design)
- 后续: **放行进 GATE1**(可进 P4b/design)。design 阶段建议落实两件:(1) 列类型上移的 import 迁移矩阵(已部分覆盖于"迁移兼容矩阵"章节,补 core 内部引用即可);(2) 在 `provision()` 签名与 `RunSandbox.create()` docstring 上固化"per-run only / create() 为 deprecated shortcut"语义,防 execute 阶段回退。
