# P8. RELEASE — 版本号 + GitHub 同步

## 前置条件
- state.yaml.phase == "release" 且 gate3 已 approved
- feature 分支代码已测试全绿

## 执行步骤

1. 判断 site_sync_needed (扫描 feat:/BREAKING commits)
2. 版本号更新: bash scripts/version-bump.sh (spec §5.3)
3. GitHub 同步: bash scripts/github-sync.sh (spec §5.4)
   - Phase A: hanflow (merge + tag + push)
   - 若 site_sync_needed: Phase C 官网同步 (spec §5.5)
   - Phase B: hanflow-evolve 自身 commit + push
4. (可选) gh release create (config.release.create_github_release)
5. 写 state.yaml: phase=learn, site_sync_needed
6. Commit, 自动进入 P9
