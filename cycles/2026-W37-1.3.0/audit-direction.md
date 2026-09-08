# Audit — direction.md (2026-W37-1.3.0 · mcp-remote-transport)

- **审核对象**: `cycles/2026-W37-1.3.0/direction.md`
- **审核员**: 独立 subagent(未参与编写),spec §4b.2 Layer 2 语义审核
- **日期**: 2026-09-08
- **Layer 1 脚本结果**:
  - `audit-rules-check.sh direction` → OK(章节完整)
  - `charter-check.sh --doc` → **WARN: 提及架构变更(主依赖新增)但无 ADR 引用** → E 类裁定见下

## 审核结论

- **整体: 需修订 (2 严重 / 4 轻微)**

严重问题集中在: ① TransportKind 命名断裂(`streamable_http` vs 现有公开契约 `"http"`),牵动 CHARTER §6 第 7 类触发判定; ② 新主依赖 + WebSocket 永久占位决策缺 ADR(charter-check --doc 已 WARN)。按 spec §4b.4,有严重问题 → 回 P3 修订,不占 audit_retry_count。

背景核实(交叉验证文档陈述,全部属实):

| 文档陈述 | 核实结果 |
|---|---|
| `transport.py:75` call_tool NotImplementedError、四子类空壳、`_build_client` 返回占位 dict | ✓ 属实(transport.py:63-75) |
| pyproject 无 mcp 依赖 | ✓ 属实 |
| LEARNINGS #5 pytest-cov 已修 | ✓ 属实(pyproject:26 `pytest-cov>=4.0` + coverage 配置 93-112 行) |
| #9 update-backlog Done 段保留已修 | ✓ 属实(BACKLOG.md:80 有 Done 段,脚本 213 行) |
| version-bump 对齐 5 处 | ✓ 属实(脚本头注释「4 处 + state.yaml.current_version」;LEARNINGS 旧文「4 处」已被 W34 修订条目取代,direction 采信最新,正确) |
| mcp SDK v2 已 GA(2026-07-28),支持 stdio / Streamable HTTP / SSE-legacy,无 WebSocket | ✓ 外部核实属实([pydantic.dev](https://pydantic.dev/articles/mcp-python-sdk-v2-beta) / [官方 what's-new](https://py.sdk.modelcontextprotocol.io/whats-new/) / [GitHub](https://github.com/modelcontextprotocol/python-sdk));另核实到 v2 移除 Streamable HTTP 的 `Mcp-Session-Id` header,属文档未列的破坏性细节,已被「P5 装包核实」风险项覆盖 |
| integration marker 与既有策略一致 | ✓ 属实(pyproject:65 已有 integration marker 定义) |

## 逐项判定

### A. 架构合规性

- [pass] **6 层定位 / 依赖方向**: 改动全部落在 tools 层(transport.py + 测试 + fixture),tools 只依赖 core 与第三方(pydantic/mcp)。mcp 是外部依赖非层间依赖,不触碰 §3 矩阵 tools 行(仅 ✓ core)。影响模块表无越层项。
- [pass] **Protocol-based**: 目标 2 明确保留 `MCPConnection` Protocol 五成员(connect/list_tools/call_tool/close/health),`build_connection` 工厂签名与返回契约不变,inprocess 分支不受影响。
- [pass] **HanflowError-only 错误契约**: 目标 4 + 验收 5 明确「包装 HanflowError(code+retryable+上下文)、不裸抛 SDK 异常」,风险表第 4 行还自查了「SDK 异常穿透」并把包装边界列为 P4b 核查项。主路径覆盖充分。(存量 `ValueError` 路径的一致性问题见 B 类与建议 3,不构成本项 fail。)
- [pass] **RuntimeContext 注入**: transport 无 ctx 需求,不新增跨层 import,无反向依赖。
- [pass] **DSL 单一真相源**: 本周期不动 DSL schema、不加删节点类型。(TransportKind 字面量是否变更的问题在 C 类裁定,A 项本身无 DSL 改动计划。)
- [pass] **LangGraph 薄运行时**: 未触碰运行时层,n/a。

### B. 完整性

- [pass] **覆盖 direction 全部目标**: 目标 1-6 与验收 1-8、影响模块表一一对应;销账项 #3/#5/#9 在验收 8 闭环。
- [pass] **有错误处理**: 目标 4 + 验收 5(命令不存在/URL 连不上 → HanflowError + health=False)。轻微缺口见建议 3(未覆盖 config 字段缺失路径)。
- [pass] **有测试策略**: TDD、stdio 真实子进程 server fixture、http/sse 走 integration marker(与既有 docker marker 同策略,pyproject 已注册)、错误路径、WS 占位断言;风险表含 Windows Proactor loop 的平台 skipif 预案。具体可执行。
- [fail] **有迁移兼容**: **缺失**。文档通篇用 `streamable_http` 指称 http 传输,但现有公开契约是 `TransportKind = Literal["stdio","sse","http","websocket","inprocess"]`(transport.py:15)——二者映射关系(保留 `"http"` 仅语义升级,还是新增 `"streamable_http"` 字面量并弃用旧值)未定义。若后者,即 YAML 配置值变更 → CHARTER §6 第 7 类触发(须 ADR + 人工 Gate),direction 只字未提;若前者,文档命名应显式写明映射。此外也未评估新主依赖对安装面的影响(mcp 进入 `[project].dependencies`,所有用户无条件背上其传递依赖树;对比 aiodocker 走 optional extra 的先例)。
- [pass] **有非目标**: 8 项,边界清晰(K8S/DOCKER 镜像/Group B CLI/stub-tools/WS 自研/Phase 17 占位/evolve 工具链),与「下次优先」清单的其余条目对得上。

### C. 自洽性

- [pass] **接口输入输出匹配**: `MCPConnection` 五成员与验收 1-4 的 connect→list_tools→call_tool→close→health 链路吻合;`MCPServerConfig` 字段(command/args/env/url/auth/headers/timeout)足以支撑三传输。
- [pass] **组件依赖无环**: hanflow 侧 3 文件 + 新 fixture,自包含;bus 的 `_InProcessConnection` 引用路径不变。
- [pass] **数据流闭环**: YAML config → MCPServerConfig → build_connection → SDK session → list_tools/call_tool 结果回 bus;失败 → HanflowError + health=False;close → health=False。验收 1 即闭环断言。
- [fail] **命名一致**: 目标 1 / 路径 A / 验收 2 均写 `streamable_http`,而现有代码与测试(transport.py:15、tests/tools/test_transport.py:18-21)用 `"http"`。文档内部命名与代码公开契约断裂,且该选择直接决定是否触发 §6 第 7 类(YAML 配置键变更 → ADR + 人工 Gate)。direction 必须显式声明二选一并给出理由。另注意: 验收 4 要求 WS「connect 抛 NotImplementedError」,而现状 `connect()` 是吞异常置 `_healthy=False`(transport.py:56-61),WS 子类需 override connect 才能满足——设计上自然,但属隐含约束,direction 宜点明。

### D. 复杂度控制

- [pass] **无过度设计 (YAGNI)**: 正确拒绝自研协议层(路径 C)与 stdio-only(路径 B,理由「remote 主题名不副实」成立);三传输全走 SDK 现成 API,hanflow 侧仅做生命周期桥接。
- [pass] **复杂度匹配主题**: 三传输 + WS 占位 + 销账,体量匹配 minor,符合单主题版本策略。两处轻微瑕疵见建议 4/5: 「连接池」对单 config 单连接的 MVP 是超前提法;sse「emit deprecation 提示」的 emit 通道(log warning 还是 run event)未定义。

### E. 历史一致性

- [pass] **不与 LEARNINGS 冲突**: #3 现状描述与实况吻合;#5/#9 销账有据;async-first(五成员全 async)、占位用带 reason 的 NotImplementedError(符合 CHARTER §4 惯例且文档明确引用)、marker 策略与既有 integration/docker 一致;「5 处版本对齐」采信了 W34 修订后的最新事实而非 LEARNINGS 滞后旧文(正确做法,依据「核实先于计划」有效实践)。
- [pass] **不与现有 specs 冲突**: 未发现概要设计 §5.2 独立原文(transport.py docstring 回链,主仓库无对应文档),唯一相关 spec 为本 direction 归档副本;方向强化 CHARTER §5 第 3 条「工具调用统一走 MCPBus」而非绕过;外部事实(SDK v2 传输矩阵、无 WS)核实无误。
- [fail] **ADR 必要性判定: 需要,而文档未安排**。证据链:
  1. `charter-check.sh --doc` 实跑输出 WARN(架构变更信号无 ADR 引用),信号源即主依赖新增;
  2. mcp 进入 `[project].dependencies` 是与 pydantic/langgraph 同级的**主依赖**(非 aiodocker 式 optional extra),且将成为 §5 禁止模式第 3 条「工具调用统一走 MCPBus」的承重实现——属 CHARTER §6 第 3 类「核心依赖」级决策(新增虽非替换,决策量级等同);
  3. WebSocket **永久**占位是对公开配置面 `TransportKind="websocket"` 的永久契约声明(永不实现 + 保留原因 + 不删字面量),是典型的应固化架构决策;
  4. direction「实现路径」节已备好 A/B/C 备选方案 + 优劣——正是 MADR 强制内容,转写 ADR-0008 成本极低;
  5. 先例标尺: ADR-0006(charter-check 信号语义)/ 0007(脚本 diff 基线修复)等更轻决策均留档,本周期两项决策的重要性不低于先例。

## 建议修订

1. **(严重)** 补 ADR 计划: direction 增加条目「产 ADR-0008: 引入 mcp>=2.0,<3 主依赖(路径 A/B/C 备选沿用实现路径节)+ WebSocket 永久占位决策」,P5 探查完成、P6 编码前产出。若修复建议 2 时选择改名方案,该 ADR 须同时覆盖 §6 第 7 类(YAML 配置值变更),并显式标注需人工 Gate。
2. **(严重)** 定义 TransportKind 命名映射: 显式声明 `streamable_http` 与现有 `"http"` 字面量的关系。推荐:**保留 `"http"` 值不变**,docstring 注明「http = SDK streamable_http 传输」,文档统一措辞为「http(Streamable HTTP)」——零迁移成本、不触发人工 Gate;若坚持新增 `streamable_http` 字面量,则必须补迁移兼容段(旧值 `"http"` 的弃用期/别名)+ 触发建议 1 的 ADR 强化。同时补一句安装面影响评估(mcp 为无条件主依赖 vs optional extra 的取舍理由)。
3. **(轻微)** 错误契约覆盖 config 校验路径: 验收 5 增加一类「config 字段缺失(stdio 无 command / http 无 url)」,并建议实现期顺势将存量 `ValueError`(transport.py:90/98/107/116/129/142)统一为 HanflowError 子类(如 ToolConfigError,非 retryable),消除热路径上的非契约异常。
4. **(轻微)** 「连接池」降格: 路径 A 的「生命周期桥接(连接池/session 上下文/健康态/错误包装)」改为「连接生命周期管理(session 上下文/健康态/错误包装)」,池化留待非目标或后置(单 config 单连接,无池化需求)。
5. **(轻微)** 明确 sse deprecation 的 emit 通道(建议 logger.warning,run event 需 ctx 通道成本更高),以及验收 4 补充「WS 子类需 override connect 以抛 NotImplementedError(现状基类 connect 吞异常)」的实现约束。
6. **(轻微,增强)** P5 核实清单补一条: mcp v2 已移除 Streamable HTTP 的 `Mcp-Session-Id` header(session 管理破坏性变更),装包实测时一并确认重连/会话语义。

---

## 复核 (Round 2)

- **复核对象**: direction.md 修订版(2026-09-08,针对 Round 1 的 6 条建议)
- **Layer 1 复跑**:
  - `audit-rules-check.sh direction` → OK(章节完整;验收扩至 9 条、目标 7 条,编号连续无断)
  - `charter-check.sh --doc` → **OK: architecture change WITH ADR linkage**(Round 1 的 WARN 已消解,ADR-0008 引用被识别)

### 建议逐条复核

1. **(严重1) ADR-0008 — pass**: 目标 5 新增条目(引入 mcp 主依赖 + WS 永久占位,P5 后 P6 前);影响模块表 +`docs/adr/0008-*.md` 行;验收 7 要求 MADR 格式落盘(上下文/备选 A·B·C/决策/后果)。主依赖 vs optional extra 取舍理由已写入目标 3(tools 层框架特性、与 pydantic/langgraph 同级;对比 aiodocker 走 extra)。因采纳「保留 `"http"` 字面量」方案,不触发 §6 第 7 类,无需人工 Gate——与建议 1 的条件分支一致。
2. **(严重2) TransportKind 命名 — pass**: 目标 1 显式声明「`TransportKind` 字面量保持 `"http"` 不变(docstring 注明 http = MCP Streamable HTTP 传输),零迁移成本,不触发 YAML 配置变更」;验收 2 对应固化「`TransportKind` 仍为 `"http"`,现有 YAML 配置零迁移」。文档主体措辞已统一为「http (Streamable HTTP)」(目标 1 / 路径 A / 验收 2)。
3. **(轻微3) config 校验错误路径 — pass**: 目标 4 扩为两类路径(连接/调用失败 + config 校验失败),后者明确「存量 `ValueError` 统一为 `HanflowError` 非 retryable 子类」;验收 5 与影响模块表(+config 校验 HanflowError 化)同步。
4. **(轻微4) 连接池降格 — pass**: 路径 A 改为「连接生命周期管理(session 上下文/健康态/错误包装)」,池化列入非目标(单 config 单连接,MVP 无池化需求)。
5. **(轻微5) sse 通道 + WS override — pass**: sse 明确 `logger.warning`(目标 1 + 验收 3);WS 子类 override `connect()` 主动抛 NotImplementedError、基类吞异常的原因已显式写明(目标 1 + 验收 4),隐含约束消除。
6. **(轻微6) Mcp-Session-Id — pass**: 风险表新增「v2 已移除 Streamable HTTP `Mcp-Session-Id` header(中)| P5 装包核实重连/会话语义并记入 ADR-0008」。

### 回归检查

Round 1 判 pass 的各项未被修订破坏: 改动仍全部位于 tools 层(依赖方向不变)、`MCPConnection` Protocol 五成员保留、错误契约较原版加强、非目标清单扩充、单主题版本策略不变、5 处版本对齐等事实陈述未动。目标/验收因新增 ADR 条目整体重编号(1-7 / 1-9),交叉引用一致。

遗留 2 处笔误级措辞残留(不阻断,Gate 前可顺手清理):
- 风险表「streamable_http 集成测试需 server」一处未统一为「http (Streamable HTTP)」;
- 目标 1 http 条目结尾「— audit 建议采纳)」有一个孤立右括号。

### 复核结论

- **整体: 通过(6/6 pass,0 严重 / 0 轻微新增)→ 进 Gate1**。Round 1 的 2 严重(C4 命名断裂、E3 缺 ADR)与 4 轻微全部解决,Layer 1 客观信号(ADR linkage)由 WARN 转 OK。

---

*审核依据: direction.md、LEARNINGS.md「框架架构模式」、CHARTER.md(§2/§3/§4/§6)、transport.py 现状、pyproject.toml、tests/tools/test_transport.py、BACKLOG.md、version-bump.sh、docs/adr/ 先例(0001/0002/0006/0007 + allow-*),及 MCP SDK v2 外部核实(py.sdk.modelcontextprotocol.io / pydantic.dev / github.com/modelcontextprotocol/python-sdk)。*
