# OpenHarmony 移植 LubanCat4（RK3588S）— 项目导航

> **目标板卡**：野火 LubanCat4（瑞芯微 **RK3588S**，16 GB LPDDR4X）
> **目标系统**：OpenHarmony 6.1（`6.1.0.31` / API 23），从 5.0.3 迁移而来
>
> 本仓库是**移植过程的知识归档**（排错记录 + 补丁 + 日志 + 取证数据），
> 不是可编译的源码树。源码树涉及 OpenHarmony 与厂商 SDK 的多个 git 仓库，体积数百 GB。
>
> 🔒 本仓库已脱敏，敏感信息处理方式见 [SANITIZED.md](SANITIZED.md)。

---

## ⚠️ 先读这个

**当前阶段的最新状态在 [docs/05-6.1进展与当前状态.md](docs/05-6.1进展与当前状态.md)**（2026-10-09 整合，2800 行）。

本 README 与 01–04 描述的是 **v5.0.3 阶段**，除「内核方案 B」外多数结论已被 05 取代。

---

## 一、当前状态速览（以 05 文档为准）

| 阶段 | 状态 |
|---|---|
| OH 5.0.3 最小系统 | ✅ boot complete + root shell + hdc（USB/TCP 双通道） |
| OH 6.1 迁移 | ✅ 源码树已迁到 6.1，板级目录在 6.1 上重建 |
| 显示链路 | ✅ 黑屏四层根因已修（dtb / fstab / RGA / UniRender） |
| 鼠标闪烁 | ✅ 已修（composer 每帧 modeset + EBUSY） |
| 锁屏 / 解锁 | ✅ 已打通（fscrypt el1 被明文填满是根因） |
| 桌面图标 | 🔴 未完成 —— 根因已定位为 **libuv 编译宏三方不匹配**，修法只需改一行 |
| PC / 2in1 界面 | 🔴 进行中 —— DPI 动态化已完成，WMS 浮动窗口上限裁剪 SystemUI 已修 |

---

## 二、文档导航

| 文档 | 内容 | 何时看 |
|---|---|---|
| **[docs/05-6.1进展与当前状态.md](docs/05-6.1进展与当前状态.md)** | OH 6.1 阶段 28 节进展时间线、黑屏根因链、改动清单、构建/刷机复现、待办与风险 | **每次开工必读（最新）** |
| [docs/08-ArkUI输入链路核实与自检开关.md](docs/08-ArkUI输入链路核实与自检开关.md) | 鼠标/输入链路所有权与线程契约核实、release 自检开关（零编译）、待验证实验 | 查输入/鼠标/键盘问题前 |
| [docs/01-总体规划与当前状态.md](docs/01-总体规划与当前状态.md) | 可行性、RK3588S 差异、阶段路线图（带进度） | 总览全局 |
| [docs/02-风险清单与知识迁移.md](docs/02-风险清单与知识迁移.md) | 移植风险清单（R1–R20）+ Android→OH 知识映射、GN/DTS/C 够用知识 | 踩坑前先查 |
| [docs/03-编译排查与内核适配.md](docs/03-编译排查与内核适配.md) | kernel.patch 结构性错配、**内核方案 B**、HDF 内核配方、binder/access_token 移植 | 编译/内核，核心技术文档 |
| [docs/04-调试与操作手册.md](docs/04-调试与操作手册.md) | 串口/hdc/镜像修改/内核重编/烧录全操作 + softbus 排查指引 | 实际操作时照抄 |
| [changes-5.0.3/README.md](changes-5.0.3/README.md) | 5.0.3 阶段全部移植补丁归档与恢复方法 | 需要重放 5.0.3 补丁时 |
| **[kernel-patches/README.md](kernel-patches/README.md)** | **当前 6.1 阶段的内核 + 源码树全部改动，`git apply` 可直接应用** | 要在自己的树上复现移植时 |
| **[board-config/README.md](board-config/README.md)** | **板级与产品配置归档**（`device/board` + `vendor/embedfire`，这两个目录在源码树里不是 git 仓库） | 恢复板级配置 / 了解分区表与 init 脚本 |
| [tools/README.md](tools/README.md) | napi 异步探针 App（定位 libuv 根因的工具） | 需要复现或继续排查 napi 问题时 |

辅助文件：
- `setup-openharmony-kernel.sh` — HDF 内核改造脚本（板级内核 + HDF 一键改造）
- `diag-map-failed.sh` — 布局诊断脚本
- `setup-serial-perm.sh` — 串口权限配置
- `logs/06-*.log` / `logs/07-*.log` — 2026-08-16 启动日志（历史）
- `patches/` — libuv / napi 异步派发修复补丁（最新工作）
- `patches-2in1-dpi/` — PC/2in1 界面 DPI 与窗口裁剪修复
- `research-pc-2in1/` — 上游 PC/2in1 实现调研记录
- `forensic-20261008/` — 2026-10-08 运行时取证数据（DPI/布局/锁屏，**仅文本/json**）

> 📷 屏幕截图（`*.jpeg` / `*.png`）不随仓库发布；抓取命令见 [docs/05](docs/05-6.1进展与当前状态.md) 开头说明。

---

## 三、目录结构

```
openharmony-lubancat/
├── docs/                        # 六篇核心文档（01–05、08）
├── kernel-patches/              # ★ 当前 6.1 阶段的全部源码改动（可 git apply）
│   ├── openharmony-kernel.patch #   内核：binder/access_token/HDF/DTS/defconfig
│   └── openharmony/             #   源码树：13 个仓库的改动
├── board-config/                # ★ 板级+产品配置（源码树里非 git，单独归档）
│   ├── board/                   #   device/board/embedfire/lubancat4
│   └── vendor/                  #   vendor/embedfire/lubancat4
├── tools/                       # 辅助工具（napi 异步探针 App）
├── changes-5.0.3/               # 5.0.3 阶段补丁归档
├── patches/                     # libuv / napi 异步派发补丁
├── patches-2in1-dpi/            # PC/2in1 DPI + WMS 窗口裁剪
├── research-pc-2in1/            # 上游 PC 产品形态调研
├── forensic-20261008/           # 运行时取证数据（文本/json）
├── logs/                        # 启动日志
├── scripts/                     # patch 导出脚本（可复现）
├── sanitize.py                  # 本仓库的脱敏脚本（可复现）
├── SANITIZED.md                 # 脱敏说明
├── LICENSE
└── README.md
```

---

## 三.5、上游仓库地址

本项目的全部工作都基于下面两个上游。**fork / clone 时请对照本表**，
不要从错误的源拉代码（`repo sync` 会按 manifest 自动选择）。

### OpenHarmony 主代码

| 项 | 值 |
|---|---|
| 版本 | **6.1.0.31** / API 23 |
| manifest 分支 | `OpenHarmony-6.1-Release` |
| 官方镜像站 | https://gitee.com/openharmony |
| 实际使用的 remote | https://gitcode.com/openharmony （`default.xml` 的 `remote="gitcode"`） |
| 代码托管 | https://gitcode.com/openharmony |
| 官方文档 | https://gitee.com/openharmony/docs |

初始化源码树（约 100 GB，需预留 300 GB 磁盘）：

```bash
repo init -u https://gitcode.com/openharmony/manifest.git \
          -b OpenHarmony-6.1-Release --no-repo-verify
repo sync -c -j$(nproc)
```

本仓库 patch 涉及的具体上游仓库（每个 patch 头部也标注了各自的基线 commit）：

| 仓库 | 地址 |
|---|---|
| graphic_2d | https://gitcode.com/openharmony/graphic_graphic_2d |
| drivers_peripheral | https://gitcode.com/openharmony/drivers_peripheral |
| window_manager | https://gitcode.com/openharmony/window_window_manager |
| arkui_ace_engine | https://gitcode.com/openharmony/arkui_ace_engine |
| arkui_napi | https://gitcode.com/openharmony/arkui_napi |
| applications_launcher | https://gitcode.com/openharmony/applications_launcher |
| applications_screenlock | https://gitcode.com/openharmony/applications_screenlock |
| screenlock_mgr | https://gitcode.com/openharmony/screenlock_mgr |
| device_board_hihope | https://gitcode.com/openharmony/device_board_hihope |
| vendor_hihope | https://gitcode.com/openharmony/vendor_hihope |
| toybox | https://gitcode.com/openharmony/third_party_toybox |
| build | https://gitcode.com/openharmony/build |
| integration_verification | https://gitcode.com/openharmony/developtools_integration_verification |

### 野火 LubanCat 板卡 SDK

| 项 | 值 |
|---|---|
| 组织 | https://github.com/LubanCat |
| **内核（本项目的内核基线）** | https://github.com/LubanCat/kernel |
| 内核分支 | `lbc-develop-5.10`（对应本项目的 5.10.209） |
| 全部源码仓库 | https://github.com/LubanCat/manifests |
| u-boot | https://github.com/LubanCat/u-boot |
| rkbin（loader/工具） | https://github.com/LubanCat/rkbin |
| Ubuntu rootfs | https://github.com/LubanCat/ubuntu |
| Debian rootfs | https://github.com/LubanCat/debian12 |

拉取板卡 SDK：

```bash
mkdir LubanCat_SDK && cd LubanCat_SDK
repo init -u https://github.com/LubanCat/manifests.git -b lubancat_linux_generic
repo sync -c -j$(nproc)
```

> ⚠️ 内核仓库有两个分支：`lbc-develop-5.10` 与 `lbc-develop-6.1`。
> 本项目用 **5.10**（方案 B 的原厂基线），别拉错。
> 移植专用的 `openharmony-kernel` 工作副本由 `setup-openharmony-kernel.sh`
> 从原厂内核改造而来，改动已全部导出到
> [kernel-patches/openharmony-kernel.patch](kernel-patches/openharmony-kernel.patch)。

---

## 四、关键路径速查（占位符）

脱敏后的路径占位符，使用时替换为你自己的实际路径：

| 占位符 | 含义 |
|---|---|
| `$OH_SRC` | OpenHarmony 源码树根目录 |
| `$LUBANCAT_SDK` | 野火 LubanCat SDK（含原厂内核） |
| `$DEV_HOME` | 开发工作目录 |
| `<FLASH_DIR>` | Windows 侧烧录目录 |
| `<HDC>` | hdc 可执行文件路径 |
| `<RKDEVTOOL>` | RKDevTool 烧录工具 |
| `<SERIALNO>` / `<CPU-SERIAL>` | 已抹除的硬件序列号 |

源码树内部结构：

```
$OH_SRC/
├── device/board/embedfire/lubancat4/   板级目录（BUILD.gn / build_kernel.sh / cfg / loader）
├── vendor/embedfire/lubancat4/         产品配置（config.json / hdf_config / ohos.build）
├── kernel/linux/linux-5.10             OH 内核（v5.0.3，不参与实际编译）
└── out/rk3588/packages/phone/images/   构建产物

$LUBANCAT_SDK/
├── kernel-5.10 / kernel-6.1            原厂内核（勿动）
├── openharmony-kernel/                 ★HDF 专用内核（改这里，git 可回滚）
└── rkbin/                              loader 与工具
```

---

## 五、最快上手命令

```bash
# 串口交互（一次性命令模式）
stty -F /dev/ttyUSB0 1500000 raw -echo

# hdc 连接
HDC="$OH_SRC/prebuilts/ohos-sdk/linux/15/toolchains/hdc"
$HDC start && $HDC tconn 192.168.x.x:36199
$HDC -t 192.168.x.x:36199 shell
```

完整操作见 [docs/04-调试与操作手册.md](docs/04-调试与操作手册.md)。

---

## 五.5、如何在自己的树上复现移植

所有源码改动已导出为可直接 `git apply` 的 patch，集中在
[kernel-patches/](kernel-patches/README.md)。**完整流程如下**，
建议按顺序执行，每一步都带校验。

### 前置：准备两棵源码树

```bash
# A. OpenHarmony 6.1 源码树（见「三.5、上游仓库地址」）
export OH_SRC=/path/to/openharmony-lts

# B. 野火板卡 SDK（只取内核仓库即可）
git clone https://github.com/LubanCat/kernel openharmony-kernel
cd openharmony-kernel
git checkout lbc-develop-5.10          # 必须是 5.10 分支
cd -
export LUBANCAT_SDK=/path/to/LubanCat_SDK

# C. 本仓库（文档 + patch）
git clone https://github.com/aicaibucai/ohos_lubancat4.git
export DOCS=$PWD/ohos_lubancat4
```

> ⚠️ **内核必须 checkout 到 patch 标注的基线 commit**，不能直接用分支 HEAD。
> 上游 `lbc-develop-5.10` 仍在前进，分支 HEAD 已领先基线半年以上，
> 直接 apply 会在 `.version`、`Makefile`、`binder.c` 等处失败。
>
> ```bash
> cd "$LUBANCAT_SDK/openharmony-kernel"
> BASE=$(grep -m1 '^# 基线:' "$DOCS/kernel-patches/openharmony-kernel.patch" | awk '{print $3}')
> echo "基线: $BASE"
> git fetch --depth 1 origin "$BASE" && git checkout FETCH_HEAD
> ```
>
> 已在干净克隆上实测：checkout 到基线后 `git apply --check` 与 `git apply` 均**一次通过**，
> `drivers/accesstokenid/`、`drivers/hdf/`、binder ioctl、`CONFIG_ACCESS_TOKENID=y` 全部落地。

### 步骤 1：应用内核补丁

```bash
cd "$LUBANCAT_SDK/openharmony-kernel"

# 先检查（不落盘），全部 hunk 能匹配才继续
git apply --check "$DOCS/kernel-patches/openharmony-kernel.patch"

# 确认无误后正式应用
git apply "$DOCS/kernel-patches/openharmony-kernel.patch"

# 补上 patch 有意不含的符号链接（指向 OH 源码树的 HDF 头文件）
ln -sfn "$OH_SRC/drivers/hdf_core/framework/include" include/hdf

# 校验
git status --short | head
```

### 步骤 2：应用 OpenHarmony 源码树补丁

```bash
cd "$OH_SRC"

for p in "$DOCS"/kernel-patches/openharmony/*.patch; do
  repo=$(grep -m1 '^# 仓库:' "$p" | sed 's/^# 仓库: //')
  echo ">>> $repo"
  git -C "$repo" apply --check "$p" \
    && git -C "$repo" apply "$p" \
    || echo "!!! 应用失败：$repo（可能是基线 commit 不一致，见 $p 头部）"
done
```

> 每个 patch 头部都写了 `# 上游:` 与 `# 基线:`。
> 如果 `--check` 失败，先 `git -C <repo> fetch origin` 并 checkout 到该基线 commit。

### 步骤 3：按需只应用某一类改动

不必一次全上。例如只修黑屏相关：

```bash
cd "$OH_SRC"
for p in foundation_graphic_graphic_2d drivers_peripheral vendor_hihope; do
  git -C "$(grep -m1 '^# 仓库:' "$DOCS/kernel-patches/openharmony/$p.patch" | sed 's/^# 仓库: //')" \
      apply "$DOCS/kernel-patches/openharmony/$p.patch"
done
```

分组对照表见 [kernel-patches/README.md](kernel-patches/README.md#23-按改动性质分批应用推荐)。

### 步骤 4：编译与刷机

```bash
# 完整构建流程见 docs/04-调试与操作手册.md
# 要点：必须剥掉 IDE 注入的 safe-delete 包装，否则构建会中断
```

所有 patch 均通过 `git apply --check` 验证（14/14）。
完整说明（含按改动性质分批应用、排除清单）见
[kernel-patches/README.md](kernel-patches/README.md)。

---

## 六、核心技术结论（TL;DR）

1. **内核走原厂 5.10.209 + HDF 钩子**（方案 B），不用 OH 的 kernel.patch —— 绕开结构性错配，与 OH 版本无关。
2. **黑屏是四层根因叠加**：dtb 用错 → fstab cmdline 缺 `ohos.required_mount.*` → librga 与内核 rga3 代际不匹配 → UniRender 默认关闭导致 drawable 生成器为空。
3. **异步 napi 不回调的总根因是 libuv 编译宏三方不匹配**（`USE_OHOS_DFX` 开 + `USE_FFRT` 关），一条派发路径被 `return`、另一条被 `#ifdef` 编掉。修法改一行。
4. **PC/2in1 方向的两处硬伤**：`maxFloatingWindowSize_` 默认 1920 × vpr 会裁剪 SystemUI；DPI 原先硬编码，已改为动态化。

---

## 七、许可与声明

- 文档内容：MIT（见 [LICENSE](LICENSE)）
- 涉及 OpenHarmony 上游代码的补丁：遵循其原始许可（Apache 2.0）
- 本仓库**不含**任何厂商闭源二进制文件、密钥、证书
- 硬件序列号等设备指纹已在 [SANITIZED.md](SANITIZED.md) 列明并抹除
