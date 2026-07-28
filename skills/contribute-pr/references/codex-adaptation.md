# Codex 适配

Codex CLI(OpenAI,2025-12 上线原生 Skills 机制)使用 contribute-pr 的方式。
spec §6.1 早期说"Codex 无原生 skill,只能 AGENTS.md"——**已过时**,Codex 现在有原生 Skills。

## Codex Skills 机制(2025-12+)

| 项 | Codex |
|----|-------|
| skill 目录 | `~/.codex/agents/skills/<name>/`(全局)或 `.agents/skills/`(项目级) |
| 文件格式 | `SKILL.md`,但内容是 **Description/Trigger/Steps 三段**(不是 frontmatter) |
| 触发方式 | 自动发现(按 Trigger 匹配)+ `$skill-name` 显式调用 |
| 查看 | `codex /skills` 列出所有已发现 skill |
| 项目配置 | `AGENTS.md`(类似 Claude Code 的 `CLAUDE.md`,always-read) |

## contribute-pr 的 Codex 安装

install.sh 检测到 `~/.codex` 后会自动:
1. 把 `skills/contribute-pr/` 装到 `~/.codex/agents/skills/contribute-pr/`
2. 把 `skills/contribute-pr/codex/SKILL.md`(Codex 专用格式)**覆盖到顶层** SKILL.md
   (Codex 版用 Description/Trigger/Steps,ZCode/Claude 版用 frontmatter,格式不兼容故分两份)
3. 同时装 loop-evolve(委托依赖)和 charter-check(S0 依赖)

## Codex 触发 contribute-pr

```
# 自动发现(说自然语言)
你说: "给 hanflow 提 PR" / "修这个 issue" / "社区贡献"
Codex 自动匹配 Trigger,调用 contribute-pr

# 显式调用
你说: "$contribute-pr topic 修复 observe.py 的 stub"

# 确认已装
运行: codex /skills
应看到: contribute-pr
```

## 工具映射(Codex 执行 skill 时的工具对应)

contribute-pr 的 SKILL.md / references 里写的操作,Codex 这样映射:

| skill 指令 | Codex 工具 |
|-----------|-----------|
| "调用 Agent / 子 agent / 并行 agent" | Task 工具 |
| "Edit / Write 文件" | apply_patch |
| "执行 bash 脚本" | shell 工具(直接跑 `.sh`) |
| "Read 文件" | Codex 原生读 |
| "调用 superpowers:* skill" | Codex 无 superpowers 生态,跳过或用 AGENTS.md 注入等价指令 |

**注意**:`superpowers:test-driven-development`、`superpowers:systematic-debugging` 等
loop-evolve 委托的 superpowers skills,**Codex 没有原生对应**。Codex 跑 contribute-pr 时
这些步骤降级为"按 TDD/debugging 的文字描述执行",质量略低于 ZCode/Claude(它们有原生
superpowers skill 加持)。这是 Codex 适配的固有损失。

## Fallback:AGENTS.md 片段(若 `codex /skills` 看不到 contribute-pr)

Codex Skills 是实验性机制,若版本旧或安装异常,skill 可能不被发现。此时用 AGENTS.md
注入兜底——把下面片段粘贴到项目根的 `AGENTS.md`:

```markdown
<!-- AGENTS.md 片段(Codex fallback) -->
## Hanflow 社区贡献 skill (contribute-pr)

当用户说"给 hanflow 提 PR""社区贡献""contribute-pr"时,按以下流程执行:

1. 读取 ~/.codex/agents/skills/contribute-pr/SKILL.md(若不存在,提示用户运行
   curl -fsSL https://raw.githubusercontent.com/xpc1024/hanflow-evolve/main/install.sh | bash)
2. 按 SKILL.md 的 Steps 执行,工具映射:
   - "调用 Agent/子 agent" → 用 Task 工具
   - "Edit/Write 文件"    → 用 apply_patch
   - 其余 shell/Read 与 Codex 原生一致
3. 凭证安全声明必须先打印
```

## 两份 SKILL.md 的同步维护

contribute-pr 有两份 SKILL.md:
- `skills/contribute-pr/SKILL.md`(ZCode/Claude,frontmatter 格式)
- `skills/contribute-pr/codex/SKILL.md`(Codex,Description/Trigger/Steps 格式)

**改流程时必须同步两份**。install.sh 把 codex/SKILL.md 覆盖到 Codex 安装目录的顶层,
故 Codex 用户读到的是 codex/ 版。两份内容描述同一流程,只是格式不同。

未来若 Codex 完全兼容 frontmatter(OpenAI 在演进),可合并为一份,删除 codex/ 子目录。
