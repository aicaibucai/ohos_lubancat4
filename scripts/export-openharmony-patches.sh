#!/usr/bin/env bash
# 从 OpenHarmony 源码树导出「真实移植改动」为独立 patch 集（精确版）
#
# 排除规则：
#   A. 构建垃圾：.cmd/.o/.o.d/.a/.order/.gch/.pyc/.class/.rej/.lock
#   B. 目录垃圾：node_modules/ oh_modules/ .hvigor/ out/ __pycache__/ ohos-build/
#   C. npm 副作用：package-lock.json, package-lock.json5, oh-package-lock.json5
#   D. 构建配置噪音：hvigorw(权限位), local.properties, local_paths.properties
#   E. 备份文件：*.bak
#   F. 仓库级排除：上游 OH 官方适配补丁（sane-airscan/cups-filters/iptables/...）
#      XTS 测试、app_samples、user_certificate_manager、packing_tool 等非本移植范围
#
# 输出：<outdir>/<仓库路径转下划线>.patch
set -uo pipefail

O=$OH_SRC
OUT=${1:-/tmp/ohos-patches}
cd "$O" || exit 1

rm -rf "$OUT"; mkdir -p "$OUT"

EXCLUDE_REPOS=(
  "third_party/sane-airscan" "third_party/cups-filters" "third_party/iptables"
  "third_party/pcre2" "third_party/freetype" "third_party/icu"
  "third_party/libjpeg-turbo" "third_party/wpa_supplicant"
  "third_party/bounds_checking_function" "third_party/libnl"
  "test/xts/acts" "applications/standard/user_certificate_manager"
  "applications/standard/app_samples" "developtools/packing_tool"
  "foundation/distributedhardware/distributed_hardware_fwk"
  "arkcompiler/ets_frontend" "developtools/ace_js2bundle"
  "applications/standard/dlp_manager" "applications/standard/permission_manager"
  "base/powermgr/power_manager" "foundation/ability/ability_runtime"
  "foundation/communication/wifi" "foundation/communication/dsoftbus"
  "applications/standard/hap" "device/soc/rockchip"
)

is_excluded() {
  local r="$1"
  for e in "${EXCLUDE_REPOS[@]}"; do [ "$r" = "$e" ] && return 0; done
  return 1
}

is_junk_file() {
  local f="$1"
  case "$f" in
    *.cmd|*.o|*.o.d|*.a|*.order|*.gch|*.pyc|*.class|*.rej|*.lock|*.bak) return 0 ;;
    package-lock.json|*/package-lock.json|package-lock.json5|*/package-lock.json5) return 0 ;;
    oh-package-lock.json5|*/oh-package-lock.json5) return 0 ;;
    hvigorw|*/hvigorw) return 0 ;;
    local.properties|*/local.properties|local_paths.properties|*/local_paths.properties) return 0 ;;
    */node_modules/*|*/oh_modules/*|*/.hvigor/*|*/out/*|*/__pycache__/*) return 0 ;;
    */ohos-build/*) return 0 ;;
  esac
  return 1
}

count=0
while IFS='|' read -r _n repo; do
  is_excluded "$repo" && continue

  mapfile -t lines < <(git -C "$repo" status --porcelain 2>/dev/null)
  [ ${#lines[@]} -eq 0 ] && continue

  real=0
  for line in "${lines[@]}"; do
    f="${line:3}"; f="${f%\"}"; f="${f#\"}"
    is_junk_file "$f" || real=$((real+1))
  done
  [ "$real" -eq 0 ] && continue

  safe=$(echo "$repo" | tr '/' '_')
  pf="$OUT/${safe}.patch"

  {
    echo "# ============================================================"
    echo "# 仓库: $repo"
    echo "# 上游: $(git -C "$repo" remote get-url origin 2>/dev/null || echo '(无 remote)')"
    echo "# 基线: $(git -C "$repo" log -1 --format='%h %ad %s' --date=short 2>/dev/null)"
    echo "# ============================================================"
    echo ""
  } > "$pf"

  # 已跟踪文件的修改（排除噪音）
  git -C "$repo" diff -- \
    ':(exclude)*.cmd' ':(exclude)*.o' ':(exclude)*.o.d' ':(exclude)*.a' \
    ':(exclude)*.order' ':(exclude)*.gch' ':(exclude)*.rej' ':(exclude)*.bak' \
    ':(exclude)*.lock' ':(exclude)*/package-lock.json' \
    ':(exclude)*/package-lock.json5' ':(exclude)*/oh-package-lock.json5' \
    ':(exclude)hvigorw' ':(exclude)*/hvigorw' \
    ':(exclude)local.properties' ':(exclude)*/local.properties' \
    ':(exclude)local_paths.properties' ':(exclude)*/local_paths.properties' \
    ':(exclude)*/node_modules/*' ':(exclude)*/oh_modules/*' \
    ':(exclude)*/.hvigor/*' ':(exclude)*/out/*' ':(exclude)*.hcb' >> "$pf" 2>/dev/null

  # 未跟踪的真实新文件（完整内容，用 git new-file 格式）
  for line in "${lines[@]}"; do
    st="${line:0:2}"; f="${line:3}"; f="${f%\"}"; f="${f#\"}"
    [ "$st" = "??" ] || continue
    is_junk_file "$f" && continue
    [ -f "$repo/$f" ] || continue
    {
      echo ""
      echo "diff --git a/$f b/$f"
      echo "new file mode 100644"
      echo "--- /dev/null"
      echo "+++ b/$f"
      # 逐行加 + 前缀；空行用单个 + 表示
      awk '{ if (length($0)==0) print "+"; else print "+" $0 }' "$repo/$f" 2>/dev/null
    } >> "$pf"
  done

  # 空 patch（只有头）则删除
  if [ "$(grep -c '^diff --git' "$pf")" -eq 0 ]; then
    rm -f "$pf"
    continue
  fi

  printf "%-58s %6s  %s diff\n" "$repo" "$(du -h "$pf" | cut -f1)" "$(grep -c '^diff --git' "$pf")"
  count=$((count+1))
done < /tmp/repo_changed.txt

echo ""
echo "生成 $count 个 patch 文件 -> $OUT"
