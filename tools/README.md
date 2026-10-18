# 辅助工具（tools/）

存放移植过程中编写、但**不在任何 git 仓库里**的辅助工程与脚本。
这些是定位关键根因的工具，删掉源码树后会一并丢失，故单独归档。

---

## oh-probe-app/ —— napi 异步探针 App

**用途**：在 2026-10-01 ~ 10-08 定位「promise/callback 形态的 napi 异步 API
完成回调不回 JS」这一总缺陷时，用它逐条证伪了多个猜想，最终把根因收敛到
**libuv 编译宏三方不匹配**（`USE_OHOS_DFX` 开 + `USE_FFRT` 关）。

完整推理链见 [docs/05](../docs/05-6.1进展与当前状态.md) §15、§17、§18。

### 探针检查项

| 探针 | 检查内容 |
|---|---|
| `SyncNapi` | 同步 napi 调用是否正常（用于排除「napi 整体坏掉」） |
| `AsyncAfterWorkCallback` | `uv_queue_work` 的 after-work 回调是否触发（**核心判据**） |
| `uvLoopTask` | stage 应用的 uv loop 驱动是否注册（推翻「无人驱动」猜想的关键） |
| `isStage` | 进程模型确认 |
| `Promise` / `Callback` | 两种异步形态分别验证 |

### 构建与部署

```bash
cd oh-probe-app
export DEV_HOME=/path/to/your/dev/dir
export OH_SRC=/path/to/openharmony-lts

# 构建（复用 launcher 的 hvigor 工具链）
bash build-probe.sh

# 签名后推板
bash patch-hap.sh
hdc install probe-app.hap
hdc shell aa start -a EntryAbility -b com.ohos.probe
```

> 脚本里的 `$DEV_HOME`、`$OH_SRC`、`<FLASH_DIR>`、`$NODE_BIN` 为脱敏占位符，
> 使用时替换为你自己的路径。

### 关键经验（踩坑记录）

1. **必须接 HDMI**：2026-10-07 那轮排查时板上没接 HDMI 线，导致探针 3 秒就被判
   前台超时退出、`SyncNapi throw 1400001` —— 这些都是**无显示造成的假象**，
   不是 napi 问题。接上 HDMI 后探针正常存活并打出完整 SUMMARY。
   （docs/05 §20）
2. **探针存活时间要够**：早期把「SUMMARY 四项 false」当主证据，实际是探针已退出。
   判断前先确认进程还在。
3. 本工程不在任何 manifest 里，是独立的 hvigor 工程，
   靠复用 launcher 的 `oh_modules` 与 SDK 工具链编译。

---

## 有意未包含的内容

| 内容 | 理由 |
|---|---|
| `entry/build/` | hvigor 构建缓存（且把绝对路径编进了产物目录名） |
| `.hvigor/`、`oh_modules/`、`node_modules/` | 依赖与构建输出 |
| `*.hap` | 签名后的二进制 |
| `local.properties` | 含绝对路径 |

---

## 许可

本目录下的脚本与工程为移植过程中新增，随本仓库 MIT 许可使用。
其复用的 OpenHarmony SDK / hvigor 工具链遵循上游许可。
