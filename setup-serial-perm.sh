#!/bin/bash
# =============================================================================
# WSL USB 设备权限一键设置（串口 + RK 烧录设备）
#
# 用途：WSL 每次重启后，/dev/ttyUSB0 权限是 root:root 0600，且 ch341 驱动未加载，
#       导致必须手动 sudo modprobe + sudo chmod。本脚本一步搞定。
#
# 用法：
#   sudo bash setup-serial-perm.sh      # 推荐
#   或直接执行（非 root 时自动用 sudo）
#
# 依赖：串口设备需已通过 usbipd 透传到 WSL（Windows 侧：usbipd attach --wsl --busid X）
# =============================================================================
set -e

# 非 root 时自动提权
if [ "$(id -u)" -ne 0 ]; then
    echo ">>> 需要 root，自动用 sudo 重新执行..."
    exec sudo bash "$0" "$@"
fi

echo "=== 1/3 加载 ch341 串口驱动 ==="
if ! lsmod | grep -q ch341; then
    modprobe ch341 && echo "✓ ch341 已加载" || echo "✗ ch341 加载失败"
else
    echo "✓ ch341 已在"
fi

echo "=== 2/3 提升串口设备权限 ==="
if [ -e /dev/ttyUSB0 ]; then
    chmod 666 /dev/ttyUSB0
    echo "✓ /dev/ttyUSB0 -> $(stat -c '%A' /dev/ttyUSB0)"
else
    echo "⚠ /dev/ttyUSB0 不存在！"
    echo "  请确认：1) 串口线已插好  2) Windows 已执行 usbipd attach --wsl --busid <串口busid>"
fi

echo "=== 3/3 提升 RK 烧录设备权限（upgrade_tool 用）==="
if ls /dev/bus/usb/*/* >/dev/null 2>&1; then
    chmod 666 /dev/bus/usb/*/*
    echo "✓ /dev/bus/usb 设备权限已放开"
else
    echo "（当前无 USB 总线设备，跳过）"
fi

echo ""
echo "完成。串口可用性："
ls -l /dev/ttyUSB0 2>/dev/null || echo "  /dev/ttyUSB0 仍未出现（见上方提示）"
