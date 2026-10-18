# 板级配置归档（board-config/）

**这两个目录是本次移植最核心的资产，但它们在 OpenHarmony 源码树里不是 git 仓库**
（`device/board/embedfire/lubancat4` 与 `vendor/embedfire/lubancat4` 从未 `git init`，
也不在任何 manifest 中）。删除源码树就会永久丢失，因此单独归档到这里。

> `docs/05` §5.2 与 §六 待办第 4 条都记录过这个风险：
> 「板级目录纳入版本控制 —— 建议 `git init` 或纳入 `local_manifests`」。
> 本目录即该待办的产物。

---

## 目录结构

```
board-config/
├── board/    ← 来自 device/board/embedfire/lubancat4（84 文件 / 5.4 MB）
└── vendor/   ← 来自 vendor/embedfire/lubancat4（119 文件 / 1.1 MB）
```

恢复时放回源码树对应位置：

```bash
cp -r board-config/board/  "$OH_SRC/device/board/embedfire/lubancat4/"
cp -r board-config/vendor/ "$OH_SRC/vendor/embedfire/lubancat4/"
```

---

## 一、board/（板级目录）

### 1.1 移植关键文件

| 路径 | 作用 | 相关文档 |
|---|---|---|
| `kernel/build_kernel.sh` | 内核构建入口，`BOARD_KERNEL_DIR` 指向 HDF 专用内核 | docs/03 §3 |
| `kernel/make-ohos.sh` | extlinux 生成：`root=PARTUUID=`、`hardware=lubancat4`、`enforcing=0`、6 条 `ohos.required_mount.*` | docs/05 §2 |
| `kernel/kernel_config/linux-5.10/arch/arm64/rk3588_standard_defconfig` | 板级内核配置 | docs/03 §3 |
| `kernel/kernel_patch/linux-5.10/dayu210_patch/hdf.patch` | **方案 B 的 HDF 钩子补丁**（13 个 diff） | docs/03 §2.3 |
| `cfg/lubancat-init.sh` | 板级启动脚本：固化 IP/网关 + **开机黑屏自愈** | docs/05 §10.3 |
| `cfg/init.lubancat4.cfg`、`cfg/fstab.lubancat4`、`cfg/fstab.required` | init 配置与挂载表 | docs/05 §2 |
| `loader/parameter.txt` | **12 分区表**（`uuid:system=614e0000-…`） | docs/05 §2 |
| `config.gni`、`device.gni`、`BUILD.gn`、`ohos.build` | 构建配置 | — |

### 1.2 其他内容（原厂自带 + 少量适配）

- `audio_drivers/` —— ES8323 编解码器、RK3588 DAI/DMA 驱动适配（C 源码）
- `camera/vdi_impl/` —— V4L2 相机管线节点（`rk_codec_node.cpp` 等）
- `bluetooth/` —— 蓝牙协议栈适配
- `hdf_config/`、`hals/` —— HDF 驱动配置与 HAL 实现
- `bootanimation/`、`logo*.bmp` —— 开机动画与 logo 资源
- `uboot/`、`startup/`、`updater/`、`distributedhardware/`、`resourceschedule/`、`default_app_config/`、`preinstall-config/`、`image_conf/`、`etc/`

---

## 二、vendor/（产品配置）

### 2.1 移植关键文件

| 路径 | 作用 | 相关文档 |
|---|---|---|
| `config.json` | 产品配置。**`:160` 有 `graphic_2d_feature_rs_enable_uni_render = true`**（黑屏根因④的修法） | docs/05 §3 |
| `window_config/display_manager_config.xml` | DPI 配置（PC/2in1 方向已改动态化） | docs/05 §25 |
| `window_config/window_manager_config.xml` | WMS 配置，含 `maxFloatingWindowSize` | docs/05 §27–28 |
| `hdf_config/khdf/device_info/device_info.hcs` | HDF 设备信息 | — |
| `hdf_config/uhdf/` | UHDF 各外设配置（camera / usb_ecm_acm / media_codec） | — |
| `security_config/` | 高权限进程名单、sanitizer 名单 | — |
| `image_conf/`、`updater_config/` | 镜像分区与 OTA 配置 | — |

### 2.2 其他内容

`bluetooth/`（含 `BCM4362A2.hcd` 固件）、`hals/`、`etc/`、`preinstall-config/`、`resourceschedule/`、`default_app_config/`、`product.gni`、`ohos.build`

---

## 三、有意未包含的内容

| 内容 | 体积 | 理由 |
|---|---|---|
| `bootanimation/*.raw` | 16 MB | 原始帧资源，体积大且可由 `bootanimation/` 下的其他文件重新生成 |
| `loader/uboot.img`、`loader/MiniLoaderAll.bin` | 4.5 MB | 二进制镜像，可从原厂 `rkbin` / `u-boot` 仓库获取 |
| `kernel/logo*.bmp` | 34 KB | 图片资源（本仓库不发布图片） |
| `kernel/kernel_patch/.../kernel.patch` 与 `.bak` | 4.7 MB | **dayu210 的上游补丁，已被方案 B 弃用**（结构性错配，见 docs/03 §2）。只保留在用的 `hdf.patch` |
| `hdf_config/khdf/*.o`、`*.hcb`、`*.cmd`、`*.order` | — | HDF 编译产物 |
| `vendor/bluetooth/BCM4362A2.hcd` | 73 KB | 博通蓝牙芯片固件（厂商二进制，可从原厂 BSP 获取） |
| `kernel/logo*.bmp`、`**/media/*.png` | 44 KB | 图片资源（本仓库不发布图片） |
| `config.json.bak-mini_rich` | — | 备份文件 |

> ⚠️ `loader/MiniLoaderAll.bin` 有版本要求：**必须 448960 字节那版**（DDR V1.08 / SPL 在 0x2000 找 FIT），
> 487872 那版配 8 分区表，刷错起不来。详见 docs/05 §5.2。

---

## 四、脱敏说明

| 原始值 | 处理 |
|---|---|
| `NET_IP` / `NET_GW`（板级静态 IP 与网关） | `192.168.x.200` / `192.168.x.1` |
| `BOARD_KERNEL_DIR`（绝对路径） | `$LUBANCAT_SDK/openharmony-kernel` |

---

## 五、许可

- `board/`、`vendor/` 多数文件源自野火 LubanCat BSP，版权归原权利人
- `cfg/lubancat-init.sh`、`kernel/make-ohos.sh` 的移植改动、`kernel_patch/hdf.patch`
  为本次移植新增，可随本仓库 MIT 许可使用
- 上游 OpenHarmony 相关部分遵循 Apache 2.0
