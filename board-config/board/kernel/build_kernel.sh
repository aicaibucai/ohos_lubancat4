#!/bin/bash
# LUBANCAT4 kernel action
#
# 内核方案 B（见 work/lubancat4-openharmony-porting 文档）：
#   内核 = LubanCat 原厂 5.10.209 + HDF 补丁 + OH binder/access_token（CONFIG_ASHMEM=y 的内核 #14）
#   内核不参与 OH 构建：本脚本不编译内核，只用已编译好的 Image 组装启动镜像。
#
# boot_linux.img 采用与板卡已验证启动一致的 **Android boot image** 格式：
#   --kernel  arch/arm64/boot/Image
#   --second  resource_hdmi2.img（内含 rk-kernel.dtb + logo，由 u-boot 从 resource 分区加载 dtb）
#   参数（base/offsets/pagesize/cmdline）均与出厂 boot.img 头一致。
#   root= 由板卡 u-boot 环境变量 bootargs 提供（与之前成功启动时一致）。
#
# 参数(由 BUILD.gn 传入):
#   $1 kernel_build_script_dir  $2 images 目录  $3 device 板级目录
#   $4 product_path             $5 源码根目录   $6 device_company
#   $7 device_name              $8 product_company
set -e

ROOT_DIR=${5}
IMG_DIR=${2}
DEVICE_PATH=${3}

BOARD_KERNEL_DIR=${BOARD_KERNEL_DIR:-$LUBANCAT_SDK/openharmony-kernel}
BOARD_RESOURCE=${BOARD_RESOURCE:-resource_hdmi2.img}

KERNEL_IMAGE=${BOARD_KERNEL_DIR}/arch/arm64/boot/Image
RESOURCE_IMG=${BOARD_KERNEL_DIR}/${BOARD_RESOURCE}
MKBOOTIMG=${BOARD_KERNEL_DIR}/scripts/mkbootimg

for f in "${KERNEL_IMAGE}" "${RESOURCE_IMG}" "${MKBOOTIMG}"; do
    if [ ! -f "${f}" ]; then
        echo "LUBANCAT4 ERROR: 缺少 ${f}" >&2
        exit 1
    fi
done

# OH 构建期望的内核标记文件（占位，内核本体不在此编译）
mkdir -p ${ROOT_DIR}/out/kernel/src_tmp/linux-5.10
touch ${ROOT_DIR}/out/kernel/src_tmp/linux-5.10/boot_linux
mkdir -p ${IMG_DIR}

# 组装 Android 格式启动镜像（参数与出厂 boot.img 完全一致）
python3 "${MKBOOTIMG}" \
    --kernel "${KERNEL_IMAGE}" \
    --second "${RESOURCE_IMG}" \
    --cmdline "androidboot.hardware=lubancat4" \
    --base 0x10000000 --kernel_offset 0x8000 \
    --second_offset 0xf00000 --tags_offset 0x100 \
    --pagesize 2048 --header_version 0 \
    -o "${IMG_DIR}/boot_linux.img"

# resource.img（dtb + logo，u-boot 阶段用）
cp "${RESOURCE_IMG}" "${IMG_DIR}/resource.img"

# 引导相关预编译二进制（来自板级 loader 目录）
cp "${DEVICE_PATH}/loader/parameter.txt"     "${IMG_DIR}/parameter.txt"     2>/dev/null || true
cp "${DEVICE_PATH}/loader/MiniLoaderAll.bin" "${IMG_DIR}/MiniLoaderAll.bin" 2>/dev/null || true
cp "${DEVICE_PATH}/loader/uboot.img"         "${IMG_DIR}/uboot.img"         2>/dev/null || true
cp "${DEVICE_PATH}/loader/config.cfg"        "${IMG_DIR}/config.cfg"        2>/dev/null || true

echo "LUBANCAT4: kernel action done (board kernel Image + ${BOARD_RESOURCE}, android boot image)"
exit 0
