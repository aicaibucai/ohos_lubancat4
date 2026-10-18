# 移植补丁集（kernel-patches/）

本目录保存 LubanCat4（RK3588S）上 OpenHarmony 6.1 移植的**全部源码改动**，
以标准 `git apply` 可应用的 patch 形式交付。

> **与 `changes-5.0.3/` 的区别**：
> - `changes-5.0.3/` 是 **OpenHarmony 5.0.3** 阶段的历史归档（2026-09-06）
> - 本目录是 **当前 6.1 阶段**的活跃改动，与 `docs/05-6.1进展与当前状态.md` 描述的状态对应

---

## 目录结构

```
kernel-patches/
├── README.md                      ← 本文件
├── openharmony-kernel.patch       ← 内核改动（512 KB / 88 diff）
└── openharmony/                   ← OpenHarmony 源码树改动（13 个 patch）
    ├── applications_standard_launcher.patch
    ├── applications_standard_screenlock.patch
    ├── base_theme_screenlock_mgr.patch
    ├── build.patch
    ├── developtools_integration_verification.patch
    ├── device_board_hihope.patch
    ├── drivers_peripheral.patch
    ├── foundation_arkui_ace_engine.patch
    ├── foundation_arkui_napi.patch
    ├── foundation_graphic_graphic_2d.patch
    ├── foundation_window_window_manager.patch
    ├── third_party_toybox.patch
    └── vendor_hihope.patch
```

---

## 一、内核补丁（openharmony-kernel.patch）

### 1.1 技术背景

采用 **方案 B**：不用 OpenHarmony 的 `kernel.patch`（与厂商内核结构性错配），
而是在**原厂 5.10.209 内核**上直接嫁接 OH 需要的内核特性。
完整决策过程见 [docs/03-编译排查与内核适配.md](../docs/03-编译排查与内核适配.md) 第二章。

### 1.2 改动内容

| 类别 | 文件 | 说明 |
|---|---|---|
| **binder 扩展** | `drivers/android/binder.c`、`binder_internal.h`、`include/uapi/linux/android/binder.h` | OH binder 需要的 3 个结构体（`binder_feature_set`/`access_token`/`binder_sender_info`）+ 3 个 ioctl（nr 30/31/32） |
| **access_token** | `drivers/accesstokenid/`（新增）、`drivers/Kconfig`、`drivers/Makefile`、`include/linux/sched.h`、`include/linux/uidgid.h` | `/dev/access_token_id` 驱动 + `task_struct` 的 `token/ftoken` 字段 |
| **HDF 钩子** | `drivers/hdf/`（新增） | HDF 驱动框架的内核侧适配 |
| **调度 trace** | `include/trace/events/{eas_sched,rtg,walt,platform_trace_event}.h`（新增） | OH 调度器 tracepoint 头文件 |
| **安全函数** | `bounds_checking_function/`（新增） | `*_s` 系列安全 C 函数（`memcpy_s` 等） |
| **DTS** | `rk3588s-lubancat-4.dts`、`rk3588s-lubancat-4-hdmi0.dtsi` | 板级设备树修正（HDMI 使能） |
| **defconfig** | `lubancat_linux_rk3588_defconfig` | `+CONFIG_ACCESS_TOKENID=y` |
| **其他** | `drivers/hid/*`、`drivers/input/misc/*`、`drivers/usb/core/notify.c`、`include/linux/hid.h` 等 | HID/输入/USB 通知链适配 |

### 1.3 应用方法

```bash
# 前提：已克隆原厂内核仓库
git clone https://github.com/LubanCat/kernel openharmony-kernel
cd openharmony-kernel
git checkout <与 patch 头部标注的基线一致的 commit>

# 应用
git apply --check ../kernel-patches/openharmony-kernel.patch   # 先检查
git apply         ../kernel-patches/openharmony-kernel.patch   # 确认后应用

# 或分步应用（只取 binder 部分）
git apply --include='drivers/android/*' ../kernel-patches/openharmony-kernel.patch
```

### 1.4 需要手动处理的两件事

patch **有意不包含**以下两项，应用后需手工补：

1. **`include/hdf` 符号链接** —— 它指向 OpenHarmony 源码树里的 HDF 头文件：
   ```bash
   ln -s "$OH_SRC/drivers/hdf_core/framework/include" include/hdf
   ```
2. **`arch/arm64/boot/Image.bak`** —— 40 MB 的编译产物备份，不属于源码改动。

---

## 二、OpenHarmony 源码树补丁（openharmony/）

### 2.1 应用前提

```bash
# OpenHarmony 6.1 源码树，需与 patch 头部标注的基线一致
cd "$OH_SRC"
```

每个 patch 的头部都记录了**上游地址与基线 commit**，例如：

```
# 仓库: foundation/graphic/graphic_2d
# 上游: https://gitcode.com/openharmony/graphic_graphic_2d
# 基线: 9fdf5854a4 2026-07-15 !31290 merge fix/shape-recursion-dos-6.1 into OpenHarmony-6.1-Release
```

### 2.2 一键应用全部

```bash
cd "$OH_SRC"
for p in <本仓库>/kernel-patches/openharmony/*.patch; do
  repo=$(grep -m1 '^# 仓库:' "$p" | sed 's/^# 仓库: //')
  echo ">>> $repo"
  git -C "$repo" apply --check "$p" && git -C "$repo" apply "$p"
done
```

### 2.3 按改动性质分批应用（推荐）

如果只想复现某一部分，按下面分组：

| 分组 | patch | 对应文档章节 |
|---|---|---|
| **显示链路（黑屏四层根因）** | `foundation_graphic_graphic_2d`、`drivers_peripheral` | docs/05 §3、§10 |
| **RGA 代际不匹配绕过** | `drivers_peripheral`（`hdi_gfx_composition.cpp`） | docs/05 §3 |
| **UniRender 启用** | `foundation_graphic_graphic_2d`（`graphic_config.gni`） | docs/05 §3 |
| **锁屏/解锁** | `base_theme_screenlock_mgr`、`applications_standard_screenlock` | docs/05 §11、§13 |
| **异步 napi（libuv 宏）** | `foundation_arkui_napi`、`patches/napi-uvloop-driver.patch` | docs/05 §18 |
| **PC/2in1 界面** | `patches-2in1-dpi/*`、`foundation_window_window_manager` | docs/05 §24–28 |
| **构建系统** | `build`、`developtools_integration_verification`、`device_board_hihope` | docs/05 §7 |
| **产品配置** | `vendor_hihope` | docs/05 §5 |
| **launcher bring-up** | `applications_standard_launcher` | docs/05 §11.5、§11.6 |

### 2.4 补丁状态说明

所有 patch 均通过 `git apply --check` 验证（14/14）。

⚠️ **`applications_standard_launcher.patch` 里的三处改动是 bring-up 期间的临时绕过**
（RDB S3→S1、库名改写、建窗提前 + race 限时兜底）。
它们在 `docs/05` §11.5/§11.6 有详细记录，**在 libuv 宏问题修复后应逐条回退**。

---

## 三、有意排除的内容

以下内容经核查**不属于本移植改动**，未纳入 patch 集：

| 内容 | 规模 | 排除理由 |
|---|---|---|
| `third_party/node` 二进制 diff | 280149 行 | `deps/brotli` 等上游构建产物变动，占原 `repo diff` 的 98.8% |
| `third_party/sane-airscan`、`cups-filters` | 26 个文件 | 上游 OH 官方 `OH_AIRSCAN` 等适配补丁，`repo sync` 自动应用 |
| `third_party/{iptables,pcre2,freetype,icu,libjpeg-turbo,wpa_supplicant}` | 10 个文件 | 上游 OH 适配 |
| `test/xts/acts` | 12 个文件 | XTS 测试固件 |
| `applications/standard/{user_certificate_manager,app_samples,hap}` | 8 个文件 | 测试样例、预编译 HAP（`SystemUI-ScreenLock.hap` 1.6 MB 二进制） |
| `developtools/packing_tool` | 1 个文件 | 上游工具 |
| `device/soc/rockchip` | 1 个文件 | `resource_tool` 二进制被重新编译，非源码改动 |
| `arkcompiler/ets_frontend` | 3 个文件 | `npm install` 删掉的 `package-lock.json` |
| `foundation/{ability/ability_runtime,communication/*}` | 6 个文件 | `hvigorw` 权限位 + `oh-package-lock.json5` |
| `applications/standard/{dlp_manager,permission_manager}` | 4 个文件 | 同上（npm/hvigor 副作用） |
| `base/powermgr/power_manager` | 4 个文件 | 同上 |
| `local.properties` | — | 含绝对路径 `$OH_SRC/prebuilts/ohos-sdk/linux` |
| `hvigorw` | — | 文件权限位变化，无内容差异 |
| `*.cmd` / `*.o` / `*.o.d` / `*.a` / `*.order` / `*.gch` | 1900+ 个 | 内核与 HDF 构建垃圾 |
| `*.hcb` / `*.rej` / `*.bak` | — | HDF 编译产物、补丁拒绝记录、备份文件 |
| `node_modules/` / `oh_modules/` / `.hvigor/` / `out/` | — | 依赖与构建输出 |

---

## 四、补丁的再生成

源码树继续演进后，用 [`scripts/`](../scripts/) 里的三个脚本重新导出：

```bash
export OH_SRC=/path/to/openharmony-lts
export LUBANCAT_SDK=/path/to/LubanCat_SDK

# 1) 扫描哪些仓库有改动
bash scripts/scan-changed-repos.sh              # 输出 /tmp/repo_changed.txt

# 2) 导出 OpenHarmony 源码树 patch
bash scripts/export-openharmony-patches.sh /tmp/ohos-patches

# 3) 导出内核 patch
bash scripts/export-kernel-patch.sh             # 输出 /tmp/kernel-patch/
```

三个脚本与本文档第三节的排除规则完全一致。

核心排除规则：

```
*.cmd *.o *.o.d *.a *.order *.gch *.pyc *.class *.rej *.lock *.bak *.hcb
package-lock.json package-lock.json5 oh-package-lock.json5
hvigorw local.properties local_paths.properties
*/node_modules/* */oh_modules/* */.hvigor/* */out/* */__pycache__/* */ohos-build/*
```

---

## 五、许可声明

- 内核改动：GPL-2.0（Linux 内核）
- OpenHarmony 源码树改动：Apache 2.0（遵循各上游仓库许可）
- 新增的 `bounds_checking_function/` 与 `drivers/accesstokenid/` 等内容
  来自 OpenHarmony 上游，版权归原权利人所有
