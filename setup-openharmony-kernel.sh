#!/bin/bash
# =============================================================================
# setup-openharmony-kernel.sh
# =============================================================================
# 作用：把一份 LubanCat 原厂内核 改造成 "LubanCat BSP + OpenHarmony HDF 框架"
#       的内核（能在 RK3588S 实板启动 + HDF 驱动框架运行）。
#
# 用法：
#   ./setup-openharmony-kernel.sh <LubanCat内核目录> <OH源码根目录>
#   例：./setup-openharmony-kernel.sh $HOME/LubanCat_SDK/kernel-5.10 $HOME/openharmony-lts
#
# 前提：先 cp -a 一份原厂内核（别在原 SDK 内核上直接改）：
#   cp -a LubanCat_SDK/kernel-5.10 LubanCat_SDK/openharmony-kernel
#
# 验证状态（2026-07-11 实测）：
#   - 内核编译 0 错误，boot.img 40MB
#   - 烧到 LubanCat4 实板：正常启动进 Debian 11
#   - HDF 框架运行：/dev/hdf/ 下 15 个设备节点（GPIO/I2C/PWM/UART/输入）
#   - 这是 OH 官方 dayu210 从未达到的状态（dayu210 的 kernel.patch 打不上）
# =============================================================================

set -e

KERNEL_DIR="$1"          # LubanCat 内核目录（要改造的）
OHOS_SRC="$2"            # OH 源码根目录（$HOME/openharmony-lts）

if [ -z "$KERNEL_DIR" ] || [ -z "$OHOS_SRC" ]; then
    echo "用法: $0 <LubanCat内核目录> <OH源码根目录>"
    exit 1
fi

cd "$KERNEL_DIR"
echo "=== 改造内核: $KERNEL_DIR ==="
echo "=== OH 源码:  $OHOS_SRC ==="

HDF_PATCH="$OHOS_SRC/device/board/hihope/dayu210/kernel/kernel_patch/linux-5.10/dayu210_patch/hdf.patch"

# -----------------------------------------------------------------------------
# 步骤 1: 打 HDF 框架补丁（13 文件：HID/USB/input 钩子 + drivers/hdf/Makefile）
# -----------------------------------------------------------------------------
# 原因: HDF 框架需要这些钩子接入内核（hid-core.c 报告输入事件、drivers/hdf 目录等）
# 来源: OH dayu210 官方 hdf.patch
# 注意: drivers/hid/hid-core.c 会因 LubanCat 多一行 <linux/uhid.h> 而失败 1 个 hunk
#       （build4 实测），失败后手工补两处 include 即可
echo ">>> [1/7] 打 hdf.patch（HDF 框架钩子）..."
patch -p1 --no-backup-if-mismatch < "$HDF_PATCH" || true
# hid-core.c Hunk#1 手工修复（LubanCat hid-core.c 比 OH 多 #include <linux/uhid.h>）
# 补 #include <linux/delay.h>（在 semaphore.h 后）+ HDF input 适配头（在 hid-ids.h 前）
if ! grep -q "hdf_hid_adapter.h" drivers/hid/hid-core.c 2>/dev/null; then
    sed -i '/#include <linux\/semaphore.h>/a #include <linux/delay.h>' drivers/hid/hid-core.c
    sed -i '/#include "hid-ids.h"/i #if defined(CONFIG_DRIVERS_HDF_INPUT)\n#include "hdf_hid_adapter.h"\n#endif' drivers/hid/hid-core.c
fi
rm -f drivers/hid/hid-core.c.rej

# -----------------------------------------------------------------------------
# 步骤 2: 接入 HDF 驱动源码（建软链 + 拷第三方组件）
# -----------------------------------------------------------------------------
# 原因: hdf.patch 只放框架钩子，真正的 HDF 驱动代码（osal/manager/platform/input 模型）
#       在 OH 源码的 drivers/hdf_core/。这是 OH patch_hdf.sh 的第二步。
# ⚠️ 副作用: 软链会导致编译时 .o 写进 OH 源码树（污染），用完 git checkout 清理
echo ">>> [2/7] 建 HDF 软链 + 拷第三方组件..."
ln -sf "$OHOS_SRC/drivers/hdf_core/adapter/khdf/linux"    drivers/hdf/khdf
ln -sf "$OHOS_SRC/drivers/hdf_core/framework"             drivers/hdf/framework
ln -sf "$OHOS_SRC/drivers/hdf_core/interfaces/inner_api"  drivers/hdf/inner_api
mkdir -p include
ln -sf "$OHOS_SRC/drivers/hdf_core/framework/include"     include/hdf
mkdir -p bounds_checking_function
cp -arfL "$OHOS_SRC/third_party/bounds_checking_function/"* bounds_checking_function/ 2>/dev/null || true
mkdir -p drivers/hdf/evdev
cp -arfL "$OHOS_SRC/third_party/FreeBSD/sys/dev/evdev/"* drivers/hdf/evdev/ 2>/dev/null || true

# -----------------------------------------------------------------------------
# 步骤 3: 拷 4 个 OH 预置 trace 头文件
# -----------------------------------------------------------------------------
# 原因: HDF 的 platform_trace.c 引用 <trace/events/platform_trace_event.h>，
#       该文件是 OH 内核自带的，LubanCat 内核没有（build4 实测缺失）
echo ">>> [3/7] 拷 OH 预置 trace 头..."
for f in eas_sched.h platform_trace_event.h rtg.h walt.h; do
    cp "$OHOS_SRC/kernel/linux/linux-5.10/include/trace/events/$f" include/trace/events/ 2>/dev/null && echo "  ✓ $f"
done

# -----------------------------------------------------------------------------
# 步骤 4: 禁用 Rockchip gcc-wrapper.py（Makefile:493 附近）
# -----------------------------------------------------------------------------
# 原因: Rockchip 内核自带 scripts/gcc-wrapper.py，把白名单外的【所有】警告变成致命
#       错误。HDF 头的 SW_MAX/FF_CNT 重定义会被它拦（build3 实测）。OH 内核无此机制。
# 做法: 注释掉 Makefile 里 CC = .../gcc-wrapper.py gcc 那行
echo ">>> [4/7] 禁用 gcc-wrapper.py（forbidden warning 机制）..."
sed -i 's|^CC\t\t= $(abspath $(srctree)/scripts/gcc-wrapper.py)|# OH port: disabled gcc-wrapper.py (turns all non-whitelisted warnings into errors)\n# CC\t\t= $(abspath $(srctree)/scripts/gcc-wrapper.py) $(CROSS_COMPILE)gcc|' Makefile

# -----------------------------------------------------------------------------
# 步骤 5: arch/arm64/Makefile —— 删 -mgeneral-regs-only + 加 -mno-outline-atomics
# -----------------------------------------------------------------------------
# 原因 A（删 -mgeneral-regs-only）: HDF 的 hdf_sbuf.c 用了 float（HdfSbufWriteFloat/
#       WriteDouble），与内核禁止浮点的 -mgeneral-regs-only 冲突，gcc 7.5/10.3 都报错
#       （build4/5 实测）。照搬 zhiyuan 板 hdf.patch 的做法（kernel/linux/patches/
#       linux-5.10/zhiyuan_patch/hdf.patch）——它在 arch/arm64/Makefile 删此标志。
# 原因 B（加 -mno-outline-atomics）: gcc-10+ 默认 -moutline-atomics，把原子操作变成
#       调用 __aarch64_cas* 辅助函数，内核不链接 libgcc 导致 undefined reference
#       （build9 实测）。OH 用 gcc-7.5 无此特性故不踩坑。
echo ">>> [5/7] arch/arm64/Makefile: 删 -mgeneral-regs-only + 加 -mno-outline-atomics..."
sed -i 's/-mgeneral-regs-only//' arch/arm64/Makefile
# 在 compat_vdso 行后插入 -mno-outline-atomics（避免重复加）
grep -q "mno-outline-atomics" arch/arm64/Makefile || \
    sed -i '/KBUILD_CFLAGS.*+= \$(compat_vdso) \$(cc_has_k_constraint)/a KBUILD_CFLAGS   += -mno-outline-atomics' arch/arm64/Makefile

# -----------------------------------------------------------------------------
# 步骤 6: 顶层 Makefile —— 放宽两个 -Werror（照搬 zhiyuan）
# -----------------------------------------------------------------------------
# 原因: HDF 代码有指针类型/原型不匹配的警告，被 -Werror 拦（build8 实测）。
#       zhiyuan 板的 hdf.patch 就是这么放宽的。
echo ">>> [6/7] 顶层 Makefile: 放宽 -Werror=strict-prototypes + incompatible-pointer-types..."
sed -i 's|-Werror=strict-prototypes ||' Makefile
sed -i 's|-Werror=incompatible-pointer-types|-Wno=incompatible-pointer-types|' Makefile

# -----------------------------------------------------------------------------
# 步骤 7: .config —— 开 HDF（platform+input）+ 关 USB PnP + 关 WERROR
# -----------------------------------------------------------------------------
# 原因 A（开 HDF platform/input）: 这是 HDF 驱动框架的核心模型，提供 GPIO/I2C/PWM/
#       UART/输入接口。
# 原因 B（关 USB PnP notify）: usb_pnp_notify.c 用了 C99 for 循环声明变量（for(int i..)），
#       与内核 -std=gnu89 冲突报错（build7 实测）。zhiyuan 配置里也没开这个，故对齐。
# 原因 C（关 WERROR）: LubanCat 默认 CONFIG_WERROR=y，会把 HDF 头的重定义警告变致命
#       （build2 实测）。OH 内核 defconfig 不开 WERROR。
echo ">>> [7/7] 配置 .config: 开 HDF + 关 USB PnP + 关 WERROR..."
echo "  （先确保已 make defconfig 生成 .config，本步在其基础上调整）"
if [ -f .config ]; then
    sed -i 's/^CONFIG_WERROR=y/# CONFIG_WERROR is not set/' .config
    cat >> .config << 'EOF'
CONFIG_DRIVERS_HDF=y
CONFIG_HDF_SUPPORT_LEVEL=2
CONFIG_DRIVERS_HDF_PLATFORM=y
CONFIG_DRIVERS_HDF_PLATFORM_GPIO=y
CONFIG_DRIVERS_HDF_PLATFORM_I2C=y
CONFIG_DRIVERS_HDF_INPUT=y
CONFIG_DRIVERS_HDF_PLATFORM_PWM=y
CONFIG_DRIVERS_HDF_PLATFORM_UART=y
CONFIG_DRIVERS_HDF_PLATFORM_SPI=y
CONFIG_DRIVERS_HDF_PLATFORM_TRACE=y
CONFIG_DRIVERS_HDF_PLATFORM_DUMPER=y
# CONFIG_DRIVERS_HDF_USB_PNP_NOTIFY is not set
# CONFIG_DRIVERS_HDF_USB_F_GENERIC is not set
EOF
    echo "  ✓ .config 已更新（需再跑 make olddefconfig 解析依赖）"
else
    echo "  ⚠️  无 .config，请先 make ARCH=arm64 CROSS_COMPILE=<tc> lubancat_linux_rk3588_defconfig"
fi

# -----------------------------------------------------------------------------
# 备注：rk805-pwrkey.c
# -----------------------------------------------------------------------------
# LubanCat 原版的 rk805-pwrkey.c 没有 HDF 代码，直接保留原样即可（HDF 开时也能编，
# 只是 powerkey 不通过 HDF 上报，走标准 input——不影响内核启动）。
# dayu210 的 hdf.patch 给这文件加了无守卫的 HDF 调用，若打了 hdf.patch 会被改；
# 如需还原原版: cp <原厂内核>/drivers/input/misc/rk805-pwrkey.c drivers/input/misc/

echo ""
echo "=== 改造完成 ==="
echo "下一步:"
echo "  1. make ARCH=arm64 CROSS_COMPILE=<linaro或gcc-10.3> olddefconfig   # 解析 HDF 配置依赖"
echo "  2. export PRODUCT_PATH=vendor/hihope/dayu210                       # khdf Makefile 需要"
echo "  3. make ARCH=arm64 CROSS_COMPILE=<tc> Image -j20                   # 编内核"
echo "  4. make ARCH=arm64 CROSS_COMPILE=<tc> rk3588s-lubancat-4.img       # 打包 boot.img"
echo ""
echo "工具链建议: gcc-arm-10.3（LubanCat 原生）。注意必须配合步骤5的 -mno-outline-atomics。"
