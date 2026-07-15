# P8. RELEASE — 版本号 + GitHub 同步 + 官网同步

## 前置条件
- state.yaml.phase == "release" 且 gate3 已 approved
- feature 分支代码已测试全绿

## 执行步骤

1. 判断 site_sync_needed (扫描 feat:/BREAKING commits)
2. 版本号更新: bash scripts/version-bump.sh (spec §5.3)
3. GitHub 同步: bash scripts/github-sync.sh (spec §5.4)
   - Phase A: hanflow (merge + tag + push 到所有 remote)
   - Phase B: hanflow-evolve 自身 commit + push
4. 若 site_sync_needed == true → 执行官网同步 (见下方详细清单)
5. (可选) gh release create (config.release.create_github_release)
6. 写 state.yaml: phase=learn, site_sync_needed
7. Commit, 自动进入 P9

## 官网同步清单 (site_sync_needed == true 时必须执行)

**关键: 每次有用户可见新特性,官网文档必须同步更新,否则用户无法知道新功能。**

### Step 1: 版本目录创建
```bash
cd E:/opensource/hanflow-site
mkdir -p content/<target_version>/en content/<target_version>/zh
# 从上一版本复制全部 MDX 作为基线 (若已有则跳过)
```

### Step 2: 版本清单更新
- 更新 `lib/versions.ts`: VERSIONS 数组 + LATEST_VERSION
- 更新 `tests/versions.test.ts`: 对应断言
- 更新 `package.json`: version 字段

### Step 3: 文档内容检查与更新 (核心步骤)
**逐项检查本周期的新特性是否需要文档更新:**

- [ ] **是否有新增 CLI 命令?** → 更新/新建 `api-reference/cli.md`
- [ ] **是否有新增 API 端点?** → 更新 `api-reference/rest.md`
- [ ] **是否有新增/修改节点类型?** → 更新 `core-concepts/nodes.md`
- [ ] **是否有新增配置项/provider/backend?** → 更新 `configuration.md` + 对应 core-concepts
- [ ] **是否有 DSL 语法变化?** → 更新 `core-concepts/dsl-syntax.md`
- [ ] **是否有新增/修改 WebSocket 事件?** → 更新 `api-reference/websocket.md`
- [ ] **是否有新增/修改错误码?** → 更新 `api-reference/error-codes.md`
- [ ] **是否有 Web Studio UI 变化?** → 更新 `web-studio/*.md`

**重要**: 双语对等 — 每个改动的文档 en 和 zh 都要更新。

**检查方法**: 读 hanflow feature 分支的 `git log` 提取 feat:/BREAKING commits 的描述,
对比官网现有文档,找出差异。

### Step 4: sidebar 更新 (若有新文档页)
- 若 Step 3 新建了文档页 → 更新 `lib/docs.ts` 的 GROUP_ORDER (加 file + title)

### Step 5: 站点文案更新 (若显著特性变化)
- 更新 `messages/en.json` 和 `messages/zh.json` 的 features 区块
- 更新 `components/landing/QuickDemo.tsx` (若有命令/URL 变化)

### Step 6: 构建验证
```bash
cd E:/opensource/hanflow-site
npm test          # versions + docs 测试
npm run build     # 静态站点构建 (Vercel 会跑这个)
```
失败则修复。

### Step 7: Push
```bash
git add -A
git commit -m "docs: sync site to v<target_version> — <主题>"
git push origin main
```

## 不同步时
site_sync_needed == false (纯 fix/refactor):
- state.yaml.site_sync_needed = false
- Gate 3 确认时告知用户"官网不变"
- 跳过官网同步,直接完成 P8
