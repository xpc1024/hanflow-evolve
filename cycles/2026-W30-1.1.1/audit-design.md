# AUDIT: design.md (2026-W30-1.1.1, docker-sandbox)

- 审核时间: 2026-07-21T10:00:00+08:00
- 审核员: independent subagent (fresh context)
- Layer 1 规则检查: PASS (7 章节齐全 — 架构定位 / 组件分解 / 接口契约 / 数据流 / 错误处理 / 测试策略 / 迁移兼容 / 前端影响 / 风险残留 / 验收标准;错误处理明确提及 HanflowError)

## 审核结论
- 整体: 需修订 (3 严重 / 4 轻微)

主题承接与方向落地**总体优秀**:direction Gate 1 清零的 2 个严重问题(类型上移、dedicated_sandbox 复用 run container + subdir)在 design 中被忠实且更具体地落实;LL4 调用链、迁移矩阵、测试金字塔、风险残留都达到 design 阶段应有的颗粒度。但逐项核对源码后发现 **3 个 A/C 类严重问题**必须回 P3b 修订后才能放行进 P4b/code,其中 2 个是**新引入**(非 direction 阶段就能发现的契约缺口),1 个是 direction 严重问题 #2 的**回退**(design 的 spawn_agent 改写偷偷把语义弄丢了一半)。

**严重清单**:
1. (A) `HanflowError.__init__` 不接受 `code=` kwarg,design 全文 `SandboxError(..., code="SANDBOX_PROVISION_FAILED", ...)` 写法直接 `TypeError`。
2. (C) `ProvisionedSandbox.exec_interface: ExecInterface` 引用的 `ExecInterface` Protocol 在 `ProvisionedSandbox` 类定义之后才声明(Pydantic field 解析时名字未绑定),且 `SandboxProvisioner.provision` 的返回类型注解 `-> ProvisionedSandbox` 也前向引用了未定义名。
3. (C) `spawn_agent` 重写中 `except Exception as exc: raise HanflowError(...)` **吞掉了 `_DockerExec.run` / `LocalExec.run` 抛出的 `SandboxTimeoutError` 与 `SandboxProvisionFailedError`**,把它们降级成无 code 的基类 `HanflowError`(`HANFLOW_ERROR`),既破坏 §2.1 错误层级统一性,也使"dedicated_sandbox 不新 provision 容器"的契约失去单测守护(design 自称的 container 数量不增断言无单测条目对应)。

## 逐项判定

### A. 架构合规性

- [pass] 6 层定位:类型 + Protocol(`SandboxProvisioner` / `ExecInterface`) + 数据模型(`RunSandbox` / `SandboxResources` / `SandboxMode` / `ProvisionedSandbox`) 全部落 `core/sandbox_contract.py`(L0);LocalProvisioner / DockerProvisioner / K8sProvisioner 落 isolation(L4);`build_sandbox` 落 runtime(组合根)。对照 CHARTER §3 矩阵三行:`core × isolation = ✗` 保持(无反向 import)、`isolation × core = ✓`、`runtime × isolation = ✓`。架构图正确。

- [pass] Protocol-based:`SandboxProvisioner` 用 `@runtime_checkable Protocol`,与既有 `core/context.py:31-32` 的 `RuntimeContext` 同型,precedent 合规;`ExecInterface` 同型。

- [pass] RuntimeContext 注入 / 组合根:`build_sandbox` 是典型组合根,内部 `from hanflow.isolation.local_provisioner import LocalProvisioner`(函数体内 lazy import)注入具体 provisioner,与 CHARTER §3 "只有组合根直接 import 具体 L4 模块去构造 ctx" 的立法理由吻合;`RuntimeContext` Protocol 不污染新属性(见组件 #6 的"为什么不在 RuntimeContext Protocol 上加 provisioned()"论证,理由充分)。

- [pass] DSL 单一真相源:本 cycle 不触碰 DSL/Compiler/Registry(不变量 #4 不涉及),`config.yaml` 仅追加 `isolation` 段,无 schema 破坏。

- [pass] LangGraph 薄运行时:不涉及。

- [pass] HanflowError-only(概念层):新增 `SandboxError(HanflowError)` + 4 个子类 + `ToolWhitelistError`,全部继承 `HanflowError`,满足不变量 #1 的概念要求。**但实现层有严重 bug,见下**。

- **[fail] HanflowError 实例化 API 误用(新引入,A 类)**:design 在 `DockerProvisioner.provision`(L269-274)、`DockerProvisioner.destroy`(L312-318)、`build_sandbox`(L384-388)三处**直接给 `SandboxError(...)` 构造函数传 `code="SANDBOX_PROVISION_FAILED"`** kwarg。但源码 `core/errors.py:28-42` 的 `HanflowError.__init__(self, message="", *, run_id=None, node_id=None, span_id=None, details=None)` **没有 `code` 形参**——`code` 是**类属性**,通过子类覆盖类属性来设(`class SandboxProvisionFailedError(SandboxError): code = "SANDBOX_PROVISION_FAILED"`,与 `errors.py:49-112` 现有 14 个子类一致)。`SandboxError(..., code="...")` 会在运行时抛 `TypeError: __init__() got an unexpected keyword argument 'code'`。这是契约/实现不自洽,且 design 自称"遵循现有 15 个子类的命名 + code 模式"——其实没遵循(现有模式是子类覆盖类属性,而非构造时传 kwarg)。**→ 严重,必须修订**:要么把 4 个 SANDBOX 子类各拆出独立类(匹配 design L651-668 的 `class XxxError(SandboxError): code = "..."` 形式),把 `DockerProvisioner.provision` 里 `SandboxError(code=...)` 全部换成对应具体子类 `SandboxProvisionFailedError(...)`;要么承认基类 `SandboxError` 就带 `code = "SANDBOX_ERROR"`,运行时不传 code——但这样 `SANDBOX_PROVISION_FAILED` / `SANDBOX_DESTROY_FAILED` 等 4 个稳定 code 在 production 路径就永远抛不出来,违背"稳定 code"承诺。前者是唯一正确做法。

- [pass] core/sandbox_contract.py 不 import hanflow.isolation(主路径):组件 #1 的 import 列表(L51-55)只有 stdlib + pydantic,无跨层 import;design L795-796 验收 #2 用 `grep "from hanflow.isolation" hanflow/core/sandbox_contract.py` 做硬守护,正确。**注意**:`SandboxProvisioner` Protocol 字段 `name: str`(L116)是类属性声明形式,与现有 `RuntimeContext` Protocol(声明 `state: NexusState`)同型,合规。

- [pass] isolation/sandbox.py 改 L4→L0 复用:组件 #8 的 `from hanflow.core.sandbox_contract import (ProvisionedSandbox, RunSandbox, ...)`(L498-502)合规;但**注意 ADR-0005 已豁免** `isolation/sandbox.py:29` 的 `isolation → observability` 直连(存量,清零截止 v1.1.0)——本 cycle 把 29 行的 `from hanflow.observability.trace import TraceExporter` 保留是合规的(仍在豁免期内,target_version=1.2.0 但 ADR 的清零截止是 v1.1.0,**此处 design 未提及是否借机清掉此豁免,见轻微项建议 #5**)。

### B. 完整性

- [pass] 接口契约:接口契约表(L577-591)列 12 行,每行有签名 + 落点 + 调用方三列,可追溯。

- [pass] 数据流:DOCKER 全链路(L599-624)与 LOCAL 对照(L628-636)各 6 步,从 `Hanflow.run()` → `build_sandbox` → `provision` → `RuntimeContextImpl` → `tool_call` → `exec_interface.run` → 返回 dict 闭环清晰,字段形状与现有 `_exec_local()` 返回 `{stdout, stderr, returncode}` 同构。

- [partial] 错误处理:错误映射表(L676-682)覆盖 5 个场景 + retryable + 谁抛,粒度合理;但**实例化 API 误用使表里所有 "DockerProvisioner.provision 抛 `SandboxProvisionFailedError`" 的契约在代码示例里都跑不起来**(见 A 类 fail 项)。另:`_LocalExec.run` 的 timeout 分支(L193-194)写 `raise  # 由调用方包成 SandboxTimeoutError`——但 `code_exec.call()`(L462-469)直接 `return await self._exec.run(...)`,**没有任何调用方包装**,design 自相矛盾。这是 B→C 边界的契约缺口(轻微偏严重,并入 C 类 fail 项)。

- [pass] 测试策略:6 档测试金字塔(L694-718)从 fake provisioner 全链路单测、LocalProvisioner 真起 subprocess、DockerProvisioner skipif 守护、类型上移 re-export 回归、charter-check 守护、矩阵新增条目,粒度合适且可执行;测试目录结构(L722-734)清晰。**但**:验收 #5(L799)"现有 `tests/isolation/test_sandbox.py` 4 个调用点 0 改动全绿"——经源码核实,4 处 + `conftest.py:118` 共 5 处 `RunSandbox.create()` 调用点(design L765 迁移矩阵也漏列 `conftest.py:118`,只列了 4 个),`RunSandbox.create()` 在类型上移后仍是同一个类(经 re-export),所以这些调用点确实 0 改动——但 design 的统计口径不一致(目标 #5 说 4 个,矩阵 L765 说 5 个),建议统一为 5 个。

- [pass] 迁移兼容:迁移矩阵(L759-768)8 行,每行有现状 + 迁移后 + 破坏性三列,清晰;`config.yaml` 向后兼容(L776-778)默认 mode=local。

- [partial] 前端影响:design 明确"无前端改动"(L740),正确(本 cycle 只动 SDK + core + isolation + tools);但**遗漏 `cli/` 与 `api/` 影响**:虽然非目标 #6 声明"API/CLI 层的 sandbox 配置端点"留给下个 cycle,但 `cli/` 里若有任何展示 `SandboxMode` 或调用 `RunSandbox` 的命令(本审核未深扫 cli,但建议 design 增加一句"cli/api 不 import SandboxMode/RunSandbox,无影响"作为证据,而非仅声明)。轻微。

### C. 自洽性

- [pass] 主链数据流闭环:DOCKER / LOCAL 两链路输入输出匹配,`build_sandbox` 返回 `tuple[RunSandbox, ProvisionedSandbox]` 与调用方 `self._sandbox, self._provisioned = await build_sandbox(...)`(L403)形状一致;`RuntimeContextImpl.__init__` 新增 `provisioned: ProvisionedSandbox | None = None`(L419)与 `spawn_agent` 新增 `provisioned: ProvisionedSandbox | None = None`(L522)形状一致。

- [pass] 组件依赖无环(主链):core ← isolation ← runtime ← sdk,无环;core 内部 `sandbox_contract.py` 自洽。

- **[fail] `ProvisionedSandbox.exec_interface` 类型前向引用未声明(新引入,C 类)**:组件 #1 的源码顺序(L109-152)是 `SandboxProvisioner`(L109,其 `provision()` 返回类型注解 `-> ProvisionedSandbox`) → `ProvisionedSandbox`(L123,其 `exec_interface: ExecInterface` 字段) → `ExecInterface`(L137)。在文件 `from __future__ import annotations`(L51)开启 PEP 563 字符串注解的前提下,**类型注解层面**自洽(字符串延迟求值);但:
  1. Pydantic v2 的 `BaseModel` 字段解析是**运行时**的——`ProvisionedSandbox.exec_interface: ExecInterface`(L132)在类定义执行时(`model_config = ConfigDict(arbitrary_types_allowed=True)` 已加),Pydantic 会尝试解析 `ExecInterface`,此时 `ExecInterface` 名字若在模块全局已绑定(因为 `from __future__ import annotations` 不影响类体执行顺序,只要 `ExecInterface` 在文件里、模块加载完时定义过即可)→ 实际可工作。**但** Pydantic 对 `Protocol` 类型字段默认会做 schema 校验,`arbitrary_types_allowed=True` 让它放过去——这条勉强成立,**建议 design 显式调换定义顺序**(`ExecInterface` → `ProvisionedSandbox` → `SandboxProvisioner`),消除审稿歧义,与 `core/context.py` 的"`RuntimeContext` Protocol 在前,`FakeContext` 实现在后"惯例对齐。**轻微偏严重**(实际可跑但读起来反直觉),降级为轻微。
  2. 真正的严重问题:`SandboxProvisioner.provision` 的 `name: str`(L116)是 Protocol **类属性声明**,Python Protocol 要求实现类必须有 `name` 实例/类属性——`LocalProvisioner`(L205 `name = "local"`)、`DockerProvisioner`(L251 `name = "docker"`)、`K8sProvisioner`(L333 `name = "k8s"`)都符合,✓。

- **[fail] `spawn_agent` 重写吞掉专用错误子类,且单测守护缺失(回退 direction 严重 #2,C 类)**:
  1. **吞错误**:design L543-547 的 `except Exception as exc: raise HanflowError(f"failed to allocate subdir in container: {exc}", run_id=...) from exc`。这里 `provisioned.exec_interface.run(command=["mkdir", "-p", subdir], timeout=5)` 在 DOCKER 档实际调 `_DockerExec.run`,后者按 design L323 + 错误处理表(L680)应抛 `SandboxTimeoutError`(retryable=True)。但被 `except Exception` 捕获后**重新包成基类 `HanflowError(code="HANFLOW_ERROR", retryable=False)`** —— 这同时违反三条不变量:(a) §2.1 统一错误层级(专用子类被降级);(b) `retryable` 语义被静默翻转(True→False);(c) §5 禁止模式"吞异常"(虽然 `from exc` 保了链,但 code+retryable 信息丢)。**正确写法**:`except (SandboxTimeoutError, SandboxError): raise` + `except Exception as exc: raise SandboxProvisionFailedError(f"subdir alloc failed: {exc}", run_id=...) from exc`。
  2. **dedicated_sandbox 契约回退**:direction 严重 #2 已清零的验收 #8(direction L142)明确"单测验证:dedicated=True 时只多一个 subdir,**container 数量不增**"。但 design 的测试策略(L694-734)与验收标准(L793-801)**都没有**这条单测条目——design 的验收 #5 只验证"4 处 create 调用点 0 改动",没有"container 数量不增"断言。这是 direction 已签字的验收被悄悄丢失,属 C 类自相矛盾(design 自身前后不一致) + E 类历史冲突(与 direction 矛盾)双重属性,按"严重必须回 P3 修订"归类。
  3. 顺带:`spec.dedicated_sandbox and provisioned is not None and provisioned.mode == SandboxMode.DOCKER`(L536)——`AgentSpec.dedicated_sandbox` 是 bool,`provisioned` 是 Optional,这俩在条件里混用,**dedicated_sandbox=True + LOCAL 档**(provisioned != None,mode=LOCAL)走 else 分支(L548-550)落 host subdir,**dedicated_sandbox=True + DOCKER 档**走 if 分支落容器内 subdir——逻辑正确,但**dedicated_sandbox=False + DOCKER 档**呢?也走 else 分支(L549 `subdir = str(run_sandbox.workspace_root / subdir_name)`),但 `run_sandbox.workspace_root` 在 DOCKER 档是 host 路径,子 agent 写到这里**容器内看不到**(容器内只 bind mount 了 `/workspace`)。这是 dedicated_sandbox=False 分支在 DOCKER 档下的隐式数据流断裂,design 未处理。**严重**,因为 direction 非目标 #3 + 目标 #7 都只覆盖 dedicated_sandbox=True,dedicated_sandbox=False 在 DOCKER 档下应是默认共享路径,但 design 的实现让共享路径写到了容器外。

- [pass] 命名一致:`SandboxProvisioner/LocalProvisioner/DockerProvisioner/K8sProvisioner`、`ProvisionedSandbox/ExecInterface`、`build_sandbox`、`SandboxError/SANDBOX_*`、`ToolWhitelistError/TOOL_WHITELIST` 命名风格统一,与既有 `SandboxMode/SandboxResources/RunSandbox` + `errors.py:49-112` 子类模式一致(`XxxError`/`XxxExceeded`)。

- [partial] 错误子类 code 命名模式:现有 14 个 code 全 UPPER_SNAKE_CASE 带领域前缀(`DSL_INVALID` / `MODEL_TIMEOUT` / `MCP_CONN_FAILED` / `TOOL_TIMEOUT` 等)。design 新增 5 个:`SANDBOX_ERROR` / `SANDBOX_PROVISION_FAILED` / `SANDBOX_DESTROY_FAILED` / `SANDBOX_TIMEOUT` / `SANDBOX_DEP_MISSING` / `TOOL_WHITELIST` —— 命名模式完全一致 ✓。**但** retryable 模式:现有 retryable=True 的子类(`ModelTimeoutError` / `RateLimitError` / `ToolTimeoutError` / `MCPConnectionError`)都是网络/限流类瞬时错;design 把 `SandboxDestroyFailedError`(L657)与 `SandboxTimeoutError`(L662)标 retryable=True,把 `SandboxProvisionFailedError`(L652)与 `SandboxDependencyMissingError`(L666)标非 retryable,语义合理(timeout 重试可能换台 daemon、destroy 失败 container leak 重试可能成功;provision 失败通常配置错、dep_missing 需 pip install)。✓。

### D. 复杂度控制

- [pass] K8sProvisioner 占位处理得当:采纳了 direction 审核的 D 类建议(不新开 `k8s_provisioner.py`,而是追加到 `isolation/sandbox.py` 末尾,L325-342),YAGNI 控制到位;`NotImplementedError("...lands in Phase 10")` 满足 CHARTER §4 编码规范"占位代码用明确标记"。

- [pass] 复杂度匹配主题:DOCKER 隔离是生产安全边界,引入 Provisioner Protocol + 类型上移 + 组合根 + 资源限额映射 + 跳过守护测试,复杂度与主题量级相当;`SandboxProvisioner` 与 `ExecInterface` 两层抽象虽多一层,但 design L155-158 论证了"code_exec / shell / 未来 firecracker 复用同一执行接口"的正当性,合理。

- [partial] 顺手清理适度:design 清理 3 处技术债(`CodeExecServer.mode` 词表对齐 / `enforce_tool_whitelist` 专用子类 / `spawn_agent` 取 span_id)。前两条正当(本身就是本 cycle 接触面);第三条"`spawn_agent` 现在用上 span(`as sp`)+ `trace.event(..., span_id=sp.span_id)`"(L527, L555)是顺手扩展观测性,**轻微 YAGNI 嫌疑**——本 cycle 主题是 DOCKER 隔离,span_id 关联观测性不是阻塞功能,但 cost 极低(2 行)且让 trace 更完整,可保留。

- [pass] Pydantic 模型纯数据:`ProvisionedSandbox` 是 BaseModel 持有数据(container_id/exec_interface/workspace_root),provisioner 行为不进模型字段,符合 §2.3;`RunSandbox` 保留 `create()` 作 deprecated shortcut(direction 复审已认 pass 的观察项),design 在 docstring(L91-95)标注了 "deprecated for DOCKER/K8S",降噪到位。

### E. 历史一致性

- [pass] 与 LEARNINGS 一致:命中 LEARNINGS"下次优先[1] DOCKER sandbox 落地"+"高优先级技术债 DOCKER/K8S 占位符";Windows 路径在风险残留(L786)"DOCKER 路径只 Linux 验证,Windows 走 fake + LOCAL"与 LEARNINGS 多次提及的 MSYS/native 路径痛点对齐。

- [pass] 与现有 specs 一致:Phase 8(DOCKER)/ Phase 10(K8S)编号与 `isolation/sandbox.py:1-17` docstring "wired in Phase 8/10" 一致;但 design 的组件 #7(L477)写 "Phase 8 DOCKER landed in cycle 2026-W30-1.1.1" —— 把"Phase 8"与"cycle 2026-W30-1.1.1"绑定的表述是新约定(spec 未明说 cycle↔Phase 映射),不影响合规,但**轻微**:design 应在第一次出现时说明 "Phase 8 = 本 cycle(2026-W30-1.1.1)"的映射,避免读者混淆。

- [pass] code_exec.py:48 文案对齐:direction 验收 #6 已纳入"Phase 7 → Phase 8";design 组件 #7(L477)的 fallback 错误信息改成了 "Phase 8 DOCKER landed in cycle 2026-W30-1.1.1; wire via build_sandbox",比 direction 要求更进一步(直接告诉用户怎么接),合理。**注意**:这条 fallback 在 design 的 `call()` 实现(L473-477)里——但同一文件里 `_exec` 路径(L462-469)走的是 provisioner 注入,**这条 fallback 只在"用户传了 mode='docker' 但没传 exec_interface"时触发**,与现有 `code_exec.py:48` "Phase 7" fallback 语义对齐,✓。

- **[partial] 与 direction 验收 #8 矛盾**:direction 验收 #8(L142)要求"单测验证 dedicated=True 时 container 数量不增",design 验收标准 7 条(L793-801)**未包含**此单测条目。这是 design 漏落实 direction 已签字的验收 → E 类历史冲突,并入 C 类 fail #2 一并修订。

- [pass] 与 direction 严重 #1 清零状态一致:类型上移方案(direction round 2 已清零)在 design 组件 #1 完整落地,SandboxMode/SandboxResources/RunSandbox 三个模型字段与源码 `sandbox.py:32-80` 逐字段核对一致(`cpu_limit="2.0"` / `memory_limit_mb=2048` / `timeout_seconds=3600` / `disk_limit_mb=5120` / `network_egress: list[str] | None = None` 全对;`run_id/mode/workspace_root/container_id/resources/bash_enabled` 6 字段全对),无字段漂移。

- [pass] 与 direction 严重 #2 清零状态**部分一致**:design 组件 #8 的 spawn_agent(L516-556)确实把 `dedicated_sandbox=True + DOCKER` 分支接到了"复用 run container + 容器内 subdir"(L536-547),不再 provision per-agent 容器 ✓;但见 C 类 fail #2 的回退(吞错误 + 单测守护缺失 + dedicated_sandbox=False 分支数据流断裂)。

## 建议修订

1. **(严重 / A 类) 修复 HanflowError 实例化 API 误用**:把 `DockerProvisioner.provision`(L269-274)、`DockerProvisioner.destroy`(L312-318)、`build_sandbox`(L384-388) 三处 `SandboxError(..., code="...", ...)` 全部改为对应具体子类(`SandboxProvisionFailedError(...)` / `SandboxDestroyFailedError(...)`),不传 `code=` kwarg。同时核实 `SandboxTimeoutError` / `SandboxDependencyMissingError` / `ToolWhitelistError` 的抛出点(`_DockerExec.run` / `DockerProvisioner.provision` 顶部 `from aiodocker import Docker` 的 ImportError 包装 / `enforce_tool_whitelist`)也都用子类而非基类 + `code=` kwarg。参考现有 `errors.py:49-112` 14 个子类的写法(只覆盖类属性 `code` / `retryable`,构造函数继承基类)。

2. **(严重 / C 类) 补 dedicated_sandbox 单测守护 + 处理 dedicated_sandbox=False 分支**:(a) 在测试策略(L694-734)新增一档"dedicated_sandbox 契约测试":fake provisioner 记录 provision 调用次数,`spawn_agent(spec.dedicated_sandbox=True)` 后断言 `provisioner.provision.call_count == 0`(容器数量不增)、subdir 落在 `provisioned.workspace_root / "agent-xxx"` 下;(b) 在 design 验收标准(L793-801)新增一条对应 direction 验收 #8 的条目;(c) 处理 `dedicated_sandbox=False + DOCKER` 的数据流:子 agent 共享 run container 时,subdir 应落 `provisioned.workspace_root / subdir_name`(容器内视角,与 dedicated=True 同落点),而非 `run_sandbox.workspace_root / subdir_name`(host 路径,容器内不可见)。建议把 L536 条件改为 `if provisioned is not None and provisioned.mode == SandboxMode.DOCKER:`(去掉 `spec.dedicated_sandbox` 限定),让所有 DOCKER 子 agent 的 subdir 都落容器内。

3. **(严重 / C 类) 修复 spawn_agent 错误包装**:把 L543-547 改为 `except SandboxError: raise` + `except Exception as exc: raise SandboxProvisionFailedError(f"failed to allocate subdir in container: {exc}", run_id=run_sandbox.run_id) from exc`,避免吞掉专用子类的 code/retryable。同时核实 `_LocalExec.run` / `_DockerExec.run` 的 `TimeoutError` 是否在内部就包成 `SandboxTimeoutError`(design L193-194 注释"由调用方包"与 L680 错误表"_DockerExec.run / _LocalExec.run 抛"矛盾,需统一:要么 exec 内部包、要么调用方包,design 必须二选一写清楚)。

4. **(轻微 / C 类) 调换 core/sandbox_contract.py 类型定义顺序**:把 `ExecInterface` 放最前,接着 `ProvisionedSandbox`(其 `exec_interface` 字段引用已定义的 `ExecInterface`),最后 `SandboxProvisioner`(其 `provision()` 返回类型引用已定义的 `ProvisionedSandbox`),消除前向引用歧义,与 `core/context.py` 顺序惯例对齐。

5. **(轻微 / B 类) 统计口径统一**:把"4 处 RunSandbox.create() 调用点"全部改为"5 处"(含 `tests/conftest.py:118`),design L94、L765、L799 三处统一。

6. **(轻微 / B 类) 补 cli/api 影响证据**:在"前端影响"章节(L738-740)或新增"CLI/API 影响"小节,补一句"`hanflow/cli/` 与 `hanflow/api/` 当前不 import `SandboxMode` / `RunSandbox`(经源码 grep 核实),本 cycle 无影响"作为证据,而非仅声明"无前端改动"。

7. **(轻微 / E 类) Phase 8 ↔ cycle 映射说明**:在组件 #7 第一次出现 "Phase 8" 处(L429 或 L477),补一句脚注"本 cycle 即 Phase 8(2026-W30-1.1.1),K8S 为 Phase 10(未来 cycle)",避免读者混淆。

## 摘要(附 design.md 末尾用)

整体需修订(3 严重 / 4 轻微),主题落地与方向承接总体优秀(direction 两个严重问题已被忠实落实),但放行前必须清三个:(1) `SandboxError(..., code="...")` 写法违背 `HanflowError.__init__` 实际签名(`code` 是类属性不是 kwarg),必须改用具体子类;(2) `ProvisionedSandbox.exec_interface` 与 `SandboxProvisioner.provision` 返回类型的前向引用顺序需调换;(3) `spawn_agent` 重写吞掉了 `SandboxTimeoutError` 等专用子类(降级成基类 `HanflowError`,违反 §2.1 + §5),且 direction 验收 #8"container 数量不增"单测守护丢失,dedicated_sandbox=False 在 DOCKER 档的数据流断裂。三条均可在 P3b 修订后清零,无需更换主题或重写组件分解。顺手清理的 3 处技术债(mode 词表 / ToolWhitelistError / span_id)是加分项。

## 复审 (round 2)

- 复审时间: 2026-07-21T14:30:00+08:00
- 复审员: independent subagent (fresh context, round 2)
- 触发: 严重问题修订后重审
- 复审范围: design.md(修订版,874 行)+ cross-check 源码 `core/errors.py:14-42`(HanflowError 签名)、`core/__init__.py:39-71`(__all__ 现状)

### 严重问题 #1 (A 类: HanflowError 实例化 API 误用)
- 判定: **已清零**
- 证据:
  - design.md L719-727 新增"实例化模式"段落,显式说明 `HanflowError.__init__` **不接受 `code=` kwarg**,`code` 是类属性;并给出 ✗ 旧写法 vs ✓ 新写法的对照范例。
  - `DockerProvisioner.provision` 的 DockerError 分支(L301-305)改为 `raise SandboxProvisionFailedError(..., run_id=..., details={...}) from exc`,无 `code=`。
  - `DockerProvisioner.destroy` 的 DockerError 分支(L343-347)改为 `raise SandboxDestroyFailedError(...)`,且注释明确"retryable=True 由类属性定义"。
  - `build_sandbox` 的 fallback 分支(L414-418)改为 `raise SandboxProvisionFailedError(..., run_id=..., details={...})`,无 `code=`。
  - `_LocalExec.run`(L203-207)、`_DockerExec.run`(L263-266)的 `SandboxTimeoutError` / `SandboxDependencyMissingError` 抛出同样不传 `code=`,全部走子类模式。
  - `enforce_tool_whitelist`(L609-612)用 `ToolWhitelistError(...)`,与 errors.py 现有 14 子类"只覆盖类属性"模式一致(对照 `core/errors.py:49-112`)。
- 理由: 逐处核对全文 7 个 `raise XxxError(...)` 落点,无一处传 `code=` kwarg;6 个新错误子类(L691-717)全部以 `code = "..."` / `retryable = True` 类属性形式定义,完全匹配现有 14 子类(`DSLValidationError: code = "DSL_INVALID"` 等)模式。`HanflowError.__init__` 签名(无 `code`)已用源码核实(`core/errors.py:28-42`)。A 类清零。

### 严重问题 #2 (C 类: dedicated_sandbox 回退 + 数据流断裂)
- 判定: **已清零**
- 证据:
  - **数据流条件修正**:design.md L575 的 `spawn_agent` 分支条件已改为 `if provisioned is not None and provisioned.mode == SandboxMode.DOCKER:`,**去掉了 round 1 的 `spec.dedicated_sandbox and` 限定**。L577 注释明确"DOCKER 档下所有子 agent(dedicated 与否)的 subdir 都落 provisioned.workspace_root(容器内视角)"。
  - **dedicated_sandbox=False + DOCKER 分支**:L592-595 的 else 分支只处理 LOCAL/NONE(`subdir = str(run_sandbox.workspace_root / subdir_name)`),DOCKER 档(dedicated 与否)统一走 if 分支 L577 `subdir = str(provisioned.workspace_root / subdir_name)` —— 数据流断裂消除。
  - **container 数量不增单测**(direction 验收 #8 落实):测试策略新增"测试金字塔 #7 dedicated_sandbox 契约单测"(L778-786),双向断言 `dedicated_sandbox=True/False` 时 `provisioner.provision.call_count == 0`,subdir 都落 `provisioned.workspace_root`。
  - **验收标准对应条目**:design.md 验收标准新增第 8 条(L872)"dedicated_sandbox 契约单测守护(direction 验收 #8 落实)",显式引用 direction 验收 #8,E 类历史冲突消除。
- 理由: round 1 的三处病(数据流断裂 / 单测守护缺失 / direction 验收丢失)逐一对应修订;spawn_agent 的条件分支已回归 "DOCKER 档统一落容器内 subdir" 的 per-run 不变量(§2.5);测试金字塔与验收标准都有专门条目把契约钉死。

### 严重问题 #3 (C 类: spawn_agent 吞错误)
- 判定: **已清零**
- 证据:
  - **except 块透传 + 仅包非 Sandbox**:`spawn_agent` L582-591 已改为:
    - L582-584 `except SandboxError: raise` —— 专用子类(`SandboxTimeoutError` 等)直接透传,保留 code/retryable;
    - L585-591 `except Exception as exc: raise SandboxProvisionFailedError(...) from exc` —— 仅包装非 Sandbox 异常;
    - L583/586 行内注释明确"专用子类透传" + "避免吞专用子类"。
  - **exec 内部包 timeout**:`_LocalExec.run` L196-207 在 `asyncio.wait_for` 外层 try/except,`except TimeoutError:` 内部 `raise SandboxTimeoutError(...) from None`,**且 L203 注释明确"内部就包, 不让 TimeoutError 漏给调用方"**;`_DockerExec.run` L267-269 的注释也声明"用 asyncio.wait_for 守护 timeout → 抛 SandboxTimeoutError"。
  - **错误表与代码一致**:错误处理章"错误映射"表 L736 的"谁抛"列写"`_LocalExec.run` / `_DockerExec.run`(**内部包**,不让 TimeoutError 漏给调用方)",与 `_LocalExec.run` 代码注释一致;L742 新增"§5 禁止吞异常(round 1 修订)"段,显式给出正确模式。
  - **验收标准对应条目**:design.md 验收新增第 9 条(L873)"spawn_agent 错误透传",要求单测验证 `SandboxTimeoutError` 不被降级成基类。
- 理由: round 1 吞错误的根因(`except Exception as exc: raise HanflowError(...)`)已彻底清除;`except SandboxError: raise` + `except Exception as exc: raise ... from exc` 是 §5 反吞异常的标准写法;exec timeout 包装点与错误表"谁抛"列自洽,round 1 的 B→C 边界矛盾也一并消除。

### 新引入问题扫描

- **`raise XxxError(...)` 是否都不传 `code=`**: ✓ 全文 7 个抛错点(`DockerProvisioner.provision` L301、`DockerProvisioner.destroy` L343、`build_sandbox` L414、`_LocalExec.run` L203、`_DockerExec.run` L263、`spawn_agent` L587、`enforce_tool_whitelist` L609)逐处核对,无一传 `code=` kwarg;`code_exec.call` 的 L486-488 / L504-507 仍用基类 `HanflowError(...)` 但**不传 `code=`**,且这两个落点是工具层用户面错误(非 sandbox 子系统),用基类不违反 §2.1(基类仍属统一层级),可接受。
- **`ProvisionedSandbox.exec_interface` 字段引用 `ExecInterface` 是否已先定义**: ✓ 组件 #1 的定义顺序已调换为 `ExecInterface`(L113) → `ProvisionedSandbox`(L132) → `SandboxProvisioner`(L146)。L108 与 L162 两处注释明确"定义顺序: ExecInterface → ProvisionedSandbox → SandboxProvisioner,消除前向引用";`ProvisionedSandbox.exec_interface: ExecInterface`(L141)引用已定义名;`SandboxProvisioner.provision(...) -> ProvisionedSandbox`(L155)同样引用已定义名。round 1 轻微 C 类(实际可跑但反直觉)已顺手清掉。
- **`spawn_agent` 的 except 块是否真对 `SandboxError` 子类透传**: ✓ 见严重 #3 证据,L582-584 是 `except SandboxError: raise`。
- **测试策略是否有 dedicated_sandbox 契约单测档 + 验收对应条目**: ✓ 测试金字塔 #7(L778-786)+ 验收标准 #8(L872)双条目。
- **`_LocalExec.run` / `_DockerExec.run` 的 timeout 包装是否在内部完成(与错误表"谁抛"列一致)**: ✓ 见严重 #3 证据。
- **`LocalProvisioner` / `DockerProvisioner` 的 `if mode != SandboxMode.XXX: raise ValueError`**(L221-222、L281-282):这是新引入的输入校验,用 stdlib `ValueError`(非 `HanflowError`)。**判定**:可接受——这是 provisioner 内部编程错(传错 mode 给错 provisioner),应由 `build_sandbox` 的分派逻辑保证不发生;走 stdlib ValueError 不污染统一错误层级(§2.1 约束的是"框架错误"用 HanflowError,内部编程断言用 ValueError/assert 是 Python 惯例)。**轻微提示**(不阻塞):若希望严格统一,可改 `SandboxProvisionFailedError`;但保留 ValueError 也合理,留给 execute 阶段决定。**不构成新严重问题**。
- **`core/__init__.py.__all__` 导出新增错误子类**: round 1 轻微项 B 类("统计口径统一")与 design 验收 #7(L871)"`core/__init__.py.__all__` 追加导出新类型"对应;经源码核实 `__all__` 现导出 14 个错误子类(CLIError 未导出,L109-112),design 新增 6 个错误子类后应在 execute 阶段追加进 `__all__` 的 `# errors` 分组——design 已在验收 #7 钉死,无遗漏。
- **`from aiodocker import Docker, DockerError` 在 `_DockerExec.run` / `DockerProvisioner.provision` 内部 lazy import**: ✓ 与错误表"谁抛"列(L733)"`DockerProvisioner.provision` 顶部 + `_DockerExec.run` 顶部 lazy import"一致;两处 ImportError 都包成 `SandboxDependencyMissingError`(L263-266、L286-289),与 round 1 修订建议一致。
- **`pyproject.toml` 的 `docker` extra**: direction 验收 #10 要求新增 `docker` optional-extra,design 验收未显式列出——但这是 execute 阶段(`pyproject.toml` 改动)的事项,design 已在风险残留隐含(lazy import + SANDBOX_DEP_MISSING 配对),不构成 design 层新问题。

**结论: 无新引入的 A/C/E 类严重问题。** 仅有 1 处轻微观察项(`ValueError` vs `SandboxProvisionFailedError` 在 provisioner mode 校验上的取舍),不阻塞放行。

### 复审判定
- 整体: **通过**(3 严重已清零 / 0 严重剩余 / 1 轻微观察项不阻塞)
- 后续: **放行进 GATE2(P4b/code 阶段)**

round 1 三个严重问题全部按建议精确修订到位(实例化 API 改用具体子类、定义顺序调换、except 块透传 + 内部包 timeout、dedicated_sandbox=False 分支修正、测试与验收双条目补齐),并顺手清掉了 round 1 的 2 个轻微项(前向引用顺序、cli/api 影响证据已补 L810)。design.md 现版本自洽、契约可执行、与 direction 14 条验收一致、与 CHARTER §2/§3/§5 合规,可进入实现阶段。
