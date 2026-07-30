# 文档大版本线版本化（Major-Line Versioning）设计

- **日期**: 2026-07-30
- **状态**: 已批准（待实施）
- **作者**: brainstorming 会话产出
- **关联项目**: `hanflow-evolve`（自进化体系 / skills）+ `hanflow-home`（官网文档站）

## 1. 背景与动机

当前 `hanflow-home` 文档按**完整 semver** 分文件夹（`content/1.0.1/`、`1.1.0/`、`1.2.0/`、`1.2.1/`），两个 skill（loop-evolve 的 `site-sync.sh`、contribute-pr 的 `home-sync.sh`）在每次版本发布时无条件执行 `cp -r content/<prev>/ content/<new>/` 建新文件夹，并把新版本塞进 `lib/versions.ts` 的硬编码 `VERSIONS` 数组。

问题：

1. **臃肿**：每个小版本（1.2.0 → 1.2.1）都复制一整棵文档树，长期不可持续。
2. **写死**：`VERSIONS` / `LATEST_VERSION` 是字面量，每次都要手改，违背"复用/不写死"原则。
3. **装饰性下拉**：导航栏 `VersionSelector` 只写 localStorage 不跳转、侧边栏不带版本前缀、旧版不预渲染——点了不切换内容。

目标：采用主流的**大版本线**（major-line）文档模型，小版本原地合并、大版本才开新线，下拉数据驱动且真正可切换，并兼容中英文（en/zh）双语文档。

## 2. 目标与非目标

### 目标
- 文档归档粒度从"每 patch 一个文件夹"改为"每 major 一个文件夹"（`content/<major>.x/`）。
- 小版本（minor/patch）在当前线文件夹内原地合并 en+zh 文档，不建文件夹、不动版本数据、不动下拉。
- 大版本（major bump）`cp -r` 出新线（含 en/zh），旧线冻结，新线成为 latest。
- `lib/versions.ts` 数据驱动生成，skill 不再手写版本数组。
- 导航栏版本下拉做到**真切换**（含大版本线 + locale 双重保留）。
- 改动落项目源 `skills/`，由 `install.sh` 分发；停用 `.agents` 下过期副本。

### 非目标
- 不向冻结的旧线做 backport。
- 不做"该文档在 1.x 不存在"的友好页（旧线缺失文档沿用现有 404 行为）。
- 不引入 VitePress/Docusaurus 重写站点。

## 3. 架构与组件

### 3.1 文件夹与版本模型
- 目录约定：`content/<major>.x/{en,zh}/...`，en/zh 双语树并存。
- 小版本：定位 `content/<major>.x/`，按 `doc-mapping.yaml` 命中文件做 diff 应用，**en 与 zh 两棵树都落盘**。
- 大版本：`cp -r content/<旧major>.x/ content/<新major>.x/`（含 en/zh），旧线冻结。

现有收敛：`1.0.1 / 1.1.0 / 1.2.0 / 1.2.1` 合并为单个 `content/1.x/`，以 `1.2.1`（19 篇，含 `community/`，是超集）的 en/zh 为基底。

### 3.2 `lib/versions.ts` —— 由生成器产出，不写死
**关键修正**：`VersionSelector` 是 `'use client'` 组件，运行在浏览器，无法读服务端文件系统。因此"运行时扫描"不可行，改为**构建前生成字面量**。

新增 `scripts/gen-versions.mjs`（在 `package.json` 的 `"prebuild"` 钩子执行）：
- 扫描 `content/` 下 `^\d+\.x$` 目录，降序排列 → `MAJOR_VERSIONS`。
- 取首项 → `LATEST_MAJOR`。
- 读 `package.json` 的 `version` → `LATEST_SEMVER`（精确发布号）。

生成文件内容（字面量，带"勿手改"头注释）：
```ts
// ⚠️ 此文件由 scripts/gen-versions.mjs 自动生成，请勿手改
export const MAJOR_VERSIONS = ['1.x'] as const;
export const LATEST_MAJOR = '1.x';
export const LATEST_SEMVER = '1.2.1';
```

收益：skill 在 major bump 时只 `cp -r` 出新目录，下次 build 下拉自动多一项——真正的"不写死"。`LATEST_SEMVER` 由 `package.json` 驱动，skill 无需维护此行。

### 3.3 路由解析 `resolveVersion()` —— 向后兼容旧 semver URL
位于 `lib/versions.ts`，被 `app/[locale]/docs/[[...slug]]/page.tsx` 使用：
- 首段匹配 `<major>.x`（如 `1.x`）→ 版本 `1.x`。
- 首段匹配旧 semver `^\d+\.\d+\.\d+$`（如 `1.2.1`）→ 归到对应 major 线 `<major>.x`，正常渲染。
- 否则 → `LATEST_MAJOR`。

这样**免 redirect 配置**即解决旧 SEO 链接，en/zh 通用（locale 在独立的 `[locale]` 段，不受影响）。

旧 semver URL 不在 `generateStaticParams` 内，靠 Next.js 默认 `dynamicParams: true` 在 Vercel 按需渲染（旧链接量少，可接受）。

### 3.4 真切换的导航栏下拉（i18n 关键）
`components/layout/VersionSelector.tsx`：
- 用 `usePathname()` 解析当前 `locale + version + slug`。
- 点选目标大版本 → 构造 `/${locale}/docs/${targetVer === LATEST ? slug.join('/') : [targetVer, ...slug].join('/')}` 并 `router.push()`。
- **保留 locale**：`/zh` 切版本停在 `/zh`，`/en` 同理。
- localStorage 仍写（持久化），但 URL 成为主权来源。

### 3.5 静态预渲染
`app/[locale]/docs/[[...slug]]/page.tsx` 的 `generateStaticParams` 覆盖 **所有大版本线 × {en,zh} × 全部 slug**，让 `1.x` 与将来的 `2.x` 都能真切换且可预渲染。

### 3.6 侧边栏
- `lib/docs.ts` 现有 `{en,zh}` 本地化标题是**版本无关**的，无需按大版本复制。
- `buildSidebarTree(root, version, locale)` 的 `version` 入参从 semver 改为 `1.x`。
- `components/docs/Sidebar.tsx` 链接补上版本前缀（latest 线不加前缀），避免切到 `1.x` 时链接串到 latest。

## 4. 两个 skill 的改造

统一语义，两端（site-sync / home-sync）都同步改造：

- **去掉**无条件 `cp -r content/<prev>/ content/<new>/`。
- 复用 contribute-pr 现有 S0.5 semver 判定区分 bump 类型：
  - **minor/patch**：定位 `content/<major>.x/`，合并 **en+zh**（按 `doc-mapping.yaml` 命中文件做 diff 应用）；不动 `versions.ts`、不建文件夹。
  - **major**：`cp -r` 出新线（含 en/zh），合并到新线；`versions.ts` 因数据驱动自动识别新目录，无需手改数组。
- `doc-sync-judge.sh` 中 `<LATEST>` 占位**仍替换为精确 semver（`LATEST_SEMVER`）**——用于文档正文中的"安装 hanflow <版本>"。**大版本线（`1.x`）只用于文件夹路径，不进正文**。`doc-sync-judge.sh` 已输出 `DOCS_ZH`/`DOCS_EN`，merge 步骤对两棵树都落盘。
- 改动落在项目源 `E:\opensource\hanflow-evolve\skills\`（`install.sh` 分发源）。
- **停用/删除 `.agents` 下过期 skill 副本**（`C:\Users\xingpc37977\.agents\skills\{loop-evolve,contribute-pr}`），避免被读到旧逻辑。

## 5. hanflow-home 一次性调整

1. 合并 `content/1.0.1/1.1.0/1.2.0/1.2.1` 为 `content/1.x/`（以 `1.2.1` en/zh 为基底）。
2. 新增 `scripts/gen-versions.mjs`，`package.json` 加 `"prebuild"` 钩子。
3. 删除手写的 `lib/versions.ts` 字面量，改为生成器输出；保留 `resolveVersion()`（按 3.3 调整）及 `versionedPath()`/`stripVersionPrefix()` 辅助函数。
4. 调整 `generateStaticParams`（按 3.5）。
5. 调整 `Sidebar.tsx` 版本前缀（按 3.6）。
6. `VersionSelector.tsx` 实现真切换（按 3.4）。

## 6. 模块化交付（两条互不依赖的工作线）

- **线1（核心痛点：文件夹瘦身）**：skill 改造 + `content/` 合并 + `gen-versions.mjs`。**单独交付即消除臃肿**，下拉先以数据驱动展示当前线。
- **线2（真切换体验）**：`resolveVersion` 调整 + `generateStaticParams` + `VersionSelector` 跳转 + `Sidebar` 前缀。
- 即使线2要往后排，线1也已独立生效。

## 7. 边界与已知限制

- 旧线文档缺失 → 沿用现有 `page.tsx` 的 404 行为，本期不做友好页。
- 冻结旧线不做 backport：`2.x` 出现后，`1.x` 冻结，新补丁只进 latest 线。
- 页脚展示精确 `LATEST_SEMVER`（如 1.2.1），下拉展示大版本线（如 1.x）——职责分离。
- MDX frontmatter `version:` 字段（现 `site-sync.sh` 会写 `dsl-syntax.mdx`）：**实施阶段先确认是否被消费**；无人用则删，有人用则设为 `LATEST_SEMVER`，先不臆断。

## 8. 验证方式

- `npm run build` 通过（`prebuild` 钩子生成 `versions.ts` 成功）。
- en/zh 各渲染一页验证可访问。
- **造一个假的 `content/2.x/`** 验证：下拉自动出现 2.x 选项 + 能切换并渲染 + locale 保留，验证后删除假目录。
- 验证旧 semver URL（如 `/zh/docs/1.2.1/quick-start`）仍可访问（归入 1.x 线）。

## 9. 影响面清单

- `hanflow-home`：`content/`（合并）、`lib/versions.ts`（生成器化）、`lib/docs.ts`（入参）、`app/[locale]/docs/[[...slug]]/page.tsx`（解析+静态参数）、`components/layout/VersionSelector.tsx`（真切换）、`components/docs/Sidebar.tsx`（前缀）、`scripts/gen-versions.mjs`（新增）、`package.json`（prebuild）。
- `hanflow-evolve`：`scripts/site-sync.sh`、`skills/contribute-pr/scripts/home-sync.sh`、`skills/contribute-pr/scripts/doc-sync-judge.sh`（`<LATEST>` 语义澄清）、对应 `references/*.md` 文档更新。
- 清理：`.agents/skills/{loop-evolve,contribute-pr}` 过期副本。
