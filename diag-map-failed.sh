#!/bin/bash
#
# 合成缓冲 Map failed 诊断脚本
# 用法：板子 USB/串口恢复后执行本脚本，它会：
#   1) 重启 render_service + launcher，触发 2560x1440 buffer 分配/Map 路径
#   2) 抓取与 BufferQueue / Mapper / GbmMmap 相关的 hilog
#   3) 输出判读提示
#
# 也可用 hdc shell 手动执行：
#   hilog -x | grep -aE 'MAPPER_SRV|gbmmap|mmap failed|AllocBuffer|Map failed|SurfaceBufferImpl|Bufferqueue'

set -u

HDC="${HDC:-$OH_SRC/prebuilts/ohos-sdk/linux/15/toolchains/hdc}"
TARGET="${TARGET:-LubanCat4-0001}"
LOG_FILE="/tmp/map_failed_diag_$(date +%Y%m%d_%H%M%S).log"

echo "==> hdc list targets"
"$HDC" list targets || true

echo "==> 停止 usb_host（避免 SIGSEGV 刷屏）"
"$HDC" -t "$TARGET" shell param set ohos.servicectrl.stop usb_host || true

echo "==> 记录 Map 失败前基线（进程/设备/DRM）"
{
  "$HDC" -t "$TARGET" shell ps -ef | grep -E 'render_service|launcher|allocator|mapper|composer' || true
  "$HDC" -t "$TARGET" shell ls -l /dev/dri 2>/dev/null || true
  "$HDC" -t "$TARGET" shell cat /sys/class/drm/card0-HDMI-A-1/status 2>/dev/null || true
  "$HDC" -t "$TARGET" shell ls /sys/class/vtconsole 2>/dev/null || true
} > "$LOG_FILE"

echo "==> 重启 render_service（约 10s）"
"$HDC" -t "$TARGET" shell begetctl stop render_service || true
sleep 1
"$HDC" -t "$TARGET" shell begetctl start render_service || true
sleep 8

echo "==> 重启 launcher（让渲染面连上新 RS）"
"$HDC" -t "$TARGET" shell 'ps -ef | grep -E "launcher|com.ohos.launcher" | awk "{print \\$2}"' >/dev/null 2>&1
LAUNCHER_PID=$("$HDC" -t "$TARGET" shell 'ps -ef | grep -E "com.ohos.launcher|launcher" | grep -v grep | head -1 | awk "{print \$2}"' 2>/dev/null | tr -d '\r')
if [ -n "${LAUNCHER_PID}" ]; then
  echo "   kill launcher pid=${LAUNCHER_PID}"
  "$HDC" -t "$TARGET" shell kill -9 "${LAUNCHER_PID}" || true
fi
sleep 6

echo "==> 抓取关键日志（20s 窗口）"
{
  echo "---- hilog Map/Mapper/GBM ----"
  timeout 20 "$HDC" -t "$TARGET" shell hilog -x | grep -aE \
    'MAPPER_SRV|ALLOC_SRV|gbmmap|mmap failed|AllocBuffer|Map failed|SurfaceBufferImpl|Bufferqueue|Load.*VDI|CreateDisplayBuffer' || true
} >> "$LOG_FILE"

echo
echo "结果已写入：$LOG_FILE"
echo "判读：
  1) 'mmap failed errno ... fd : N' => mmap 层失败，看 errno
  2) 'Load buffer VDI failed'       => 本进程 VDI dlopen 失败
  3) 仅有 'Map failed ret:50001000' 而无 GBM 日志 => mapper 未真正执行 mmap（VDI null / 远程 mapper）
  4) 无任何日志 => 需要把窗口抓长，或用 hilog -r 后重跑"
