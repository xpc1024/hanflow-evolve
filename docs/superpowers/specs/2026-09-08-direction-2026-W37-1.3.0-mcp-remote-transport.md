# Direction — 2026-W37-1.3.0 · mcp-remote-transport

- **cycle**: 2026-W37-1.3.0
- **theme**: learnings-priority (ai_signal, score 44) — 收敛为子项 learning:3「MCP remote transport 实现」
- **date**: 2026-09-08
- **target_version**: 1.3.0 (minor)

## 动机

learnings-priority 主题聚合 10 条信号,P3 阶段按「单主题版本策略」逐条核实现状后
收敛核心交付(核实记录见 retro 素材):

| learning | 现状核实结论 |
|---|---|
| #3 MCP remote transport | **仍空壳**: `hanflow/tools/transport.py:75` `call_tool` 直接 `NotImplementedError`;Stdio/SSE/HTTP/WebSocket 四个 `_RemoteConnection` 子类仅做 config 校验无任何 IO;`_build_client` 探测 `from mcp import ClientSession` 后返回**占位 dict**;pyproject 无 `mcp` 依赖 |
| #5 pytest-cov | **已修复**(dev 组 `pytest-cov>=4.0` + coverage 配置齐全)— LEARNINGS 滞后条目,本周期销账 |
| #9 update-backlog 清空 Done 段 | **本周期 P2 复现并已修复**(4/4 bats 绿,Done 4 条历史保留)— 销账 |
| #1/#2/#4 (DOCKER 镜像构建/K8S sandbox/Group B CLI) | 确认未做,但均为独立大件,留后续周期 |

「远程 MCP 工具调用生产不可用」是 tools 生态的硬缺口,且连续 2 个周期为
source_stub 高信号(LEARNINGS #3 原文)。官方 `mcp` Python SDK 已出 **v2.0.0**
(2026-07-28 协议修订,支持 stdio / Streamable HTTP / SSE-legacy,无 WebSocket),
依赖与 API 形态均已稳定,实现条件成熟。这正是 v1.3.0 minor 的合适体量。

## 目标 (in scope)

1. `hanflow/tools/transport.py`: `_RemoteConnection` 及四个传输类真实实现——
   - **stdio**: 子进程传输(本地 MCP server),生产可用
   - **http (Streamable HTTP)**: 远程 MCP server 主路径(SDK 官方推荐的生产
     remote 路径)。**`TransportKind` 字面量保持 `"http"` 不变**(docstring 注明
     「http = MCP Streamable HTTP 传输」),零迁移成本,不触发 YAML 配置变更
     (audit 建议采纳)
   - **sse**: legacy 桥接(SDK 仍提供,协议已弃用;连接时 `logger.warning`
     deprecation 提示 — audit 建议 5)
   - **websocket**: 显式保留 `NotImplementedError` 占位(CHARTER §4 惯例;子类
     **override `connect()`** 主动抛出,因基类 connect 现为吞异常置 unhealthy —
     audit 建议 5)
2. `MCPConnection` 协议五个成员(connect / list_tools / call_tool / close / health)
   对远程连接全部真实工作;`list_tools` 返回真实工具清单,`call_tool` 返回真实结果。
3. 依赖: pyproject.toml 增加 `mcp>=2.0,<3`(**主依赖**而非 optional extra:远程工具
   调用是 tools 层框架特性、与 pydantic/langgraph 同级;对比 aiodocker 仅服务于
   DOCKER 沙箱可选档而走 extra。取舍理由固化入 ADR — audit 建议 1/2)。
4. 错误契约: 按 CHARTER 包装 `HanflowError`(带 code + retryable + 上下文),不裸抛
   SDK 异常;`health()` 反映连接活性。覆盖两类路径: **连接/调用失败**(命令不存在/
   URL 连不上)与 **config 校验失败**(stdio 无 command / http 无 url)——后者顺势
   将存量 `ValueError`(transport.py 四传输构造处)统一为 `HanflowError` 子类
   (code 非 retryable),消除热路径非契约异常 (audit 建议 3)。
5. **ADR-0008**: 「引入 mcp>=2.0,<3 主依赖 + WebSocket 永久占位」——实现路径节
   A/B/C 备选即 MADR 素材;P5 探查完成后、P6 编码前产出 (audit 建议 1)。
6. 测试(TDD):
   - stdio 路径用**真实子进程 MCP server**(用 mcp SDK server 侧写 fixture)做
     集成级验证:list_tools 非空、call_tool 真实回显、close 后 health=False;
   - http/sse 用 marker 隔离(`integration`,默认跳过,与既有 docker marker 同策略);
   - 错误路径: 命令不存在/URL 连不上 → HanflowError + health=False;config 缺
     字段 → HanflowError(非 retryable);
   - websocket 占位抛 NotImplementedError。
7. LEARNINGS 销账: #5(pytest-cov)、#9(update-backlog)、#3(本周期完成后);
   signals 相关条目行首 `~~` 标注。

## 非目标 (out of scope)

- K8S sandbox 落地(Phase 10,大工程,需 K8s 环境)
- DOCKER sandbox 定制镜像构建流水线(learning #1)
- CLI Group B 命令后端 metrics/search/eval/datasets/worker(learning #4)
- web_search / vector_search builtin 后端实现(属 stub-tools 主题成员)
- WebSocket MCP 传输自研(官方协议无此传输)
- tools/builtin 其余文件、api/routes/observe.py 的 Phase 17 占位
- 连接池化(单 config 单连接,MVP 无池化需求 — audit 建议 4)
- evolve 工具链其余项: score-signals 解耦(#8)、charter-check 正则(#6)、
  gh release 权限(#7)、环境项(#10)

## 实现路径

- **路径 A — 官方 mcp SDK v2 全量接入 (推荐)**: stdio + http(Streamable HTTP)
  + sse 三传输真实实现,WebSocket 显式占位。SDK 三传输均为现成 API,hanflow 侧
  工作是连接生命周期管理(session 上下文/健康态/错误包装)+ 测试。effort medium、
  risk medium(SDK v2 是 major rework,P5 需装包核实精确 import 路径与 v2 语义)。
- **路径 B — 最小 stdio-only**: 只做子进程传输,http/sse 仍占位。改动最小,
  但「remote」主题名不副实(stdio 是本地子进程),远程工具生态缺口依旧。
- **路径 C — 自研协议层**: 不依赖 SDK,自行实现 MCP JSON-RPC + Streamable HTTP。
  完全可控但重复造轮子,协议演进成本永久背在自己身上,无用户可见增益。

**推荐 A**:生产价值最大、复用官方维护的协议实现,体量匹配 minor。

## 影响模块

| 仓库 | 模块 | 改动 |
|------|------|------|
| hanflow | hanflow/tools/transport.py | `_RemoteConnection` 真实实现 + 三传输 + WS 占位说明 + config 校验 HanflowError 化 |
| hanflow | pyproject.toml | +`mcp>=2.0,<3` (主依赖) |
| hanflow | tests/tools/test_transport.py | 真实 stdio 集成 + 错误路径 + WS 占位断言 |
| hanflow | tests/tools/ (新 fixture) | mcp server 侧 echo fixture(子进程) |
| hanflow | CHANGELOG.md | 1.3.0 minor 段(release 阶段) |
| hanflow-evolve | docs/adr/0008-*.md | mcp 主依赖 + WS 永久占位 (P5 后 P6 前) |
| hanflow-evolve | LEARNINGS.md | #3/#5/#9 销账 |
| hanflow-evolve | scripts/update-backlog.sh + tests | (已完成,Done 段保留修复) |

## 风险评估

| 风险 | 等级 | 缓解 |
|------|------|------|
| mcp SDK v2 major rework,API 与 v1 有 break | 中 | P5 先装包实测 import 路径与 ClientSession 语义,以 v2 迁移指南对照;锁定 `>=2.0,<3` |
| v2 已移除 Streamable HTTP `Mcp-Session-Id` header(会话语义破坏性变更) | 中 | P5 装包核实重连/会话语义并记入 ADR-0008 (audit 建议 6) |
| Windows asyncio 子进程 stdio(Proactor loop)兼容 | 中 | 集成 fixture 先在本机(Git Bash/Windows)真实跑通再固化;必要时 conftest 按平台 skipif |
| http (Streamable HTTP) 集成测试需 server | 低 | 测试 server 用 mcp SDK server 侧同 fixture 起本地 http,marker=integration 隔离 |
| SDK 异常类型穿透破坏 HanflowError 契约 | 中 | 设计阶段明确包装边界(P4b audit 重点核查项) |
| 长连接生命周期泄漏(session 未 close) | 中 | async context manager 模式 + close 幂等 + 测试断言 close 后 health=False |

## 验收标准

1. stdio 集成测试(真实子进程 MCP server): connect → list_tools 返回 ≥1 工具 →
   call_tool 真实调用返回预期结果 → close → health()=False,全绿。
2. http(Streamable HTTP) 对本地测试 server 同链路真实工作(marker=integration,
   离线跳过);`TransportKind` 仍为 `"http"` 字面量,现有 YAML 配置零迁移。
3. sse 传输可构造并给出 logger.warning deprecation 提示(不要求真实 server 集成)。
4. websocket: build_connection 可构造,connect/call_tool 抛 NotImplementedError
   且消息含明确原因(协议无 WS 传输;子类 override connect 主动抛出)。
5. 错误契约: 命令不存在 / URL 连不上 → HanflowError(code 稳定、retryable 合理),
   无裸 SDK 异常逃逸;health()=False;config 缺必填字段(stdio 无 command /
   http 无 url)→ HanflowError 非 retryable 子类(存量 ValueError 一并替换)。
6. `ruff check` + `ruff format --check` + `mypy --strict` 全绿;pytest 全量通过
   (含新增测试;integration/docker marker 默认跳过不计失败)。
7. ADR-0008 落盘(docs/adr/,MADR 格式: 上下文/备选 A·B·C/决策/后果)。
8. 版本 1.2.3 → 1.3.0(version-bump.sh 对齐 5 处),CHANGELOG minor 段自动追加,
   GitHub release + site 同步(release 阶段)。
9. LEARNINGS #3/#5/#9 销账,BACKLOG Done 段追加本周期条目(已修复的脚本应保留历史)。
