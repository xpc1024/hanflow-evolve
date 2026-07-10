#!/usr/bin/env bats

load 'test-helper'

@test "passes for complete design doc" {
  doc="$BATS_TMPDIR/design-ok.md"
  cat > "$doc" <<'EOF'
# 设计文档: 主题 X

## 架构定位
本主题定位在 core 层。

## 组件分解
- 组件 A
- 组件 B

## 接口契约
Foo.bar() -> Result

## 数据流
input -> process -> output

## 错误处理
所有错误抛出 HanflowError 子类, 带稳定 code。

## 测试策略
单元 + 集成测试。

## 迁移兼容
旧 API 保留一个 cycle。
EOF

  run bash "$SCRIPTS_DIR/audit-rules-check.sh" "$doc" design
  [ "$status" -eq 0 ]
}

@test "fails when required section missing" {
  doc="$BATS_TMPDIR/design-incomplete.md"
  cat > "$doc" <<'EOF'
# 设计文档: 主题 Y

## 架构定位
core 层。

## 组件分解
- A

## 接口契约
Foo.bar()

## 数据流
a -> b

### 错误处理
缺失 HanflowError 说明。

### 测试策略
略。
EOF

  run bash "$SCRIPTS_DIR/audit-rules-check.sh" "$doc" design
  [ "$status" -ne 0 ]
  # 应提到缺失章节 (迁移兼容 缺失, 错误处理 缺 HanflowError)
  echo "$output" | grep -E "迁移兼容|HanflowError"
}

@test "checks direction doc has required sections" {
  doc="$BATS_TMPDIR/direction-ok.md"
  cat > "$doc" <<'EOF'
# 方向: 主题 Z

## 动机
为什么要做。

## 目标
做成什么。

## 非目标
不做什么。

## 影响模块
core / cli。

## 验收标准
- 标准 1
- 标准 2
EOF

  run bash "$SCRIPTS_DIR/audit-rules-check.sh" "$doc" direction
  [ "$status" -eq 0 ]
}
