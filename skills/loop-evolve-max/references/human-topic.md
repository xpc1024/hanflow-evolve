# P2b. HUMAN_TOPIC — 开发者主题 + 核心标记 (max 版: 委托 + 追加)

> 委托 loop-evolve human-topic.md 主体;追加核心领域人工标记。

## 执行步骤

1. 【委托主体】读 loop-evolve 的 human-topic.md 并执行,
   执行前将 `state.yaml` 全局替换为 `state-max.yaml`(其余字面量保持不变,均为共享 infra)。
   loop-evolve reference 路径解析(取先找到者):
   - 优先 `~/.zcode/skills/loop-evolve/references/human-topic.md`
   - 回退 `$EVOLVE_HOME/skills/loop-evolve/references/human-topic.md`
   完成开发者主题选择(target_theme 落定)。

2. 【max 追加·核心标记】用 AskUserQuestion 询问:
   "本周期是否涉及核心领域(触及 core/runtime/isolation/persistence/memory 包,或安全边界面)?
   标记为核心将额外引入安全专家与性能专家。"
   选项:
   - 标记为核心(force-overview):写入 state-max.yaml pending_core_override=true
   - 不标记(交由 P3 自动判定):pending_core_override=false

   说明(对用户可见):自动检测是主;人工标记只能强制为 core,不能把自动判 core 的降级。

3. 写 state-max.yaml:
   `bash scripts/write-state.sh state-max.yaml pending_core_override <true|false>`
   (若用户未响应, 默认 false, 交 P3 自动判定)

4. 进入 P3(读 max/references/plan.md)
