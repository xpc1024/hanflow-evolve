# Design Audit — 2026-W37-1.3.0 · MCP remote transport

- **审核对象**: cycles/2026-W37-1.3.0/design.md (概要设计, MCP remote transport, 基于 mcp SDK 2.2.0 实测)
- **上游约束**: direction.md (Gate1 已批) / LEARNINGS.md 框架架构模式 / CHARTER.md
- **交叉验证源码**: transport.py / bus.py / builtin/base.py / core/errors.py / test_transport.py / config.py / pyproject.toml / tests/tools/{test_bus.py,conftest.py} / docs/adr/
- **审核日期**: 2026-09-08 (独立审核, 未参与编写)

## 审核结论

- **整体: 需修订 (1 严重 / 8 轻微)**

1 个 C 类自洽性缺陷必须回炉: WebSocket 占位的 `NotImplementedError` 会穿透
`MCPBus.start()` 的 `except HanflowError` 隔离层, 使总线启动崩溃, 与设计自身引用的
"failures are isolated, never block the bus" 契约直接冲突。修复简单(start() 补一类
捕获即可), 但属组件交互级缺陷, 须回炉修订设计文本后再进 P6。
其余为完整性与实现细节级轻微项, 可在修订时顺手补齐。

现状陈述逐条核实结果(设计对源码/仓库的声明全部属实):

| 设计声明 | 核实结果 |
|---|---|
| bus.py `start()` 是 no-op、`_external` 恒空、注释 "Task 2" | ✅ bus.py:72-75, :65 |
| `MCPConnectionError` 既有 (MCP_CONN_FAILED, retryable=True) | ✅ errors.py:92-94 |
| ToolDescriptor 字段 name/server/description/input_schema/output_schema(+annotations default {}) | ✅ base.py:15-21 |
| 存量 `ValueError` 共 6 处(四传输 + inprocess 缺 builtin + unknown transport) | ✅ transport.py:90/99/108/117/130/142 |
| 既有 2 处断言需更新 | ✅ test_transport.py:8(inprocess→MCPConfigError) + :36-42(stdio 命令不存在; 现状靠 mcp 未安装的副作用才 pass, 装依赖后必红——设计改断言是必要的) |
| "全仓 grep 无其他 ValueError 捕获点" | ✅ 仓内其余 `except ValueError`(config.py/expr.py/filesystem.py) 均为各模块自抛自捕, 与 transport 工厂无关 |
| config.py `mcp_servers: dict[str, Any]` | ✅ config.py:91 |
| pyproject 无 mcp 依赖; 版本 1.2.3 | ✅ |
| ADR-0008 编号可用 | ✅ 现有 0001/0002/0006/0007, 0008 为下一编号, 不重用符合规约 |

## 逐项判定

### A. 架构合规性

- [pass] **6 层定位**: 改动落在 tools 层(transport.py + bus.py)与 core 错误层级;
  tools→core 依赖矩阵合法(CHARTER §3 ✓); mcp 作为第三方依赖与 pydantic/langgraph
  同级, 不引入层间横穿; 组合根不涉。
- [pass] **Protocol-based**: `MCPConnection` 五成员签名零变更, AsyncExitStack 把
  SDK 两层 ctx mgr 折叠进扁平 connect/close, 协议边界干净。
- [pass] **HanflowError-only**: 错误矩阵 4 场景全部 `HanflowError` 子类(稳定 code +
  retryable + details), SDK 异常不穿透 transport 边界(外圈 except Exception 兜底,
  因 v2 异常体系分散而放弃按类型捕获, 策略合理)。WS 的 `NotImplementedError` 是
  CHARTER §4 认可的占位标记(非框架错误), 不违反 §2.1——但其与 bus 的交互缺陷见 C-1。
- [pass] **RuntimeContext 注入**: 本设计不碰 ctx, bus 生命周期仍由组合根 start/stop 驱动。
- [pass] **DSL 单一真相源**: YAML `mcp_servers` 结构零变化; `MCPServerConfig.name`
  为 bus 注入字段(default None)非 YAML 字段。
- [pass] **LangGraph 薄运行时**: 不在影响面。

### B. 完整性

- [pass] **覆盖 direction 目标**: 目标 1(四传输真实化)/2(协议五成员)/3(主依赖,
  收紧为 >=2.2.0,<3 兼容 direction 的 >=2.0,<3)/4(错误契约+ValueError 统一)/
  5(ADR-0008, T4 注明固化)/6(测试) 分别由 T2/T4/T1/T5 承接。目标 7(LEARNINGS
  销账)未在 design 出现——属 retro/release 阶段流程任务, direction 验收 9 已锁定,
  可接受(提醒: execute/release 阶段勿遗漏)。
- [pass] **错误处理**: §5 矩阵完整(场景 × 异常 × code × retryable × 抛出层),
  失败路径数据流(§4)与矩阵一致, 闭环。
- [pass] **测试策略**: TDD 先红后绿; stdio 真实子进程(非 mock); 错误路径全覆盖;
  失败隔离测试(坏 server + 好 server 共存); integration marker 与 docker marker
  同策略; 全量门四件套齐。
- [pass] **迁移兼容**: §8 三层刻画(零变化/行为增强/Minor breaking)清晰,
  `except ValueError` 调用方影响面已 grep 核实。
- [pass] **非目标**: design 未重复列出, 引用 direction(direction 有完整非目标节,
  含池化/WS 自研/K8S 等排除项)——规则允许。
- [fail] **direction 风险表核实项未闭环**: 风险表明确要求 "P5 装包核实 v2 移除
  `Mcp-Session-Id` header 后的重连/会话语义并记入 ADR-0008", 设计 §0 实测表
  **无此结论**(仅覆盖 import 路径/签名/异常体系)。P6 前须补记, 否则 ADR-0008
  素材不完整。(轻微)
- [fail] **http 细节缺口**: ① `_open_transport` 的 "factory(headers) 若有
  headers/auth" 中 `auth: str` 如何并入 http_client(Authorization 头?)未定义;
  ② SDK `Tool.annotations`(destructiveHint 等)→ `ToolDescriptor.annotations` 的
  映射缺失, 远端 destructive 语义丢失(当前无行为影响——external 的 HanflowError
  在 bus `except HanflowError: raise` 直通不进重试分支——但语义缺口应显式声明
  "本周期不映射" 或补映射)。(轻微)
- [fail] **http/sse 集成 server 起法未明确**: direction 验收 2/3 要求 http 对本地
  测试 server 真实工作, T5 只说 "http/sse 真实链路 @integration", 未写 server
  fixture 如何起(mcp SDK server 侧 streamable-http 挂载方式)。(轻微)

### C. 自洽性

- [fail] **WS 占位与 start() 隔离契约冲突 (严重)**: T3 `start()` 对每个非 lazy
  external 执行 `await conn.connect(cfg)`, 仅 `except HanflowError → logger.warning`;
  而 `WebSocketConnection` override `connect()` 抛 `NotImplementedError`(非
  HanflowError)。`lazy` 默认 False → 用户配置 websocket server 时 NotImplementedError
  穿透 start() → **总线启动崩溃**, 恰好违反设计 T3 自己引用的 bus.py docstring
  契约 "failures are isolated, never block the bus"。direction 验收 4 只要求
  "connect 抛 NotImplementedError", 未处理 bus 侧交互, 设计照抄而漏。须补:
  start() 的隔离捕获扩为 `except (HanflowError, NotImplementedError)` 或等效方案,
  并同步补 T5 断言(WS + 非 lazy 不阻断其余 server 启动)。
- [pass] **AsyncExitStack 半开栈回滚**: 三阶段失败(transport 进入失败 = 空栈
  aclose 无害 / ClientSession 进入失败 = 回滚 transport / initialize 握手失败 =
  回滚两层)均正确回滚; `_validate_config` 置于 try 外直抛不吞, MCPConfigError
  语义(非重试配置错)与 retryable 标志一致。
- [pass] **close 幂等**: `if self._stack: aclose()` + 置空 + `_healthy=False`,
  二次 close no-op; stop() 重复调用亦安全(连接层幂等)。
- [pass] **未 connect 就 call_tool**: 明确 "未连接 → MCPConnectionError",
  health 守卫闭环。
- [pass] **T2/T3 name 注入时序**: bus `__init__` 中 build 后回填 `cfg.name = name`,
  `_RemoteConnection` 持 config 引用(Pydantic v2 模型默认可变), start/connect 时
  `self.config.name` 已就位, `ToolDescriptor(server=...)` 取值正确; build 先于回填
  因引用共享无时序问题。
- [pass] **lazy 与 _find_tool 交互**: lazy connect 延迟至 bus 的 tool_call/list_tools
  首次访问, 先于 `_find_tool` 的 `conn.list_tools()` 执行, 时序成立。但
  "(同 try/except 隔离)" 在 tool_call 语境有歧义: 单次 tool_call 中 lazy connect
  失败应抛 `MCPConnectionError` 冒泡(而非 start 式 logger.warning 吞掉——吞掉后
  _find_tool 报 "未连接", 丢失真实失败原因)。修订时补一句澄清。(轻微澄清)
- [pass] **接口输入输出匹配**: list_tools 返回 list[ToolDescriptor] 是 Protocol
  list[Any] 的收窄(协变, mypy 合法); ToolDescriptor 必填字段(name/server/
  description/input_schema)在适配器中全部供给; streams[0]/streams[1] 下标取法兼容
  sse 三元组; call_tool 返回 structured_content|content 与 bus `ToolCallResult.output:
  Any` 匹配。附注: `connect(config)` 参数被忽略而用 `self.config`(协议零变更下
  的取舍, bus 传同一 cfg 对象无实际分歧), 建议 docstring 注明参数仅保协议兼容。
- [pass] **组件依赖无环 / 数据流闭环 / 命名一致**: T1←T2←T3 单向; §4 数据流
  YAML→bus→connect→list/call→stop 闭环含失败路径; 错误类名与 code
  (MCP_CONFIG_INVALID/TOOL_EXEC_FAILED/MCP_CONN_FAILED) 与既有 CONFIG_INVALID/
  TOOL_TIMEOUT 风格一致。
- 附(实现注意, 不单列 fail): connect 失败路径未置空 `self._session`(残留已关闭
  session 引用, health 守卫下无实际危害); 未 close 直接二次 connect 的语义未定义
  (建议 docstring 声明或加守卫)。

### D. 复杂度控制

- [pass] **AsyncExitStack 桥接是必要复杂度**: SDK 是两层 async ctx mgr, 协议是扁平
  生命周期, ExitStack 是最小适配手段, 非过度设计。
- [pass] **模板方法收敛**: 子类仅 override `_validate_config` + `_open_transport`
  两个 hook, 差异面最小。
- [pass] **YAGNI 守住**: 无池化/无重连管理器/无 list_tools 缓存(direction 非目标
  明确排除); MCPServerConfig 仅增 1 字段。
- [pass] **复杂度匹配主题**: 五任务(T1-T5)对 minor 版本体量恰当, WS override
  connect 的理由(基类会吞异常)成立。

### E. 历史一致性

- [pass] **Pydantic Protocol 字段 Any 先例**: `MCPServerConfig.name: str | None`
  非协议字段, 不触发 SchemaError 问题。但 `_session: Any` 引用 "LEARNINGS 先例"
  不精确——该先例(2026-W30)条件是 **Pydantic 模型持 Protocol 字段**, 而
  `_RemoteConnection` 是普通类, 且 mcp 自带类型并已升主依赖, 可直接精确注解
  `ClientSession`。用 Any 不违规(strict 可过), 但先例引用理由错误且放弃免费类型
  安全, 建议改精确注解或改引 "SDK 边界隔离" 理由。(轻微)
- [pass] **异步优先**: 新增/改造 API 全部 async, 无同步回退。
- [pass] **Windows 路径规则**: "容器内路径字符串拼接" 规则不适用(stdio 子进程是
  本地进程, 非容器内路径); direction 风险表已列 Proactor 兼容 + fixture 本机实跑
  + skipif 缓解, 与 LEARNINGS 环境教训一致。
- [pass] **不与 LEARNINGS 冲突**: 占位规范(NotImplementedError 带原因消息)、
  错误上下文 details、StrEnum/Literal、`X | None` 风格均符合; 错误子类经类属性
  覆盖 code/retryable(与 Sandbox 层级 2026-W30 模式一致, 无 code= kwarg 误用)。
- [pass] **不与现有 specs 冲突**: ADR-0008 编号正确; ValueError→MCPConfigError 属
  异常契约变更, 已由 direction(Gate1)授权 + §8 CHANGELOG minor breaking 注明,
  YAML 键零变化不触发 CHARTER §6 第 7 类人工 Gate 清单。
- 附(实现核实项): `ClientSession(..., read_timeout_seconds=self.config.timeout_seconds)`
  传 int; v1 该参数注解为 `timedelta | None`(运行时 anyio 容忍数值, 但 mypy
  strict 可能报 arg-type)。§0 事实基准未覆盖参数类型, P6 首跑类型门时核实,
  必要时 `timedelta(seconds=...)` 转换。(轻微)

## 建议修订

1. **(严重/C)** T3 `start()` 隔离捕获补 WS 交互: `except HanflowError` 扩为
   `except (HanflowError, NotImplementedError)`(或等效), 并在 T5 增断言
   "websocket + 非 lazy 配置不阻断其余 server 启动"。否则违反 bus.py 既定契约
   "failures are isolated, never block the bus", P6 落地即翻车。
2. (轻微/C-澄清) T3 lazy 分支补一句: tool_call/list_tools 首次访问时的 lazy
   connect 失败**以 MCPConnectionError 冒泡**(不吞), "隔离" 仅适用于 start()
   多 server 并发启动场景。
3. (轻微/B) §0 补记 direction 风险表要求的 `Mcp-Session-Id` 移除后重连/会话
   语义核实结论(或明确标注 "P6 前 ADR-0008 落盘时补"), 闭环 P5 核实项。
4. (轻微/B) T2 补两处定义: ① http `auth` 字段并入 http_client headers 的具体
   方式(如 Authorization: Bearer); ② SDK `Tool.annotations` →
   `ToolDescriptor.annotations` 的取舍(建议本周期显式声明不映射, 或最小映射
   `destructiveHint → annotations["destructive"]`)。
5. (轻微/B) §8 补行为变化说明: config 校验失败从现状 "connect 静默吞 →
   health=False" 变为 "connect 显式抛 MCPConfigError"(bus.start 路径仍被隔离,
   行为等价; 裸用 transport 的路径从静默变显式异常)。
6. (轻微/B) T5 补 http/sse integration 测试的本地 server 起法(一句即可:
   mcp SDK server 侧 streamable-http 挂载, 复用 echo fixture)。
7. (轻微/C-实现注意) T2 代码示意补三处: connect 失败路径置空 `self._session`;
   声明未 close 二次 connect 未定义(或加守卫); docstring 注明 connect(config)
   参数仅为协议兼容、实现以 self.config 为准。
8. (轻微/E) `_session: Any` 改为精确注解 `ClientSession`, 或将引用理由从
   "LEARNINGS 先例"(限 Pydantic 字段)改为 "SDK 边界隔离"; 同时 P6 核实
   `read_timeout_seconds` 的 v2 参数类型(int vs timedelta), 保 mypy strict 绿。
9. (轻微/D-记账) `_find_tool` 每次 tool_call 全量 `list_tools()`, remote 真实化
   后每次调用多一次网络往返(stdio 为本地 IPC 影响小, http 为 RTT)。本周期不加
   缓存是 YAGNI 正确, 建议将 "connection 层 list_tools 结果缓存" 记入 LEARNINGS
   下次优先候选。

---

**判定汇总**: A 类 6/6 pass; B 类 5 pass + 3 fail(均轻微); C 类 7 pass + 1 fail
(严重) + 2 处 pass 附澄清/实现注意; D 类 4/4 pass; E 类 5 pass + 1 处附实现核实。
整体 **需修订**: 1 严重(建议修订 #1, 回炉补 WS/start 交互后即可放行)+ 8 轻微
(#2-#9, 修订时顺手补齐)。设计的 SDK 实测基础、现状陈述准确性、错误矩阵完整度
与复杂度控制均属高质量, 缺陷集中于组件交互边界的单点遗漏。

## 复核 (Round 2)

- **复核对象**: design.md 修订版(2026-09-08, 按 Round 1 建议修订 #1-#9)
- **复核方式**: 逐条对照修订声明 + 交叉检查修订是否引入新缺陷

### 逐条复核

| # | 建议 | 落实情况 | 判定 |
|---|---|---|---|
| 1 | (严重) start() 捕获扩 NotImplementedError + T5 WS 断言 | T3 start() 改为 `except (HanflowError, NotImplementedError) → logger.warning`, 并注明审计依据(websocket 击穿 start() 违反隔离契约); T5 test_bus.py 增 "另配 websocket server 验证 NotImplementedError 不阻断启动"。设计/测试双侧闭环 | **pass** |
| 2 | lazy 失败冒泡澄清 | T3 明确 "lazy connect 失败在调用语境以 MCPConnectionError 冒泡(不吞), '隔离'仅适用于 start() 多 server 启动场景, 吞掉会丢失真实失败原因"。语义精确, 与 bus `except HanflowError: raise` 直通路径自洽 | **pass** |
| 3 | §0 补会话语义核实 + read_timeout 类型 | 新增两行: ① `MCP_SESSION_ID="mcp-session-id"` 实测**仍在**(direction 风险表 "已移除" 的担忧被 P5 实测证伪, 属正常核实产出而非矛盾), resumption/reconnect 由 streamable_http transport 层自动管理、hanflow 无需干预(记入 ADR-0008)——direction 风险缓解项闭环; ② `read_timeout_seconds: float \| None` 实测 float, int 兼容, mypy strict 无需 timedelta 转换 | **pass** |
| 4 | HTTP auth 并入方式 + annotations 最小映射 | HTTPConnection: `factory(headers, auth)`, headers 原样注入, auth(str)并入 `Authorization: Bearer <auth>` 头(复杂 OAuth 留后续); list_tools 适配器增 `t.annotations.destructive_hint is True → annotations={"destructive": True}` 最小映射, 其余 hint 显式声明不映射——与 bus.py:106 `descriptor.annotations.get("destructive")` 的重试豁免键精确对齐 | **pass** |
| 5 | §8 补行为变化段 | 新增 "行为变化(裸用 transport 的路径): 从 'connect 静默吞 → health=False' 变为显式抛 MCPConfigError/MCPConnectionError(bus.start 路径仍隔离, 行为等价)" | **pass** |
| 6 | integration server 起法 | T5 补 "本地 server 用 mcp SDK server 侧 streamable-http 挂载复用同一 echo fixture(P6 探查 mcp.server v2 挂载 API)" | **pass** |
| 7 | connect 失败置空 _session + docstring 两则 | 代码示意: `except HanflowError` 与 `except Exception` 两分支均先 `self._session = None` 再 aclose(不残留已关闭 session 引用); docstring 声明 connect(config) 参数仅协议兼容、以 self.config 为准, 以及未 close 二次 connect 未定义的约定 | **pass** |
| 8 | _session 精确注解 | `self._session: ClientSession \| None = None` + 注释说明 TYPE_CHECKING 导入、运行时零 import(保留 SDK 缺失降级宽松性); 配合 transport.py 既有 `from __future__ import annotations`(PEP 563 字符串注解, 运行时不求值), mypy strict 可解析。read_timeout 类型核实已由 #3 的 §0 新增行覆盖 | **pass** |
| 9 | §9 记账项 | 新增 "## 9 记账项(learn 阶段入 LEARNINGS)": `_find_tool` 全量 list_tools 的 http RTT 放大, 本周期不加缓存(YAGNI), connection 层缓存列为下次优先候选, 执行时机明确 | **pass** |

### 新引入内容交叉检查

- §0 "会话头仍在" 与 direction 风险表 "v2 已移除 Mcp-Session-Id" 表面相反——
  实为 P5 装包核实证伪了 direction 的早期信息, 正是风险表要求的核实动作本身,
  结论(transport 层自动管理, hanflow 无需干预)有实测依据且将记入 ADR-0008。不构成冲突。
- `except HanflowError: self._session = None; await stack.aclose(); raise`:
  初次 connect 失败时 `self._stack` 本为 None, 无残留; 二次 connect 场景已由
  docstring 约定未定义。自洽。
- annotations 映射伪码 `t.annotations.destructive_hint is True` 在 SDK Tool 的
  `annotations` 为 None(未提供)时需 None 守卫(`if t.annotations and ...`)。
  属伪码级实现细节: T5 stdio 集成测试(echo fixture 不带 annotations)首跑必然
  暴露并纠正, 映射语义本身无歧义。**不构成修订要求**, 记为 P6 实现注意。

### 复核结论

- **9/9 全部 pass, 未发现修订引入的新缺陷**。
- **整体: 通过 → 进 Gate2**。
- 遗留事项(不阻塞): ① P6 实现 annotations 映射时补 None 守卫; ② ADR-0008 落盘时
  纳入 §0 会话语义实测结论(transport 层自动管理); ③ release/retro 阶段执行 §9
  记账与 LEARNINGS #3/#5/#9 销账(direction 验收 9)。
