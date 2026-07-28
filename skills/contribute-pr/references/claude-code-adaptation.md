# Claude Code 适配

Claude Code(Anthropic)与 ZCode 的 skill 机制**几乎完全同构**,contribute-pr 无需任何
格式翻译即可在 Claude Code 直接使用。本文件只记录细微差异。

## 格式兼容性(零翻译)

| 项 | ZCode | Claude Code | 兼容 |
|----|-------|-------------|------|
| skill 目录 | `~/.zcode/skills/<name>/` | `~/.claude/skills/<name>/`(或项目 `.claude/skills/`) | 路径不同,格式同 |
| frontmatter | `name` + `description` | `name` + `description` | ✓ 完全一致 |
| 文件名 | `SKILL.md` | `SKILL.md` | ✓ |
| 触发 | `/contribute-pr` 或 Skill 工具 | `/contribute-pr` 或 Skill 工具 | ✓ |
| 子任务并行 | `Agent` 工具 | `Task` 工具 | 仅工具名差异 |

**结论**:contribute-pr 的 SKILL.md / references / scripts 在 Claude Code 下**直接可用**。

## install.sh 对 Claude Code 的处理

install.sh 优先装到 `~/.zcode/skills/`,但若检测到 `~/.claude/` 存在,也会装到
`~/.claude/skills/`(具体见 install.sh 的 `detect_skills_dir` 与主流程)。两个目录都装
确保 Claude Code 用户能用。

## 唯一需注意的差异

### 1. 子任务工具名

contribute-pr 委托 loop-evolve 的 references 里会写"用 Agent 工具并行"或"调用子 agent"。
在 Claude Code 里,对应工具是 **`Task`**(不是 `Agent`)。Claude Code 执行时自动映射,
无需用户干预,但若 skill 文字硬编码"Agent 工具",Claude Code 用户需理解为"Task 工具"。

### 2. superpowers 生态

loop-evolve 委托的 `superpowers:test-driven-development`、`superpowers:systematic-debugging`
等 skills,Claude Code 用户需自行安装 Anthropic 的 superpowers skill 包(若想用原生版)。
未安装时,这些步骤降级为按文字描述执行(和 Codex 一样的降级行为)。

### 3. 项目级 skill

Claude Code 支持项目级 `.claude/skills/`(优先级高于用户级)。若贡献者在 hanflow 仓库根
放了 `.claude/skills/contribute-pr/`,会覆盖用户级。一般用用户级即可,无需项目级。

## 验证 Claude Code 下可用

```bash
# 安装后, 在 Claude Code 里:
/contribute-pr status
# 应打印当前 state (若刚装, 显示"无 state, 从 scan 开始")
```

若提示"skill not found",确认 `~/.claude/skills/contribute-pr/SKILL.md` 存在
(install.sh 应已装)。
