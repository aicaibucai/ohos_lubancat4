# 脱敏说明（SANITIZED.md）

本仓库由内部工作区文档整理而成，上传公开仓库前已做系统化脱敏。
本文记录**改了什么、为什么改、如何复现**，便于你审查与后续维护。

---

## 一、脱敏原则

| 原则 | 说明 |
|---|---|
| 源目录不动 | 脱敏只在副本上进行，原始工作区保持原样 |
| 可复现 | 所有替换规则集中在 `sanitize.py`，任何人可重跑校验 |
| 占位符可读 | 不简单删除，而是替换为语义化占位符，保证文档仍然可操作 |
| 二进制同规则 | 日志等二进制文件同样按字节级规则替换 |

---

## 二、已处理的敏感信息

### 2.1 硬件设备指纹（🔴 高风险）

| 原始值 | 出现位置 | 处理 |
|---|---|---|
| `bb86…`（16 位十六进制 serialno） | `logs/06-*.log`、`logs/07-*.log`（kernel cmdline 的 `androidboot.serialno=`） | → `<SERIALNO>` |
| `8472…`（16 位十六进制 CPU Serial） | 同上（`rockchip-cpuinfo ... Serial:`） | → `<CPU-SERIAL>` |

**为什么要处理**：RK3588S 的 CPU Serial 与 bootloader serialno 是该颗 SoC / 该块板子的**唯一硬件标识**，
可用于唯一识别你的具体设备。虽非口令，但属于设备指纹，公开仓库应抹除。

### 2.2 本地文件系统路径（🟡 中风险）

| 原始值形态 | 占位符 |
|---|---|
| `/home/<user>/<dev>/LubanCat_SDK` | `$LUBANCAT_SDK` |
| `/home/<user>/<dev>/openharmony-lts` | `$OH_SRC` |
| `/home/<user>/<dev>` | `$DEV_HOME` |
| `/home/<user>` | `$HOME` |
| `<dev>/openharmony-lts`（相对路径形式） | `$OH_SRC` |

**为什么要处理**：暴露操作系统用户名与个人目录结构。

### 2.3 Windows 侧路径（🟡 中风险）

| 原始值形态 | 占位符 |
|---|---|
| `D:\<flash>` / `/mnt/d/<flash>` | `<FLASH_DIR>` |
| `D:\<tools>\RKDevTool.exe`（含完整版本号路径） | `<RKDEVTOOL>` |
| `/mnt/d/<IDE目录>/hdc.exe` | `<HDC>` |
| `D:\...\`（省略形式） | `<FLASH_DIR>/...` |

**为什么要处理**：暴露磁盘分区、开发工具安装位置。

### 2.4 内网 IP 地址（🟡 中风险）

| 原始值 | 处理 |
|---|---|
| `192.168.<网段>.<板子IP>` | `192.168.x.100` |
| `192.168.<网段>.<板子IP>` | `192.168.x.160` |
| `192.168.<网段>.<板子IP>` | `192.168.x.200` |
| `192.168.<网段>.1`（网关） | `192.168.x.1` |

**为什么要处理**：虽然 `192.168.x.x` 是私有地址段，但结合端口与设备名可还原你的局域网拓扑。

### 2.5 邮箱（🟢 已确认无泄漏）

`~/.gitconfig` 中的 `user.email` **未出现在任何项目文件中**。
但请注意：`git commit` 时会把它写进 commit metadata 并随 push 公开。
如需避免，请在推送前设置：

```bash
git config user.email "<your-github-noreply-email>"
# GitHub 提供的隐私邮箱格式： <ID>+<username>@users.noreply.github.com
```

---

## 三、已剔除的文件与理由

| 原始文件 | 体积 | 剔除理由 |
|---|---|---|
| `changes-5.0.3/untracked-files/`（857 个文件） | ~13 MB | 经逐一核查，**不含任何 LubanCat 移植源码**。全部是：① 上游仓库自带的未跟踪文件（appspawn.cfg、foo.cpp 占位等）；② 内核构建垃圾（142 个 `.cmd`、`.o.d`、15 个 `.gch` 预编译头、43 个空文件）；③ bzip2 自带的 `manual.pdf`。原 README 自己也标注「third_party 部分不要使用」 |
| `changes-5.0.3/repo-all.patch` | 7.5 MB | 拆分为 `repo-all-porting.patch`。原文件 283680 行中 **280149 行（98.8%）是 `third_party/node` 的二进制 diff**（`deps/brotli` 等上游构建产物），与移植无关。保留部分为 3387 行 / 49 个 project / 252 处 diff |
| `changes-5.0.3/repo-status.txt` | 868 KB | `repo status` 的原始输出，信息已被 `repo-all-porting.patch` + README 覆盖 |
| `changes-5.0.3/untracked-list.txt` | 774 KB | 12756 行未跟踪文件清单，其中 **9242 行是 grpc 解压源码**，无参考价值 |
| `changes-5.0.3/applications_standard_launcher.patch` | 0 B | 空文件 |
| `changes-5.0.3/device_board_embedfire.patch` | 0 B | 空文件 |
| `changes-5.0.3/repo-status-porcelain.txt` | 240 B | 只是 `repo status --porcelain` 命令不存在的报错记录 |
| `patches-2in1-dpi/*.orig` | ~12 KB | 补丁的原始版本，`.diff` 已包含同样信息 |
| `patches-2in1-dpi/window_manager_config.xml.orig-wmfix` | 5 KB | 同上 |
| `forensic-20261008/desktop_unlocked_172418B.jpeg` | 172 KB | 与 `desktop_unlocked.jpeg` 字节完全相同（同尺寸副本） |
| `forensic-20261008/lockscreen_124111B.jpeg` | 124 KB | 与 `lockscreen.jpeg` 字节完全相同（同尺寸副本） |
| `changes-5.0.3/repo-diff.err` | 124 B | 仅 repo 版本升级提示，零信息量 |
| `forensic-20261008/diag5_full2.txt`、`diag5_probe1.txt` | 各 56 KB | 与 `diag5_full1.txt` 是同一次崩溃寄存器 dump 的重复版本（三者均 1048 行，仅起始偏移不同），保留 full1 |
| `forensic-20261008/diag.txt` | 64 B | uboot `printenv devnum` 输出，与移植无关 |
| `forensic-20261008/` 下 15 个中间输出 | ~56 KB | `diag2/3/4/5_out`、`diag5_screen_dump`、`diag_out`、`diag10_out`、`dyn_dpi`、`geo`、`hgm`、`icon_final`、`icon_path`、`icon_size_out`、`iconformula`、`two`。**结论已全部写入 `docs/05` 正文**（§24.1–24.3 的几何/公式/刷新率分析、§24.6 的常量三方对照），raw 文件只是取证来源。保留 11 个被文档引用的核心证据 |
| **全部图片**（10 个 `*.jpeg` / `*.png`，共 ~1.7 MB） | 1.7 MB | 用户要求不上传图片。已在 `docs/05` 开头统一说明，正文引用改为删除线标注 |

### 3.1 源码树改动导出时的排除项

`kernel-patches/` 由 OpenHarmony 源码树（500 个 git 仓库）与内核仓库的
`git diff` 导出，导出时排除了以下**非移植内容**：

| 排除内容 | 规模 | 理由 |
|---|---|---|
| `third_party/node` 二进制 diff | 280149 行 | `deps/brotli` 等上游构建产物变动，占原始 `repo diff` 的 98.8% |
| `third_party/sane-airscan`、`cups-filters` | 26 文件 | 上游 OH 官方 `OH_AIRSCAN` 适配补丁，`repo sync` 自动应用 |
| `third_party/{iptables,pcre2,freetype,icu,libjpeg-turbo,wpa_supplicant,bounds_checking_function,libnl}` | 25 文件 | 上游 OH 适配 |
| `test/xts/acts` | 12 文件 | XTS 测试固件 |
| `applications/standard/{user_certificate_manager,app_samples,hap}` | 8 文件 | 测试样例、预编译 HAP 二进制（`SystemUI-ScreenLock.hap` 1.6 MB） |
| `device/soc/rockchip` 的 `resource_tool` | 1 文件 | RK 二进制工具被重新编译，非源码改动 |
| `arkcompiler/ets_frontend` 的 `package-lock.json` | 3 文件 | `npm install` 的副作用 |
| `local.properties` | 1 文件 | **含绝对路径** `$OH_SRC/prebuilts/ohos-sdk/linux`，作为敏感信息剔除 |
| `hvigorw` | 多处 | 仅文件权限位变化，无内容差异 |
| `*.cmd` / `*.o` / `*.o.d` / `*.a` / `*.order` / `*.gch` | 1900+ 文件 | 内核与 HDF 构建垃圾 |
| `*.hcb` / `*.rej` / `*.bak` | 多处 | HDF 编译产物、补丁拒绝记录、备份文件 |
| `arch/arm64/boot/Image.bak` | 40 MB | 内核编译产物备份 |
| `include/hdf` 符号链接 | 1 项 | 指向 OH 源码树的绝对路径，改为在 `kernel-patches/README.md` 说明手工创建方法 |

导出的 14 个 patch 全部通过 `git apply --check` 验证。

---

## 四、已核查无敏感内容的文件

| 文件 | 核查结论 |
|---|---|
| ~~`Launcher_3745.db`~~ | 已核查无个人数据（仅系统应用名与网格配置），但作为 SQLite 二进制**未随仓库发布** |
| `patches/*.patch` | 纯代码 diff，无路径泄漏 |
| `kernel-patches/**/*.patch` | 纯代码 diff，已全量扫描：无家目录路径、无 `D:\`、无内网 IP、无邮箱 |
| `research-pc-2in1/*.txt` | 上游仓库调研记录（gitee API 查询结果），无敏感信息 |
| `forensic-20261008/diag*.txt` | 运行时取证输出，路径已脱敏 |

---

## 五、如何复现 / 校验

```bash
# 重新生成干净副本（不会动你的原始目录）
python3 sanitize.py <你的原始工作区> /tmp/verify-clean

# 全量复扫（把 PATTERN_* 换成 sanitize.py 里对应的原始字面量）
cd /tmp/verify-clean
grep -rn "PATTERN_SERIALNO" .   && echo "❌ 仍有序列号"     || echo "✅ 无序列号"
grep -rn "PATTERN_HOMEDIR" .    && echo "❌ 仍有家目录路径" || echo "✅ 无家目录路径"
grep -rn 'D:\\\|/mnt/d/' .      && echo "❌ 仍有 Windows 路径" || echo "✅ 无 Windows 路径"
grep -rn "192\.168\.123\." .    && echo "❌ 仍有原始内网 IP" || echo "✅ 无原始内网 IP"
```

`grep` 无命中时退出码为 1，`&&` 分支不执行，因此上述脚本在干净状态下只会打印 ✅。

---

## 六、替换规则完整清单

规则按顺序应用（长串优先，避免被短规则二次命中）。原始字面量请对照 `sanitize.py`：

```python
REPLACEMENTS = [
    # 1) 硬件指纹（最高优先级，先替换长串）
    ("<16位序列号字面量>", "<SERIALNO>"),
    ("<16位CPU序列号字面量>", "<CPU-SERIAL>"),

    # 2) 源码树路径（长的在前）
    ("/home/<user>/<dev>/LubanCat_SDK", "$LUBANCAT_SDK"),
    ("/home/<user>/<dev>/openharmony-lts", "$OH_SRC"),
    ("/home/<user>/<dev>", "$DEV_HOME"),
    ("/home/<user>", "$HOME"),

    # 3) 相对路径形式（05 文档里的 markdown 链接）
    ("../../<dev>/openharmony-lts/", "../../$OH_SRC/"),
    ("../../<dev>/", "../../$DEV_HOME/"),
    ("<dev>/openharmony-lts", "$OH_SRC"),
    ("<dev>/LubanCat_SDK", "$LUBANCAT_SDK"),
    ("<dev>/OH6.1_BUILD_STATUS.md", "$DEV_HOME/OH6.1_BUILD_STATUS.md"),
    ("<dev>", "$DEV_HOME"),

    # 4) Windows 路径
    (r"D:\<flash目录名>", "<FLASH_DIR>"),
    (r"D:\<工具目录>\RKDevTool_Release_v<版本号>\...\RKDevTool.exe", "<RKDEVTOOL>"),
    (r"/mnt/d/<IDE目录>/hdc.exe", "<HDC>"),
    (r"/mnt/d/<flash目录名>", "<FLASH_DIR>"),
    (r'D:\...\\', "<FLASH_DIR>/..."),
    (r"/mnt/d/", "<WIN_DRIVE>/"),

    # 5) 内网 IP
    ("192.168.<网段>.<板子IP>", "192.168.x.100"),
    ("192.168.<网段>.<板子IP>", "192.168.x.160"),
    ("192.168.<网段>.<板子IP>", "192.168.x.200"),
    ("192.168.<网段>.1", "192.168.x.1"),   # 网关

    # 6) git 身份（防御性）
    ("<个人邮箱>", "<EMAIL>"),
]
```

---

## 七、仍需你注意的事项

1. **commit author 邮箱**：`git push` 会把 `~/.gitconfig` 的 `user.email` 写入提交历史并公开。
   推送前建议改用 GitHub noreply 邮箱（见 §2.5）。
2. **截图中的可见信息**：截图经人工核查无隐私内容，但如果你在后续添加新截图，注意检查
   状态栏时间、通知内容、账号信息。
3. **本仓库不含源码树**：仅知识归档。上传后如需附带可编译代码，
   注意 OpenHarmony 上游代码遵循 Apache 2.0，需保留版权头。
4. **`forensic-20261008/` 的体积**：约 1.1 MB 的取证数据（json/txt/截图），
   如果你觉得过于详细，可只保留 README 中引用的那几个文件。

---

## 八、脱敏前后对比

| 指标 | 脱敏前 | 脱敏后 |
|---|---|---|
| 文件数 | 1910 | 75 |
| 总体积 | ~47 MB | ~3.9 MB |
| 硬件序列号 | 20 处 | 0 |
| 家目录路径 | ~50 处 | 0 |
| Windows 路径 | ~35 处 | 0 |
| 原始内网 IP | ~20 处 | 0 |
| 空文件 / 构建垃圾 | 216 个 | 0 |
| 源码树 git 仓库改动 | 500 个仓库 / ~1900 个噪音文件 | 14 个 patch（全部通过 `git apply --check`） |
