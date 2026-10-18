#!/bin/bash

# Copyright (c) 2021 HiHope Open Source Organization .
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e

export PATH=../../../../prebuilts/clang/ohos/linux-x86_64/llvm/bin/:$PATH
export PRODUCT_PATH=vendor/embedfire/lubancat4
IMAGE_SIZE=64  # 64M
IMAGE_BLOCKS=4096

CPUs=`sed -n "N;/processor/p" /proc/cpuinfo|wc -l`
MAKE="make CROSS_COMPILE=../../../../prebuilts/gcc/linux-x86/aarch64/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-"
BUILD_PATH=boot_linux
EXTLINUX_PATH=${BUILD_PATH}/extlinux
EXTLINUX_CONF=${EXTLINUX_PATH}/extlinux.conf
TOYBRICK_DTB=toybrick.dtb
if [ ${KBUILD_OUTPUT} ]; then
	OBJ_PATH=${KBUILD_OUTPUT}/
fi

ID_MODEL=1
ID_ARCH=2
ID_UART=3
ID_DTB=4
ID_IMAGE=5
ID_CONF=6
model_list=(
	"TB-RK3568X0   arm64 0xfe660000 rk3568-toybrick-x0-linux  Image rockchip_linux_defconfig"
	"TB-RK3568X10  arm64 0xfe660000 rk3568-toybrick-x10-linux Image rockchip_linux_defconfig"
	"BQ3588C1      arm64 0xfe660000 rk3588-bearkey-bq3588c1-linux  Image rockchip_linux_defconfig"
)


function help()
{
	echo "Usage: ./make-ohos.sh {BOARD_NAME}"
	echo "e.g."
	for i in "${model_list[@]}"; do
		echo "  ./make-ohos.sh $(echo $i | awk '{print $1}')"
	done
}


function make_extlinux_conf()
{
	dtb_path=$1
	uart=$2
	image=$3
	
	echo "label rockchip-kernel-5.10" > ${EXTLINUX_CONF}
	echo "	kernel /extlinux/${image}" >> ${EXTLINUX_CONF}
	echo "	fdt /extlinux/${TOYBRICK_DTB}" >> ${EXTLINUX_CONF}
	# hardware= 必须存在：param 服务据此生成 ohos.boot.hardware；
	# 第一阶段 fstab.c 与第二阶段 init.cfg 的 mount_fstab_sp 都用它拼路径
	#   /vendor/etc/fstab.${ohos.boot.hardware}      -> /vendor/etc/fstab.lubancat4
	#   /vendor/etc/init.${ohos.boot.hardware}.cfg   -> /vendor/etc/init.lubancat4.cfg
	# 缺失则 /data、/sys_prod、/chip_prod 永不挂载，init 判定启动失败并 reboot panic。
	cmdline="append earlycon=uart8250,mmio32,${uart} root=PARTUUID=614e0000-0000-4b53-8000-1d28000054a9 rw rootwait rootfstype=ext4 hardware=lubancat4"
	# enforcing=0：bring-up 阶段先让 SELinux 走 permissive。
	# 原因：system.img 内 /system/etc/selinux/config 是 SELINUX=enforcing，
	# 而随包策略（third_party/selinux，北京万里红版本）对 lubancat4 的服务覆盖不全，
	# 会出现 foundation->dev_at_file:chr_file ioctl 等大量 AVC 拒绝，
	# 导致 appfwk / launcher 起不来。内核 cmdline 的 enforcing= 可覆盖该配置。
	# 策略补齐后可删除此参数恢复 enforcing。
	cmdline="${cmdline} enforcing=0"
	# 第一阶段 init(init_early) 从内核 cmdline 读取 required fstab：
	#   格式 <block device>@<mount point>@<fstype>@<mount options>@<fsmgr flags>
	# 两个作用：
	#   1) system 挂到 /usr 后立即 SwitchRoot("/usr")，之后 execv("/bin/init") 才解析到 system 镜像；
	#   2) ueventd 只给「带 required 标志的条目」或名字里含 vendor/system/chipset/boot/
	#      ramdisk/rvt/dtbo/modem_driver 的分区创建 /dev/block/.../by-name/ 节点
	#      （见 base/startup/init/ueventd/ueventd.c:177 的 HandleRequiredBlockDeviceNodes）。
	#      sys-prod / chip-prod / userdata / misc 这些名字不含任何关键词，所以**必须**标 required，
	#      否则 ueventd 不建 by-name 节点，第二阶段 mount_fstab_sp 会一直等到超时后失败。
	# 说明：第一阶段挂载失败只记日志（fstab_mount.c 的 "Ignore failure" 分支），不会中断启动，
	#       因此这里统一标 required 只为拿到设备节点，是安全的。
	cmdline="${cmdline} ohos.required_mount.system=/dev/block/platform/fe2e0000.mmc/by-name/system@/usr@ext4@ro,barrier=1@wait,required"
	cmdline="${cmdline} ohos.required_mount.vendor=/dev/block/platform/fe2e0000.mmc/by-name/vendor@/vendor@ext4@ro,barrier=1@wait,required"
	cmdline="${cmdline} ohos.required_mount.sys_prod=/dev/block/platform/fe2e0000.mmc/by-name/sys-prod@/sys_prod@ext4@ro,barrier=1@wait,required"
	cmdline="${cmdline} ohos.required_mount.chip_prod=/dev/block/platform/fe2e0000.mmc/by-name/chip-prod@/chip_prod@ext4@ro,barrier=1@wait,required"
	# /data 必须带 fs_mgr 的 fileencryption=software,quota（对齐 dayu210 的 fstab）：
	# 否则 StorageDaemon 的 /data/storage/el1 布局建不出来（appfwk/launcher 卡住），
	# 且 el5_filekey_manager 会因等待密钥而卡死被 SAMGR 清理。
	# userdata.img 的 f2fs superblock 本身带 encrypt/project_quota 特性，可直接启用。
	cmdline="${cmdline} ohos.required_mount.data=/dev/block/platform/fe2e0000.mmc/by-name/userdata@/data@f2fs@discard,noatime,nosuid,nodev@wait,required,fileencryption=software,quota"
	cmdline="${cmdline} ohos.required_mount.misc=/dev/block/platform/fe2e0000.mmc/by-name/misc@/misc@none@none@wait,required"
	echo "  ${cmdline}" >> ${EXTLINUX_CONF}
}

function make_kernel_image()
{
	arch=$1
	conf=$2
	dtb=$3
	
	${MAKE} ARCH=${arch} ${conf}
	if [ $? -ne 0 ]; then
		echo "FAIL: ${MAKE} ARCH=${arch} ${conf}"
		return -1
	fi

	${MAKE} ARCH=${arch} ${dtb}.img -j${CPUs}
	if [ $? -ne 0 ]; then
		echo "FAIL: ${MAKE} ARCH=${arch} ${dtb}.img"
		return -2
	fi

	return 0
}

function make_ext2_image()
{
	blocks=${IMAGE_BLOCKS}
	block_size=$((${IMAGE_SIZE} * 1024 * 1024 / ${blocks}))

	if [ "`uname -m`" == "aarch64" ]; then
		echo y | sudo mke2fs -b ${block_size} -d boot_linux -i 8192 -t ext2 boot_linux.img ${blocks}
	else
		genext2fs -B ${blocks} -b ${block_size} -d boot_linux -i 8192 -U boot_linux.img
	fi

	return $?
}

function make_boot_linux()
{
	arch=${!ID_ARCH}
	uart=${!ID_UART}
	dtb=${!ID_DTB}
	image=${!ID_IMAGE}
	conf=${!ID_CONF}
	if [ ${arch} == "arm" ]; then
		dtb_path=vendor/arch/arm/boot/dts
	else
		dtb_path=vendor/arch/arm64/boot/dts/rockchip
	fi

	rm -rf ${BUILD_PATH}
	mkdir -p ${EXTLINUX_PATH}

	make_kernel_image ${arch} ${conf} ${dtb}
	if [ $? -ne 0 ]; then
		exit 1
	fi
	make_extlinux_conf ${dtb_path} ${uart} ${image}
	cp -f ${OBJ_PATH}arch/${arch}/boot/${image} ${EXTLINUX_PATH}/
	cp -f ${OBJ_PATH}${dtb_path}/${dtb}.dtb ${EXTLINUX_PATH}/${TOYBRICK_DTB}
	cp -f logo*.bmp ${BUILD_PATH}/
	if [ "enable_ramdisk" != "${ramdisk_flag}" ]; then
		make_ext2_image
	fi
}

ramdisk_flag=$2
found=0
for i in "${model_list[@]}"; do
	if [ "$(echo $i | awk '{print $1}')" == "$1" ]; then
		make_boot_linux $i
		found=1
	fi
done

