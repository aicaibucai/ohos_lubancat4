# OpenHarmony 移植 LubanCat4（RK3588S）— 项目导航

> **目标板卡**：野火 LubanCat4（瑞芯微 **RK3588S**，16 GB LPDDR4X）
> **目标系统**：OpenHarmony 6.1（`6.1.0.31` / API 23），从 5.0.3 迁移而来
>
> 本仓库是**移植过程的知识归档**（排错记录 + 补丁 + 日志 + 取证数据），
> 不是可编译的源码树。源码树涉及 OpenHarmony 与厂商 SDK 的多个 git 仓库，体积数百 GB。
>
> 🔒 本仓库已脱敏，敏感信息处理方式见 [SANITIZED.md](./SANITIZED.md)。

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

辅助文件：
- `setup-openharmony-kernel.sh` — HDF 内核改造脚本（板级内核 + HDF 一键改造）
- `diag-map-failed.sh` — 布局诊断脚本
- `setup-serial-perm.sh` — 串口权限配置
- `logs/06-*.log` / `logs/07-*.log` — 2026-08-16 启动日志（历史）
- `patches/` — libuv / napi 异步派发修复补丁（最新工作）
- `patches-2in1-dpi/` — PC/2in1 界面 DPI 与窗口裁剪修复
- `research-pc-2in1/` — 上游 PC/2in1 实现调研记录
- `forensic-20261008/` — 2026-10-08 运行时取证数据（DPI/布局/锁屏）
- `screenshots/` — 关键节点截图

---

## 三、目录结构

```
openharmony-lubancat/
├── docs/                        # 六篇核心文档（01–05、08）
├── changes-5.0.3/               # 5.0.3 阶段补丁归档
├── patches/                     # libuv / napi 异步派发补丁
├── patches-2in1-dpi/            # PC/2in1 DPI + WMS 窗口裁剪
├── research-pc-2in1/            # 上游 PC 产品形态调研
├── forensic-20261008/           # 运行时取证数据
├── logs/                        # 启动日志
├── screenshots/                 # 截图
├── sanitize.py                  # 本仓库的脱敏脚本（可复现）
├── SANITIZED.md                 # 脱敏说明
├── LICENSE
└── README.md
```

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
