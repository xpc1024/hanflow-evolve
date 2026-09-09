# Retro — 2026-W37-1.3.0 · MCP remote transport

- **周期**: 2026-W37-1.3.0 · 主题 learnings-priority → 收敛 MCP remote transport
- **版本**: 1.2.3 → **1.3.0**(minor)· 发布于 2026-09-09
- **Gate**: gate1/gate2 auto-approve(用户无响应,双轮审核通过,留痕);
  **gate3 用户批准**(`loop-evolve gate approve`)
- **retry_count**: 0(全量门一次通过)· audit_retry: direction 1 次回炉(2 严重),
  design 1 次回炉(1 严重)——均为"实现前修复",成本远低于实现后

## 目标达成率

direction 验收 1–9:**9/9 全达成**。
- 三传输真实化 + WS 占位 + bus 接线 + 错误契约 + ADR-0008 + CHANGELOG +
  LEARNINGS 销账(#3/#5/#9)+ BACKLOG Done 保留(脚本修复生效)。
- 唯一减项: gh release create 因权限(LEARNINGS #7 旧账,tag 已推)未建
  Release 页——不阻断,已知项。

## 什么有效 (Keep Doing)

1. **"核实先于计划"再立功**: P3 Explore 核实 10 条 learnings,当场证伪 #5
   (pytest-cov 早已修复)并发现 learning:9 在 P2 复现——选题范围即时收敛,
   还顺手把 update-backlog 缺陷修了(TDD 红→绿)。
2. **P5 装包实测 SDK**: mcp v2 的三处文档失真(import 改名/异常体系/会话头
   "已移除"系误传)全部被实测纠正,design 建立在事实上,后续零返工。
3. **两轮独立审核抓真问题**: direction 2 严重(ADR 缺失、命名断裂)+
   design 1 严重(WS 异常穿透 bus 隔离)都是实现后要翻车的交互级缺陷。
4. **真实子进程 fixture**: echo server 4 工具矩阵(回显/失败/destructive/
   无注解)一次覆盖适配、映射、None 守卫、幂等,Windows/Proactor 实测背书。
5. **Gate3 硬停策略**: 外向不可逆动作(release)前停,用户一条命令恢复,
   自主性与安全性兼得。

## 什么卡住 (Pain Points)

1. **依赖解析三连坑**(T0,约 40min): requires-python 无上界(3.15 split)+
   zhipuai 全系 pin pyjwt<2.9 与 mcp 需求硬冲突 + override 丢 crypto extra
   致 import 失败。解法定型: cap 版本域 + 下界提升 + override-dependencies
   (带 extra)。
2. **write-state.sh 与跨行长值**: gate_status 长注释值经 sed 拆行后留下
   孤立续行,YAML 校验误报两次。教训: state 字段值保持短 token。
3. gh release 权限(#7 旧账确认仍在)。

## token 消耗 (估算, 分阶段)

scan→prioritize 低;P3 核实(Explore 135k)+ P4/P4b 两轮审核(480k+330k+复核)
占大头;P7 编码 + 排障中等;P9/P10 低。审核 subagent 成本 ≈ 编码本身,
但换来的 3 个严重缺陷提前拦截,值。

## 意外发现

1. mcp v2 **会话头仍在**(mcp-session-id),社区"已移除"说法不准——已入 ADR-0008 附记。
2. `create_mcp_http_client` 无公开导出路径(mypy attr-defined),
   `mcp.shared._httpx_utils` 是唯一真实家——SDK v2 rework 的粗糙处。
3. FastMCP → `MCPServer`(v2 改名),fixture 直接用新 API,零阻力。
4. `bus.list_tools()` 聚合语境与指名调用语境的隔离语义差异(聚合跳过坏
   server / 指名冒泡)在实现时才完全显形——design 已预案,实现 3 行落实。

## 下次优先 (→ LEARNINGS 已更新)

DOCKER 镜像构建流水线 / K8S sandbox / Group B CLI / charter-check 正则 /
gh release 权限 / score-signals 解耦 / list_tools 缓存(新增)/ 环境项。
