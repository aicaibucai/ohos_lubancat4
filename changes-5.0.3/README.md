# 5.0.3 移植变动备份 (2026-09-06)

本目录保存了 `openharmony-lts` (OpenHarmony 5.0.3, RK3588S LubanCat4) 全部**未提交**的移植改动，
用于升级到 6.1 LTS 前的安全归档。

## 备份内容

| 文件 | 说明 |
|---|---|
| `repo-all.patch` (7.5M) | **核心**。全局 `repo diff` 输出，包含所有仓库已跟踪文件的修改（早期 200+ 处移植补丁 + 本期 toybox/dmsfwk 等修改）。283680 行。 |
| `third_party_toybox.patch` | toybox config.h / globals.h / BUILD.gn（新增 tr/diff/netcat/route 命令） |
| `third_party_openssl.patch` | openssl 生成脚本幂等跳过（避免每次 gn gen 删 1774 文件） |
| `third_party_abseil-cpp.patch` | abseil install.sh 幂等跳过 |
| `third_party_glib.patch` | glib install.sh 幂等跳过 |
| `third_party_re2.patch` | re2 install.sh 幂等跳过 |
| `third_party_libnl.patch` | libnl install.sh 幂等跳过 |
| `third_party_grpc.patch` | grpc install.sh 幂等跳过 |
| `foundation_ability_dmsfwk.patch` | 删除 distributedschedsvr 重复的 distributed_bm_storage.cpp 源条目 |
| `lubancat-init.sh` | 新增的板级启动脚本（固化 IP/网关 + hdc TCP） |
| `untracked-files/` | 857 个真实未跟踪新增文件（按仓库结构），含 HDF 驱动适配、foundation 构建修改、arkcompiler foo.cpp 占位等。**不含** third_party 解压源码与 out/ 构建产物。 |
| `repo-status.txt` | 完整 `repo status` 输出（含所有变动仓库与文件状态） |
| `untracked-list.txt` | 过滤后的未跟踪文件清单 |

> 注：`untracked-files/third_party/` 目录可能为旧复制残留（第三方库解压源码），恢复时**不要**使用。

## 恢复方法

### 1. 已跟踪文件修改（repo-all.patch）
在 `openharmony-lts` 仓库根目录执行：
```bash
cd $OH_SRC
repo apply $HOME/work/lubancat4-openharmony-porting/changes-5.0.3/repo-all.patch
# 若部分 hunk 失败，可逐仓库： git -C <repo> apply <对应.patch>
```

### 2. 未跟踪新增文件（untracked-files/）
```bash
cp -rn $HOME/work/lubancat4-openharmony-porting/changes-5.0.3/untracked-files/* \
      $OH_SRC/
```
（`-n` 不覆盖已有文件，避免误写第三方库。）

### 3. 板级脚本
`lubancat-init.sh` 已包含在 `untracked-files/device/board/embedfire/lubancat4/cfg/` 中，
或单独文件 `lubancat-init.sh`。

## 已知副作用（升级前注意）

- dayu210(rich 基底) GN 验证曾覆盖 `out/rk3588/build.ninja` 为 dayu210 配置。
  lubancat4 升级/重建时重新 `hb build --build-only-gn -p lubancat4` 即可恢复。
- 本备份**不含**内核改动（HDF 补丁在 `LubanCat_SDK/openharmony-kernel`，独立仓库）。

## 升级 6.1 LTS 建议

- 03 文档记录：v6.1 曾因 **prebuilt-sdk 机制断裂**放弃（ace_ets2bundle / rust_libc / ohos-sdk tracingChannel 报错）；
  且在 v6.1 上编 dayu210 失败。
- 建议在**新目录**拉 6.1 LTS（保留本 5.0.3 工作区与备份），避免 `repo sync` 覆盖未提交改动。
- 移植到 6.1 时：内核 HDF 补丁需重新适配 6.1 内核；产品配置(lubancat4/vendor+device)需对照 6.1 的 dayu210 重做。
