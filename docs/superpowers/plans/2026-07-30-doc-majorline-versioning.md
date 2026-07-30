# 文档大版本线版本化（Major-Line Versioning）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 hanflow-home 文档从"每 patch 一个文件夹"改为"每 major 一条线（`content/<major>.x/`）"，小版本原地合并 en+zh，大版本才开新线；导航栏版本下拉数据驱动且真正可切换；同步改造 loop-evolve / contribute-pr 两个 skill。

**Architecture:** 两个仓库协同。`hanflow-home`（Next.js 14）负责站点：新增 `scripts/gen-versions.mjs` 在 `prebuild` 生成 `lib/versions.ts` 字面量（扫描 `content/<major>.x/` + 读 `package.json`），`resolveVersion` 兼容旧 semver URL，`VersionSelector` 改真切换（保留 locale），`generateStaticParams` 覆盖所有线×{en,zh}。`hanflow-evolve`（skill 源）负责流程：`site-sync.sh` / `home-sync.sh` 按 semver bump 类型分流（minor/patch 原地合并、major 开新线），`doc-sync-judge.sh` 的 `<LATEST>` 路径占位替换为 `<major>.x`。

**Tech Stack:** Next.js 14 App Router、TypeScript、vitest、Node.js ESM（gen-versions.mjs）、bash + python（site-sync / home-sync / doc-sync-judge）。

**设计依据:** `docs/superpowers/specs/2026-07-30-doc-majorline-versioning-design.md`

**两条独立工作线:**
- **线1（Task 1–7，核心瘦身）**: gen-versions.mjs + versions.ts 重构 + content 合并 + 两个 skill 改造 + 清理 .agents 副本。单独交付即消除臃肿。
- **线2（Task 8–11，真切换体验）**: resolveVersion 调整 + generateStaticParams + Sidebar 前缀 + VersionSelector 真切换。

> **仓库边界约定**: Task 1–5、8–11 的文件路径默认 `E:\opensource\hanflow-home\...`；Task 6–7 默认 `E:\opensource\hanflow-evolve\...`。每个 Task 标注所在仓库。

---

## 线 1 — 文件夹瘦身（核心痛点）

### Task 1: 新增 gen-versions.mjs 版本生成器（hanflow-home）

生成器扫描 `content/` 下 `<major>.x` 目录 + 读 `package.json`，产出 `lib/versions.ts` 的字面量。这是"不写死"的基石——客户端组件无法读文件系统，故在构建前生成字面量。

**Files:**
- Create: `E:\opensource\hanflow-home\scripts\gen-versions.mjs`
- Modify: `E:\opensource\hanflow-home\package.json` (加 `prebuild` 钩子)

- [ ] **Step 1: 创建 gen-versions.mjs**

```js
// scripts/gen-versions.mjs
// 在 next build 前生成 lib/versions.ts 的字面量。
// 扫描 content/ 下 <major>.x 目录 + 读 package.json version。
// ⚠️ 此脚本是 lib/versions.ts 的唯一生成源; 不要手改 versions.ts。
import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const contentDir = join(root, 'content');
const outPath = join(root, 'lib', 'versions.ts');

// 1. 扫描 content/ 下 <major>.x 目录 (如 1.x, 2.x), 按 major 数值降序
const majorLineRe = /^(\d+)\.x$/;
let majors = [];
if (existsSync(contentDir)) {
  majors = readdirSync(contentDir, { withFileTypes: true })
    .filter((e) => e.isDirectory() && majorLineRe.test(e.name))
    .map((e) => ({ name: e.name, major: Number(e.name.match(majorLineRe)[1]) }))
    .sort((a, b) => b.major - a.major) // 降序: 最新线在前
    .map((e) => e.name);
}
if (majors.length === 0) {
  console.error('[gen-versions] ERROR: no content/<major>.x/ directories found under', contentDir);
  process.exit(1);
}
const latestMajor = majors[0];

// 2. 读 package.json version 作为精确发布号 (页脚/正文用)
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const latestSemver = pkg.version;
if (!latestSemver) {
  console.error('[gen-versions] ERROR: package.json has no version field');
  process.exit(1);
}

// 3. 写 lib/versions.ts (仅字面量; 辅助函数仍在文件下半部分, 不被覆盖)
const header = `// ⚠️ 此文件由 scripts/gen-versions.mjs 自动生成 (上半部分字面量)。
// 请勿手改上方字面量; 改 content/<major>.x/ 或 package.json 后重跑 npm run build。
// 下方 resolveVersion 等辅助函数为手写, 生成器不会覆盖。

export const MAJOR_VERSIONS = [${majors.map((m) => `'${m}'`).join(', ')}] as const;
export type MajorVersion = (typeof MAJOR_VERSIONS)[number];

export const LATEST_MAJOR: MajorVersion = '${latestMajor}';
export const LATEST_SEMVER: string = '${latestSemver}';
`;

writeFileSync(outPath, header, 'utf8');
console.log(`[gen-versions] wrote lib/versions.ts: MAJOR_VERSIONS=[${majors.join(', ')}] LATEST_MAJOR='${latestMajor}' LATEST_SEMVER='${latestSemver}'`);
```

> 说明：生成器只写文件头部的字面量区。`resolveVersion` 等手写函数放同一文件下半部分（Task 3 处理），生成器用 `writeFileSync` 整体覆盖——因此 Task 3 会把辅助函数**合并进生成器**输出，而非分两段。见 Task 3 Step 1 的完整实现。

- [ ] **Step 2: 加 prebuild 钩子到 package.json**

把 `package.json` 的 `"scripts"` 改为（仅新增 `prebuild` 一行，其余不动）：

```json
"scripts": {
  "dev": "next dev",
  "prebuild": "node scripts/gen-versions.mjs",
  "build": "next build",
  "start": "next start",
  "lint": "next lint",
  "test": "vitest run",
  "test:watch": "vitest",
  "typecheck": "tsc --noEmit"
}
```

- [ ] **Step 3: 跑生成器验证输出**

Run: `cd /e/opensource/hanflow-home && node scripts/gen-versions.mjs`

注意：此时 `content/` 下还没有 `1.x/` 目录（Task 5 才合并），会报 "no content/<major>.x/" 退出 1。这是预期的——先记录，Task 5 合并后会通过。本 Task 不单独验证生成器，验证推迟到 Task 5。

- [ ] **Step 4: Commit**

```bash
cd /e/opensource/hanflow-home
git add scripts/gen-versions.mjs package.json
git commit -m "build: add gen-versions.mjs to generate lib/versions.ts at prebuild"
```

---

### Task 2: 临时手动生成 versions.ts 字面量（hanflow-home）

为了让 Task 3–5 能引用 `MAJOR_VERSIONS`/`LATEST_MAJOR`/`LATEST_SEMVER` 而不阻塞，先手写一份与生成器输出一致的 `lib/versions.ts`。Task 5 合并 content 后会由生成器接管。

**Files:**
- Modify: `E:\opensource\hanflow-home\lib\versions.ts`（临时手写，Task 5 后由生成器产出）

- [ ] **Step 1: 暂时清空 versions.ts 到最小字面量（保留旧函数供 Task 3 参考，随后重写）**

把 `lib/versions.ts` 整体替换为：

```ts
// 临时占位; Task 3 重写完整版, Task 5 后由 gen-versions.mjs 生成头部。
export const MAJOR_VERSIONS = ['1.x'] as const;
export type MajorVersion = (typeof MAJOR_VERSIONS)[number];
export const LATEST_MAJOR: MajorVersion = '1.x';
export const LATEST_SEMVER: string = '1.2.1';
```

- [ ] **Step 2: Commit**

```bash
cd /e/opensource/hanflow-home
git add lib/versions.ts
git commit -m "versions: placeholder major-line literals (full rewrite in next task)"
```

---

### Task 3: 重写 lib/versions.ts — 生成器输出 + resolveVersion（hanflow-home）

把生成器扩展为同时输出**字面量 + 手写辅助函数**，让 `lib/versions.ts` 完全由生成器产出。`resolveVersion` 兼容三种首段：`<major>.x`、旧 semver（归到对应 major 线）、非版本段（归 latest）。

**Files:**
- Modify: `E:\opensource\hanflow-home\scripts\gen-versions.mjs`（在 header 后追加辅助函数源码）
- Modify: `E:\opensource\hanflow-home\lib\versions.ts`（由生成器重写）

- [ ] **Step 1: 扩展 gen-versions.mjs, 在 header 后追加辅助函数**

在 `gen-versions.mjs` 中，把第 3 步的 `writeFileSync(outPath, header, ...)` 改为写入 `header + helpers`，其中 `helpers` 是固定字符串（辅助函数源码）。把第 3 步那段替换为：

```js
const helpers = String.raw`
export interface ResolvedVersion {
  version: string;
  isLatest: boolean;
  rest: string[];
}

const MAJOR_LINE_RE = /^\d+\.x$/;      // 大版本线, 如 1.x
const SEMVER_RE = /^\d+\.\d+\.\d+$/;   // 旧完整 semver, 如 1.2.1

export function isKnownVersion(value: string): value is MajorVersion {
  return (MAJOR_VERSIONS as readonly string[]).includes(value);
}

/**
 * 把 docs catch-all slug 拆成 (version, rest):
 *  - 首段是 <major>.x 形态 → 用该大版本线
 *  - 首段是旧 semver (1.2.1) → 归到对应 major 线 <major>.x
 *  - 否则 → LATEST_MAJOR
 * 旧 semver URL 由此兼容, 无需 redirect 配置; locale 在独立 [locale] 段不受影响。
 */
export function resolveVersion(slug: string[]): ResolvedVersion {
  if (slug.length > 0) {
    const first = slug[0];
    if (MAJOR_LINE_RE.test(first)) {
      return { version: first, isLatest: first === LATEST_MAJOR, rest: slug.slice(1) };
    }
    if (SEMVER_RE.test(first)) {
      // 旧 semver 首段 → 归到对应 major 线 (如 1.2.1 → 1.x)
      const majorLine = first.split('.')[0] + '.x';
      return { version: majorLine, isLatest: majorLine === LATEST_MAJOR, rest: slug.slice(1) };
    }
  }
  return { version: LATEST_MAJOR, isLatest: true, rest: slug };
}

export function stripVersionPrefix(slug: string[]): string[] {
  if (slug.length === 0) return slug;
  const first = slug[0];
  if (MAJOR_LINE_RE.test(first) || SEMVER_RE.test(first)) return slug.slice(1);
  return slug;
}

/** 构造文档路径段; LATEST 线不加前缀, 其余线加 <major>.x/ 前缀。 */
export function versionedPath(rest: string, version: string): string {
  return version === LATEST_MAJOR ? rest : `${version}/${rest}`;
}
`;

writeFileSync(outPath, header + '\n' + helpers, 'utf8');
console.log(`[gen-versions] wrote lib/versions.ts: MAJOR_VERSIONS=[${majors.join(', ')}] LATEST_MAJOR='${latestMajor}' LATEST_SEMVER='${latestSemver}'`);
```

- [ ] **Step 2: 跑生成器重写 versions.ts**

Run: `cd /e/opensource/hanflow-home && node scripts/gen-versions.mjs`

预期：因 content 下无 `1.x/` 仍报错退出。Task 5 后才跑通。本步不验证，留待 Task 5。

- [ ] **Step 3: Commit**

```bash
cd /e/opensource/hanflow-home
git add scripts/gen-versions.mjs lib/versions.ts
git commit -m "versions: generator emits literals + resolveVersion (major-line aware)"
```

---

### Task 4: 重写 tests/versions.test.ts 适配大版本线（hanflow-home）

旧测试假设 `VERSIONS` 是完整 semver 数组、`LATEST_VERSION` 是最后一项。新模型下 `MAJOR_VERSIONS` 是 `<major>.x`、`LATEST_MAJOR` 是首项。改写测试以反映新语义。

**Files:**
- Modify: `E:\opensource\hanflow-home\tests\versions.test.ts`

- [ ] **Step 1: 整体替换 versions.test.ts**

```ts
import { describe, expect, it } from 'vitest';
import {
  MAJOR_VERSIONS,
  LATEST_MAJOR,
  LATEST_SEMVER,
  isKnownVersion,
  resolveVersion,
  stripVersionPrefix,
  versionedPath,
} from '../lib/versions';

describe('versions (major-line model)', () => {
  it('exposes LATEST_MAJOR as the first (newest) major line', () => {
    expect(LATEST_MAJOR).toBe(MAJOR_VERSIONS[0]);
  });

  it('every major line is <number>.x shaped', () => {
    expect(MAJOR_VERSIONS.length).toBeGreaterThanOrEqual(1);
    for (const v of MAJOR_VERSIONS) {
      expect(v).toMatch(/^\d+\.x$/);
    }
  });

  it('LATEST_SEMVER is a full semver string', () => {
    expect(LATEST_SEMVER).toMatch(/^\d+\.\d+\.\d+$/);
  });

  it('detects known major lines', () => {
    for (const v of MAJOR_VERSIONS) {
      expect(isKnownVersion(v)).toBe(true);
    }
    expect(isKnownVersion('9.x')).toBe(false);
  });

  it('resolves latest when first slug segment is not a version', () => {
    expect(resolveVersion(['quick-start'])).toEqual({
      version: LATEST_MAJOR,
      isLatest: true,
      rest: ['quick-start'],
    });
    expect(resolveVersion(['core-concepts', 'nodes'])).toEqual({
      version: LATEST_MAJOR,
      isLatest: true,
      rest: ['core-concepts', 'nodes'],
    });
  });

  it('resolves an explicit <major>.x segment', () => {
    if (MAJOR_VERSIONS.length >= 2) {
      const older = MAJOR_VERSIONS[MAJOR_VERSIONS.length - 1]; // 最旧的线
      expect(resolveVersion([older, 'quick-start'])).toEqual({
        version: older,
        isLatest: false,
        rest: ['quick-start'],
      });
    }
  });

  it('maps a legacy semver first segment onto its major line', () => {
    // 1.2.1 → 1.x (兼容旧 SEO 链接)
    expect(resolveVersion(['1.2.1', 'quick-start'])).toEqual({
      version: '1.x',
      isLatest: '1.x' === LATEST_MAJOR,
      rest: ['quick-start'],
    });
    expect(resolveVersion(['2.0.0', 'quick-start'])).toEqual({
      version: '2.x',
      isLatest: '2.x' === LATEST_MAJOR,
      rest: ['quick-start'],
    });
  });

  it('strips a version prefix (major-line or legacy semver) if present', () => {
    expect(stripVersionPrefix([LATEST_MAJOR, 'quick-start'])).toEqual(['quick-start']);
    expect(stripVersionPrefix(['1.2.1', 'quick-start'])).toEqual(['quick-start']);
    expect(stripVersionPrefix(['quick-start'])).toEqual(['quick-start']);
  });

  it('builds a versioned path with no prefix for latest major line', () => {
    expect(versionedPath('quick-start', LATEST_MAJOR)).toBe('quick-start');
  });

  it('builds a versioned path with <major>.x/ prefix for old lines', () => {
    if (MAJOR_VERSIONS.length >= 2) {
      const older = MAJOR_VERSIONS[MAJOR_VERSIONS.length - 1];
      expect(versionedPath('quick-start', older)).toBe(`${older}/quick-start`);
    }
  });
});
```

- [ ] **Step 2: 运行测试验证失败（content 未合并、versions.ts 未重写时）**

Run: `cd /e/opensource/hanflow-home && npm run test 2>&1 | tail -20`

预期：此时因 `lib/versions.ts` 还是 Task 2 的临时字面量（无 `resolveVersion` 等导出），测试会因 import 失败而报错。这是预期的——Task 5 合并 content 并跑通生成器后，versions.ts 才有完整导出。本 Task 先把测试写好，验证推迟到 Task 5 Step 4。

- [ ] **Step 3: Commit**

```bash
cd /e/opensource/hanflow-home
git add tests/versions.test.ts
git commit -m "test: adapt versions tests to major-line model"
```

---

### Task 5: 合并 content 四版本为 content/1.x/（hanflow-home）⭐ 线1收口

把 `content/1.0.1/1.1.0/1.2.0/1.2.1` 合并为单一 `content/1.x/`，以 `1.2.1`（19 篇，超集）为基底；删除三个旧文件夹；跑通生成器；测试通过。

**Files:**
- Create: `E:\opensource\hanflow-home\content\1.x\`（从 1.2.1 复制）
- Delete: `content/1.0.1/`、`content/1.1.0/`、`content/1.2.0/`、`content/1.2.1/`

- [ ] **Step 1: 以 1.2.1 为基底创建 content/1.x/**

```bash
cd /e/opensource/hanflow-home/content
cp -r 1.2.1 1.x
echo "created content/1.x/ ($(find 1.x -name '*.mdx' | wc -l) mdx files)"
```

预期输出：`created content/1.x/ (38 mdx files)`（en 19 + zh 19）。

- [ ] **Step 2: 删除四个旧 semver 文件夹**

```bash
cd /e/opensource/hanflow-home/content
rm -rf 1.0.1 1.1.0 1.2.0 1.2.1
ls -1
```

预期输出仅剩：`1.x`。

- [ ] **Step 3: 跑生成器重写 lib/versions.ts（现在能通过）**

Run: `cd /e/opensource/hanflow-home && node scripts/gen-versions.mjs`

预期：`[gen-versions] wrote lib/versions.ts: MAJOR_VERSIONS=[1.x] LATEST_MAJOR='1.x' LATEST_SEMVER='1.2.0'`

> ⚠️ 注意 `LATEST_SEMVER` 会显示 `1.2.0`（当前 `package.json` 的 version）。这正确——精确发布号跟随 package.json。若要让页脚显示 1.2.1，需把 `package.json` version 改为 `1.2.1`。**本计划不改 package.json version**（那是发布流程的事），LATEST_SEMVER 顺其自然跟随。

- [ ] **Step 4: 跑测试验证通过**

Run: `cd /e/opensource/hanflow-home && npm run test 2>&1 | tail -20`

预期：所有 versions 测试通过（`resolveVersion` 现已存在；`MAJOR_VERSIONS=['1.x']`）。

- [ ] **Step 5: 跑 typecheck + build 验证站点可构建**

Run: `cd /e/opensource/hanflow-home && npm run typecheck 2>&1 | tail -20`

预期：无 TS 错误。

> `npm run build` 会在 Task 8（generateStaticParams）改完后一起验证。本步先确保 typecheck + test 过。

- [ ] **Step 6: Commit**

```bash
cd /e/opensource/hanflow-home
git add -A
git commit -m "content: collapse 1.0.1/1.1.0/1.2.0/1.2.1 into single 1.x major line"
```

---

### Task 6: 改造 site-sync.sh —— major/minor 分流（hanflow-evolve）⭐ 核心

loop-evolve 的 release 同步脚本。改为：minor/patch 只原地合并文档（路径定位 `content/<major>.x/`，更新 `package.json` + `dsl-syntax.mdx` frontmatter，不建文件夹、不动 versions.ts）；major 才 `cp -r` 出新线。`lib/versions.ts` 由生成器产出，脚本不再手写。

**Files:**
- Modify: `E:\opensource\hanflow-evolve\scripts\site-sync.sh`

- [ ] **Step 1: 重写 site-sync.sh 主体逻辑**

把整个 `site-sync.sh` 替换为：

```bash
#!/usr/bin/env bash
# site-sync.sh — RELEASE Phase C: 同步 hanflow-home (大版本线模型)
#
# 用法: site-sync.sh <evolve_home>
#
# 行为 (大版本线模型, spec 2026-07-30):
#   从 state.yaml current_version 读 LATEST (精确 semver, 如 1.2.1)。
#   计算 MAJOR_LINE = "<major>.x" (如 1.x)。
#   - minor/patch bump: 在 content/<MAJOR_LINE>/ 原地更新 (不建文件夹, 不动 versions.ts)。
#   - major bump: 若 content/<MAJOR_LINE>/ 不存在, cp -r content/<旧major>.x/ → 新线。
#   versions.ts 由 gen-versions.mjs 在 build 时生成, 本脚本不手写。
#
#   1. 从 config.yaml paths.hanflow_home 读 site 路径; state.yaml current_version 读 LATEST
#   2. 校验 site 仓库存在 + 分支干净
#   3. 幂等检查: content/<MAJOR_LINE>/ 存在 且 package.json version == LATEST → 已同步, 退出 0
#   4. major bump: cp -r content/<prev_major>.x/ → content/<MAJOR_LINE>/ (若不存在)
#   5. 改 package.json version = LATEST (gen-versions 从此读 LATEST_SEMVER)
#   6. npm run build (含 prebuild gen-versions → versions.ts 自动更新)
#   7. git add -A && git commit && git push
#
# 注: content/<line>/core-concepts/dsl-syntax.mdx 的 frontmatter version: 字段经核实
# 无任何代码消费 (readDoc 只读 raw, 不解析 frontmatter), 不再写入/维护。
set -euo pipefail

EVOLVE_HOME="${1:?Usage: site-sync.sh <evolve_home>}"
[ -d "$EVOLVE_HOME" ] || { echo "ERROR: evolve_home not found: $EVOLVE_HOME" >&2; exit 1; }

CONFIG="$EVOLVE_HOME/config.yaml"
STATE="$EVOLVE_HOME/state.yaml"
for f in "$CONFIG" "$STATE"; do
  [ -f "$f" ] || { echo "ERROR: missing $f" >&2; exit 1; }
done

# 读 site 路径 + LATEST
READ_OUT=$(CONFIG_FILE="$CONFIG" STATE_FILE="$STATE" python -c "
import os, yaml
c = yaml.safe_load(open(os.environ['CONFIG_FILE'], encoding='utf-8'))
s = yaml.safe_load(open(os.environ['STATE_FILE'], encoding='utf-8'))
print((c.get('paths') or {}).get('hanflow_home') or '')
print(s.get('current_version') or '')
")
SITE_PATH=$(printf '%s' "$READ_OUT" | sed -n '1p')
LATEST=$(printf '%s' "$READ_OUT" | sed -n '2p')

[ -n "$SITE_PATH" ] || { echo "ERROR: config.yaml paths.hanflow_home is empty" >&2; exit 1; }
[ -n "$LATEST" ] || { echo "ERROR: state.yaml current_version is empty" >&2; exit 1; }
[ -d "$SITE_PATH" ] || { echo "ERROR: hanflow-home path not found: $SITE_PATH" >&2; exit 1; }

# 大版本线: 1.2.1 → 1.x
MAJOR=$(printf '%s' "$LATEST" | sed -nE 's|^([0-9]+)\..*|\1|p')
MAJOR_LINE="${MAJOR}.x"

echo "[site-sync] site=$SITE_PATH target=v$LATEST line=$MAJOR_LINE"

# 校验 site 干净 (允许 content/<major>.x/ untracked)
PORCELAIN=$(git -C "$SITE_PATH" status --porcelain 2>/dev/null || true)
DIRTY=$(printf '%s\n' "$PORCELAIN" | grep -v -E '^\?\? content/[0-9]+\.x(/|$)' || true)
[ -z "$DIRTY" ] || { echo "ERROR: site repo unexpected changes:" >&2; printf '%s\n' "$DIRTY" >&2; exit 1; }

REMOTES=$(git -C "$SITE_PATH" remote 2>/dev/null || true)

# 幂等: content/<MAJOR_LINE>/ 存在 且 package.json version 已是 LATEST → 跳过
PkgVer=$(python -c "import json;print(json.load(open('$SITE_PATH/package.json',encoding='utf-8')).get('version',''))" 2>/dev/null || echo "")
if [ -d "$SITE_PATH/content/$MAJOR_LINE" ] && [ "$PkgVer" = "$LATEST" ]; then
  echo "[site-sync] already synced to v$LATEST ($MAJOR_LINE) — idempotent skip"
  echo "OK: site-sync no-op"
  exit 0
fi

# major bump: 新线不存在 → 从最近的旧线 cp -r
if [ ! -d "$SITE_PATH/content/$MAJOR_LINE" ]; then
  PREV=$(ls -1 "$SITE_PATH/content/" 2>/dev/null | grep -E '^[0-9]+\.x$' | sort -rV | head -1 || true)
  [ -n "$PREV" ] || { echo "ERROR: no existing content/<major>.x/ to copy from" >&2; exit 1; }
  echo "[site-sync] major bump: cp -r content/$PREV content/$MAJOR_LINE"
  cp -r "$SITE_PATH/content/$PREV" "$SITE_PATH/content/$MAJOR_LINE"
fi

# 改 package.json (LATEST_SEMVER 来源; gen-versions 从此读取)
echo "[site-sync] updating package.json for $MAJOR_LINE"
SITE_PATH_ENV="$SITE_PATH" TARGET_VERSION_ENV="$LATEST" python <<'PYEOF'
import json, os

site = os.environ['SITE_PATH_ENV']
latest = os.environ['TARGET_VERSION_ENV']

p = os.path.join(site, 'package.json')
data = json.load(open(p, encoding='utf-8'))
old = data.get('version')
data['version'] = latest
with open(p, 'w', encoding='utf-8', newline='\n') as fh:
    json.dump(data, fh, indent=2); fh.write('\n')
print(f"  package.json: version {old} -> {latest}")
PYEOF

# versions.ts 不手写: prebuild(gen-versions.mjs) 会从 content/ + package.json 生成。
echo "[site-sync] versions.ts left to prebuild gen-versions.mjs (data-driven)"
# 注: dsl-syntax.mdx frontmatter version 字段无代码消费, 不再写入。

# npm run build (prebuild 先生成 versions.ts; build 内含类型检查)
echo "[site-sync] npm run build"
cd "$SITE_PATH"
if ! npm run build 2>&1 | tail -20; then
  echo "ERROR: npm run build failed in site repo" >&2
  exit 1
fi

# commit + push
cd "$SITE_PATH"
git add -A
if git diff --cached --quiet; then
  echo "[site-sync] no net changes (idempotent)"; echo "OK: site-sync no-op"; exit 0
fi

git commit -m "feat: sync site to v$LATEST ($MAJOR_LINE) [major-line model]

Auto-synced by hanflow-evolve/scripts/site-sync.sh. versions.ts is now
generated by scripts/gen-versions.mjs at prebuild (data-driven). Minor/patch
bumps merge into content/$MAJOR_LINE/ in place; major bumps open a new line." 2>&1 | tail -3

if [ -n "$REMOTES" ]; then
  PUSHED=0
  for REMOTE in $REMOTES; do
    echo "[site-sync] pushing to '$REMOTE'"
    if git push "$REMOTE" main 2>&1; then PUSHED=1; break; fi
  done
  [ "$PUSHED" -eq 0 ] && echo "WARN: all remotes failed; commit local-only" >&2
else
  echo "[site-sync] no remote; local commit only"
fi
echo "OK: site-sync done (v$LATEST / $MAJOR_LINE)"
```

- [ ] **Step 2: 检查 release.md 是否需同步更新（描述）**

Run: `cd /e/opensource/hanflow-evolve && grep -n "site-sync\|cp -r content\|VERSIONS" skills/loop-evolve/references/release.md`

读相关段落，若描述了旧的"每版本建文件夹 + 改 VERSIONS 数组"，改为说明大版本线语义（minor/patch 原地合并、major 开新线、versions.ts 由 gen-versions 生成）。**具体改写内容**：找到 release.md 中关于 site-sync 的步骤清单，把"cp content/<prev>/ → content/<LATEST>/"和"改 lib/versions.ts VERSIONS"两步替换为：

```
site-sync.sh (大版本线模型):
  - minor/patch: 在 content/<major>.x/ 原地更新 (package.json + frontmatter), 不建文件夹。
  - major: cp -r content/<旧major>.x/ → content/<新major>.x/。
  - versions.ts 不手写: prebuild 的 gen-versions.mjs 扫描 content/ + package.json 自动生成。
```

（若 release.md 中无逐字该清单，按其现有措辞风格插入等价说明即可。）

- [ ] **Step 3: Commit**

```bash
cd /e/opensource/hanflow-evolve
git add scripts/site-sync.sh skills/loop-evolve/references/release.md
git commit -m "site-sync: major/minor branching per major-line model"
```

---

### Task 7: 改造 home-sync.sh + doc-sync-judge.sh + 清理 .agents 副本（hanflow-evolve）⭐ 核心

contribute-pr 路径。`home-sync.sh` 的 NEW_VERSION 处理改为大版本线语义：minor/patch 不建文件夹不动 versions.ts；major 才 `cp -r` 出新线。`doc-sync-judge.sh` 的 `<LATEST>` 路径占位替换为 `<major>.x`（路径用大版本线）。最后删除 `.agents` 下过期 skill 副本。

**Files:**
- Modify: `E:\opensource\hanflow-evolve\skills\contribute-pr\scripts\home-sync.sh`
- Modify: `E:\opensource\hanflow-evolve\skills\contribute-pr\scripts\doc-sync-judge.sh`
- Modify: `E:\opensource\hanflow-evolve\skills\contribute-pr\references\submit.md`（描述同步）
- Delete: `C:\Users\xingpc37977\.agents\skills\loop-evolve\`、`contribute-pr\`（过期副本）

- [ ] **Step 1: 改写 home-sync.sh 的版本切换器段（第 135–155 行）**

把 home-sync.sh 中这一段：

```bash
# ── 版本切换器更新 (若有 NEW_VERSION) ──
if [ -n "$NEW_VERSION" ]; then
  VERSIONS_TS="$HANFLOW_HOME_REPO/lib/versions.ts"
  # 检查是否已含此版本 (幂等)
  if ! grep -q "'$NEW_VERSION'" "$VERSIONS_TS" 2>/dev/null; then
    # 读旧 LATEST
    OLD_LATEST=$(grep "LATEST_VERSION" "$VERSIONS_TS" | sed -nE "s|.*'([^']+)'.*|\1|p" | head -1)
    # VERSIONS 数组加新版本
    sed -i "s|VERSIONS = \[|VERSIONS = ['$NEW_VERSION', |" "$VERSIONS_TS"
    # LATEST 更新
    sed -i "s|LATEST_VERSION: Version = '[^']*'|LATEST_VERSION: Version = '$NEW_VERSION'|" "$VERSIONS_TS"
    # cp -r 旧版本目录 → 新版本
    if [ -d "$HANFLOW_HOME_REPO/content/$OLD_LATEST" ] && [ ! -d "$HANFLOW_HOME_REPO/content/$NEW_VERSION" ]; then
      cp -r "$HANFLOW_HOME_REPO/content/$OLD_LATEST" "$HANFLOW_HOME_REPO/content/$NEW_VERSION"
      echo "  版本: content/$NEW_VERSION 已创建 (从 $OLD_LATEST 复制)"
    fi
    echo "  版本: lib/versions.ts 已更新 LATEST=$NEW_VERSION"
  else
    echo "  版本: $NEW_VERSION 已在 versions.ts (幂等跳过)"
  fi
fi
```

替换为（大版本线语义；versions.ts 由 gen-versions 生成，不手写）：

```bash
# ── 版本同步 (大版本线模型, 若有 NEW_VERSION) ──
# versions.ts 由 gen-versions.mjs 在 build 时生成, 这里不手写。
# minor/patch: 只更新 package.json (LATEST_SEMVER 来源); 不建文件夹。
# major: cp -r content/<旧major>.x/ → content/<新major>.x/。
if [ -n "$NEW_VERSION" ]; then
  NEW_MAJOR=$(printf '%s' "$NEW_VERSION" | sed -nE 's|^([0-9]+)\..*|\1|p')
  NEW_LINE="${NEW_MAJOR}.x"
  # package.json version = 精确 semver (gen-versions 从这里读 LATEST_SEMVER)
  python -c "
import json,os
p=os.environ['PKG']
d=json.load(open(p,encoding='utf-8')); d['version']=os.environ['VER']
json.dump(d,open(p,'w',encoding='utf-8',newline='\n'),indent=2); open(p,'a',encoding='utf-8').write('\n')
" PKG="$HANFLOW_HOME_REPO/package.json" VER="$NEW_VERSION"
  echo "  版本: package.json -> v$NEW_VERSION"
  # major bump: 新线不存在才 cp -r
  if [ ! -d "$HANFLOW_HOME_REPO/content/$NEW_LINE" ]; then
    PREV=$(ls -1 "$HANFLOW_HOME_REPO/content/" 2>/dev/null | grep -E '^[0-9]+\.x$' | sort -rV | head -1 || true)
    if [ -n "$PREV" ]; then
      cp -r "$HANFLOW_HOME_REPO/content/$PREV" "$HANFLOW_HOME_REPO/content/$NEW_LINE"
      echo "  版本: major bump → content/$NEW_LINE 已创建 (从 $PREV 复制)"
    else
      echo "  WARN: 无旧线可复制, content/$NEW_LINE 需手动创建" >&2
    fi
  else
    echo "  版本: minor/patch → 原地合并到 content/$NEW_LINE (不建文件夹)"
  fi
  echo "  版本: versions.ts 由 prebuild gen-versions.mjs 自动更新 (数据驱动)"
fi
```

- [ ] **Step 2: 改写 home-sync.sh 末尾"准备就绪"提示里的 content/$NEW_VERSION 引用**

把 home-sync.sh 第 177 行附近：

```bash
[ -n "$NEW_VERSION" ] && echo "  版本: lib/versions.ts + content/$NEW_VERSION 已更新"
```

改为（NEW_LINE 变量在版本段已定义，但该 echo 在版本段之外，需重算或改措辞）：

```bash
if [ -n "$NEW_VERSION" ]; then
  NL=$(printf '%s' "$NEW_VERSION" | sed -nE 's|^([0-9]+)\..*|\1|p')".x"
  echo "  版本: package.json=v$NEW_VERSION content/$NL (versions.ts 由 build 生成)"
fi
```

- [ ] **Step 3: 改写 doc-sync-judge.sh 的 <LATEST> 语义（第 24–26 行）**

`<LATEST>` 用于文档**路径**（`content/<LATEST>/zh/...`），故替换为 `<major>.x`。把 doc-sync-judge.sh 第 24–26 行：

```bash
# 读 LATEST_VERSION (从 lib/versions.ts)
LATEST=$(grep "LATEST_VERSION" "$HANFLOW_HOME_REPO/lib/versions.ts" 2>/dev/null | sed -nE "s|.*'([^']+)'.*|\1|p" | head -1)
[ -z "$LATEST" ] && LATEST="1.2.0"  # fallback
```

替换为：

```bash
# 读 LATEST_MAJOR (大版本线, 用于文档路径 content/<major>.x/...)
# versions.ts 由 gen-versions.mjs 生成; 兜底也读 package.json 推 major。
LATEST=$(grep "LATEST_MAJOR" "$HANFLOW_HOME_REPO/lib/versions.ts" 2>/dev/null | sed -nE "s|.*'([^']+)'.*|\1|p" | head -1)
if [ -z "$LATEST" ]; then
  # 兜底: 从 package.json version 推 major.x
  PV=$(python -c "import json;print(json.load(open('$HANFLOW_HOME_REPO/package.json',encoding='utf-8')).get('version','1.0.0'))" 2>/dev/null || echo "1.0.0")
  LATEST=$(printf '%s' "$PV" | sed -nE 's|^([0-9]+)\..*|\1|p')".x"
fi
```

> 说明：`<LATEST>` 现替换为 `1.x`（路径形态），与 doc-mapping.yaml 中 `content/<LATEST>/zh/...` 正确拼接为 `content/1.x/zh/...`。文档**正文**里的精确版本号不经过此占位（正文版本号由 AI 生成文档时直接写）。

- [ ] **Step 4: 更新 submit.md 中 site-sync/home-sync 相关描述**

Run: `cd /e/opensource/hanflow-evolve && grep -n "home-sync\|cp -r content\|VERSIONS\|版本切换器\|content/\\\$NEW\|content/\$NEW" skills/contribute-pr/references/submit.md`

把描述"home-sync 更新版本切换器（VERSIONS 数组 + 新建 content/<version>/ 文件夹）"的句子，改为：

```
home-sync.sh (大版本线模型):
  - minor/patch: 仅更新 package.json; 文档合并进 content/<major>.x/; versions.ts 由 build 生成。
  - major: cp -r content/<旧major>.x/ → content/<新major>.x/。
```

（按 submit.md 现有措辞风格插入等价说明。）

- [ ] **Step 5: 删除 .agents 下过期 skill 副本**

```bash
rm -rf "/c/Users/xingpc37977/.agents/skills/loop-evolve"
rm -rf "/c/Users/xingpc37977/.agents/skills/contribute-pr"
ls "/c/Users/xingpc37977/.agents/skills/" 2>/dev/null | grep -E 'loop-evolve|contribute-pr' && echo "WARN: 仍有残留" || echo "OK: .agents 副本已清理"
```

预期输出：`OK: .agents 副本已清理`。

> 注意：`.agents` 是用户级 skill 安装目录的过期副本；`.zcode` 下的是当前副本（与项目源一致）。删 `.agents` 副本不影响 `.zcode` 的可用性。

- [ ] **Step 6: Commit**

```bash
cd /e/opensource/hanflow-evolve
git add skills/contribute-pr/scripts/home-sync.sh skills/contribute-pr/scripts/doc-sync-judge.sh skills/contribute-pr/references/submit.md
git commit -m "contribute-pr: home-sync + doc-sync-judge per major-line model; drop stale .agents copies"
```

---

## 线 2 — 真切换体验（可选延后，独立于线1）

### Task 8: generateStaticParams 覆盖所有大版本线（hanflow-home）

当前 `generateStaticParams` 只预渲染 `LATEST_VERSION`。改为遍历 `MAJOR_VERSIONS` 所有线 × {en, zh}，让旧线也能真切换且可预渲染。

**Files:**
- Modify: `E:\opensource\hanflow-home\app\[locale]\docs\[[...slug]]\page.tsx`

- [ ] **Step 1: 改 page.tsx 的 import + generateStaticParams**

把 page.tsx 第 4 行 import 改为：

```ts
import { resolveVersion, LATEST_MAJOR, MAJOR_VERSIONS } from '@/lib/versions';
```

把 `generateStaticParams`（第 46–65 行）整体替换为：

```ts
export async function generateStaticParams() {
  // 预渲染所有大版本线 × {en,zh} × 全部 slug, 让 1.x / 将来 2.x 都可真切换。
  const fs = await import('node:fs/promises');
  const out: { locale: string; slug: string[] }[] = [];
  for (const locale of ['en', 'zh']) {
    for (const ver of MAJOR_VERSIONS) {
      const dir = path.join(CONTENT_ROOT, ver, locale);
      let exists = true;
      try {
        await fs.access(dir);
      } catch {
        exists = false;
      }
      if (!exists) continue;
      const files = await walkMdx(dir);
      for (const rel of files) {
        // LATEST 线不加前缀; 旧线加 <major>.x/ 前缀
        if (ver === LATEST_MAJOR) {
          out.push({ locale, slug: rel });
        } else {
          out.push({ locale, slug: [ver, ...rel] });
        }
      }
    }
  }
  return out;
}
```

- [ ] **Step 2: 跑 typecheck**

Run: `cd /e/opensource/hanflow-home && npm run typecheck 2>&1 | tail -20`

预期：无错误。

- [ ] **Step 3: Commit**

```bash
cd /e/opensource/hanflow-home
git add 'app/[locale]/docs/[[...slug]]/page.tsx'
git commit -m "docs: pre-render all major lines x {en,zh} for real version switching"
```

---

### Task 9: Sidebar 链接补版本前缀（hanflow-home）

`Sidebar.tsx` 的 `hrefFor` 现在总是 `/docs/<slug>`（无版本前缀），导致切到旧线时链接串到 latest。改为：接收当前 version，旧线加 `<major>.x/` 前缀。

**Files:**
- Modify: `E:\opensource\hanflow-home\components\docs\Sidebar.tsx`
- Modify: `E:\opensource\hanflow-home\app\[locale]\docs\[[...slug]]\page.tsx`（传 version 给 Sidebar）

- [ ] **Step 1: 给 Sidebar 加 version 入参**

把 `Sidebar.tsx` 的组件签名 + `hrefFor` 改为：

```tsx
export function Sidebar({
  tree,
  locale,
  activeSlug,
  version,
}: {
  tree: SidebarNode[];
  locale: string;
  activeSlug: string;
  version: string; // 大版本线, 如 '1.x'; LATEST_MAJOR 时无前缀
}) {
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({});

  function hrefFor(slug: string) {
    // LATEST 线不加前缀; 旧线加 <major>.x/ 前缀
    const prefix = version === LATEST_MAJOR ? '' : `${version}/`;
    return `/${locale}/docs/${prefix}${slug}`;
  }
```

并在文件顶部 import 加 `LATEST_MAJOR`：

```tsx
import type { SidebarNode } from '@/lib/docs';
import { LATEST_MAJOR } from '@/lib/versions';
```

- [ ] **Step 2: 在 page.tsx 把 version 传给 Sidebar**

`page.tsx` 的 `DocsShell` 调用里，Sidebar 是 DocsShell 内部渲染的。先确认 DocsShell 是否接受 version prop：

Run: `cd /e/opensource/hanflow-home && grep -n "Sidebar\|version\|interface.*Shell\|Props" components/docs/DocsShell.tsx`

读 DocsShell.tsx。如果 DocsShell 把 `<Sidebar tree={...} locale={...} activeSlug={...} />` 透传，则：
- DocsShell 增加 `version?: string` prop，透传给 `<Sidebar version={version} ... />`。
- page.tsx 的 `<DocsShell ... />` 增加 `version={version}`（`version` 已在 page.tsx 第 16 行从 `resolveVersion` 解构出）。

具体改 DocsShell.tsx：找到 Sidebar 渲染处，加 `version={version}`；找到 Props 接口，加 `version: string`。在 page.tsx 的 DocsShell 调用加 `version={version}`。

> 若 DocsShell 内部直接渲染 Sidebar 且不接受外部 version，按上述把它打通。**不要**在 Sidebar 里读 URL——version 由 page.tsx 从 `resolveVersion` 得到后向下传，保持单向数据流。

- [ ] **Step 3: 跑 typecheck + test**

Run: `cd /e/opensource/hanflow-home && npm run typecheck 2>&1 | tail -20 && npm run test 2>&1 | tail -20`

预期：无错误，测试通过。

- [ ] **Step 4: Commit**

```bash
cd /e/opensource/hanflow-home
git add components/docs/Sidebar.tsx components/docs/DocsShell.tsx 'app/[locale]/docs/[[...slug]]/page.tsx'
git commit -m "sidebar: prefix links with <major>.x/ for non-latest version lines"
```

---

### Task 10: VersionSelector 真切换 + 保留 locale（hanflow-home）⭐ 线2收口

把 `VersionSelector` 从"只写 localStorage"改为"用 `usePathname` 解析当前路径，点选目标线时 `router.push` 切换并保留 locale"。下拉展示大版本线。

**Files:**
- Modify: `E:\opensource\hanflow-home\components\layout\VersionSelector.tsx`

- [ ] **Step 1: 重写 VersionSelector.tsx**

整体替换为：

```tsx
'use client';

import { useState, useRef, useEffect } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { Check, ChevronDown } from 'lucide-react';
import { MAJOR_VERSIONS, LATEST_MAJOR, LATEST_SEMVER } from '@/lib/versions';

export function VersionSelector() {
  const t = useTranslations('nav');
  const router = useRouter();
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  // 从当前路径解析 locale + 当前线 + rest。
  // 路径形如 /{locale}/docs/[<major>.x/]<slug...>
  function parsePath() {
    const segs = (pathname || '').split('/').filter(Boolean);
    const locale = segs[0] && ['en', 'zh'].includes(segs[0]) ? segs[0] : 'en';
    const docsIdx = segs.indexOf('docs');
    const afterDocs = docsIdx >= 0 ? segs.slice(docsIdx + 1) : [];
    let currentLine = LATEST_MAJOR;
    let rest: string[] = afterDocs;
    if (afterDocs.length > 0 && /^\d+\.x$/.test(afterDocs[0])) {
      currentLine = afterDocs[0];
      rest = afterDocs.slice(1);
    }
    return { locale, currentLine, rest };
  }

  const { locale, currentLine, rest } = parsePath();
  const current = MAJOR_VERSIONS.includes(currentLine as never) ? currentLine : LATEST_MAJOR;

  useEffect(() => {
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, []);

  function selectLine(target: string) {
    // 保留 locale; LATEST 线不加前缀, 其余加 <major>.x/
    const slugPart = rest.join('/');
    const prefix = target === LATEST_MAJOR ? '' : `${target}/`;
    const href = `/${locale}/docs/${prefix}${slugPart}`;
    window.localStorage.setItem('hanflow-docs-version', target);
    setOpen(false);
    router.push(href);
  }

  return (
    <div className="relative" ref={ref}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center gap-1 text-sm text-content-secondary hover:text-content-primary transition-colors"
        aria-expanded={open}
      >
        {current}
        <span className="text-xs text-content-muted">({LATEST_SEMVER})</span>
        <ChevronDown className="h-3.5 w-3.5" />
      </button>
      {open && (
        <div className="absolute right-0 mt-2 w-32 rounded-code border border-edge bg-bg-elevated p-1 shadow-xl">
          {MAJOR_VERSIONS.map((v) => (
            <button
              key={v}
              type="button"
              onClick={() => selectLine(v)}
              className="flex w-full items-center justify-between rounded px-3 py-2 text-sm text-content-secondary hover:bg-bg-subtle hover:text-content-primary"
            >
              {v}
              {v === current && <Check className="h-3.5 w-3.5 text-accent" />}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 2: 跑 typecheck**

Run: `cd /e/opensource/hanflow-home && npm run typecheck 2>&1 | tail -20`

预期：无错误。

- [ ] **Step 3: Commit**

```bash
cd /e/opensource/hanflow-home
git add components/layout/VersionSelector.tsx
git commit -m "version-selector: real switching with locale preservation (major lines)"
```

---

### Task 11: 端到端验证（造假 2.x 测大版本升级路径）（hanflow-home）

证明"大版本升级时下拉自动出现新线且能切换"，验证后清理。

- [ ] **Step 1: 造一个假的 content/2.x/ 测大版本升级**

```bash
cd /e/opensource/hanflow-home
cp -r content/1.x content/2.x
# 手动把 package.json version 提到 2.0.0 (仅验证用, 之后还原)
python -c "import json;p='package.json';d=json.load(open(p,encoding='utf-8'));d['version']='2.0.0';json.dump(d,open(p,'w',encoding='utf-8',newline='\n'),indent=2);open(p,'a',encoding='utf-8').write('\n')"
node scripts/gen-versions.mjs
echo "--- generated versions.ts head ---"
head -8 lib/versions.ts
```

预期：`lib/versions.ts` 头部显示 `MAJOR_VERSIONS = ['2.x', '1.x']`（降序，2.x 在前），`LATEST_MAJOR = '2.x'`，`LATEST_SEMVER = '2.0.0'`。

- [ ] **Step 2: 跑 build 验证下拉与预渲染**

Run: `cd /e/opensource/hanflow-home && npm run build 2>&1 | tail -30`

预期：build 成功；`generateStaticParams` 为 2.x 和 1.x 都生成页面。

- [ ] **Step 3: 本地 dev 手动验证下拉切换（可选, 需人工）**

Run: `cd /e/opensource/hanflow-home && npm run dev`（手动打开浏览器）

人工核对：
- 导航栏下拉出现 `2.x` 和 `1.x`，2.x 高亮（当前 latest）。
- 点 `1.x` → URL 变为 `/zh/docs/1.x/<当前slug>` 或 `/en/docs/1.x/...`，locale 保留，内容切到 1.x 线。
- 侧边栏链接在 1.x 视图下带 `1.x/` 前缀。
- 访问旧 semver URL `/zh/docs/1.2.1/quick-start` → 渲染 1.x 线 quick-start（不 404）。

- [ ] **Step 4: 还原 — 删除假 2.x + 还原 package.json version**

```bash
cd /e/opensource/hanflow-home
rm -rf content/2.x
git checkout -- package.json lib/versions.ts
node scripts/gen-versions.mjs
head -8 lib/versions.ts
```

预期：`MAJOR_VERSIONS = ['1.x']`，`LATEST_MAJOR = '1.x'`，`package.json` version 还原为 `1.2.0`。

- [ ] **Step 5: 跑 typecheck + test + build 确认干净状态**

Run: `cd /e/opensource/hanflow-home && npm run typecheck 2>&1 | tail -5 && npm run test 2>&1 | tail -10 && npm run build 2>&1 | tail -10`

预期：全部通过。

- [ ] **Step 6: Commit（若有版本文件未还原干净）**

```bash
cd /e/opensource/hanflow-home
git status --porcelain
# 若有遗留, git checkout -- 还原; 验证产物不提交。预期 git status 干净。
```

---

## 完成标准

- [ ] `content/` 下只有 `1.x/`（含 en/zh 各 19 篇），无散落 semver 文件夹。
- [ ] `npm run build` 通过；`prebuild` 自动生成 `lib/versions.ts`。
- [ ] `lib/versions.ts` 由 `gen-versions.mjs` 产出，含 `MAJOR_VERSIONS` / `LATEST_MAJOR` / `LATEST_SEMVER` + `resolveVersion` 等。
- [ ] 导航栏下拉数据驱动：造假 `2.x/` 后自动出现且能切换，删后消失。
- [ ] 旧 semver URL（`/docs/1.2.1/...`）渲染 1.x 线内容，不 404。
- [ ] `site-sync.sh` / `home-sync.sh` 按 major/minor 分流；minor/patch 不建文件夹。
- [ ] `doc-sync-judge.sh` 的 `<LATEST>` 路径占位替换为 `<major>.x`。
- [ ] `.agents` 下 `loop-evolve` / `contribute-pr` 过期副本已删。
- [ ] 改动均在项目源（hanflow-evolve/skills、hanflow-home），可被 install.sh 分发。
