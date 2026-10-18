#!/usr/bin/env bash
# 导出 openharmony-kernel 的完整移植改动
# - 已跟踪文件：git diff
# - 未跟踪新文件：git diff --no-index /dev/null <file>（生成标准 new-file patch）
set -uo pipefail

K=${1:-$LUBANCAT_SDK/openharmony-kernel}
OUT=${2:-/tmp/kernel-patch}
cd "$K" || exit 1

mkdir -p "$OUT"
PF="$OUT/openharmony-kernel.patch"

{
  echo "# ============================================================"
  echo "# 仓库: openharmony-kernel (LubanCat_SDK)"
  echo "# 上游: $(git remote get-url origin 2>/dev/null || echo '(无 remote)')"
  echo "# 基线: $(git log -1 --format='%h %ad %s' --date=short 2>/dev/null)"
  echo "#"
  echo "# 方案 B：原厂 5.10.209 内核 + HDF 钩子 + OH binder/access_token 移植"
  echo "# 详见 docs/03-编译排查与内核适配.md 第二章"
  echo "# ============================================================"
  echo ""
} > "$PF"

# 1) 已跟踪文件的修改
git diff >> "$PF" 2>/dev/null

# 2) 未跟踪的新增内容（排除编译产物与符号链接）
NEW_ITEMS=(
  "bounds_checking_function"
  "drivers/accesstokenid"
  "drivers/hdf"
  "include/trace/events/eas_sched.h"
  "include/trace/events/platform_trace_event.h"
  "include/trace/events/rtg.h"
  "include/trace/events/walt.h"
)

for item in "${NEW_ITEMS[@]}"; do
  [ -e "$item" ] || continue
  # 符号链接跳过（指向 OH 源码树，不该进内核 patch）
  if [ -L "$item" ]; then
    echo "# [跳过符号链接] $item -> $(readlink "$item")" >> "$PF"
    continue
  fi
  if [ -d "$item" ]; then
    find "$item" -type f \
      ! -name "*.cmd" ! -name "*.o" ! -name "*.o.d" \
      ! -name "*.a" ! -name "*.order" ! -name "*.gch" 2>/dev/null | sort | while read -r f; do
      echo "" >> "$PF"
      git diff --no-index /dev/null "$f" 2>/dev/null >> "$PF"
    done
  elif [ -f "$item" ]; then
    echo "" >> "$PF"
    git diff --no-index /dev/null "$item" 2>/dev/null >> "$PF"
  fi
done

echo "生成: $PF"
echo "大小: $(du -h "$PF" | cut -f1)"
echo "diff 数: $(grep -c '^diff --git' "$PF")"
