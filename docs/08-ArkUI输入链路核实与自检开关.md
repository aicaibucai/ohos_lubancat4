# 08 - ArkUI 输入链路：所有权 / 线程契约核实（2026-09-30 复核，含待验证实验）

> **来源**：本文源自"当时"（v5.0.3 阶段）的一次聊天分析（`SetPostPointerEvent` 是否 double free、
> `mouseEvents_` 无锁是否是主线缺陷、`ACE_DCHECK` 在 release 是否等于没有守卫）。
> 2026-09-30 在**当前 6.1 树**上逐条回代码核实，结果如下：
>
> - 原分析的**大方向成立** ✔（`SetPostPointerEvent` 自洽、无锁属设计前提、PC/2in1 确实是压测场景）；
> - **一处结论在当前树上已不成立** ⚠️：release 版**有**守卫，只是被两个系统参数"门控"着（§三）；
> - 本次核实**新发现一处真实缺陷**（§二）与**两个更对口的自检开关**（§四），
>   并把原计划的"重编一个 debug ACE"换成**零编译的运行时开关**（§五）。
>
> **2026-09-30 更新**：§三 的**调试开关实验**仍未执行（板子未接串口，但 HDC 通道可用）；
> 而"**鼠标一动就整机重启**"这一现象**已实测复现**并取到崩溃取证 → 见 **§1.3**；上游对照见 **§1.4**。
>
> ---
>
> ## ★★ 2026-10-01 深夜复核实测：**A / B 两类假设双双被证伪，真凶在显示合成层**
>
> §三 的开关实验**已在板上执行**（`persist.ace.debug.enabled=1` + `flags=37` = bit0 线程契约 + bit2 悬垂引用
> + bit5 使用中被销毁），并在**真实复现**（移动鼠标 → 内核 `use tmds mode` 爆发 → 丢帧）中采样：
> **三个开关一次都没有触发** ✗。故：
>
> - ❌ **A 类**（`mouseEvents_` 的 UI 线程契约被破坏）——**不成立**；
> - ❌ **B 类**（`MouseEvent` 持有的 MMI 事件生命周期失效）——**不成立**；
> - ✅ §1.3 那份崩溃栈（`~PointerEvent` → `free()`）**是真的**，但属 **09-20 那次会话**的独立事件：
>   该 faultlog 时间戳 `2026-09-20 01:48:23.780`、`Process life time: 129s`（而 10-01 的新重启
>   **没有新增任何 faultlog**）。且 2026-10-01 观察到的"鼠标→重启"经用户确认是**手动断电**所致，
>   **不能作为该崩溃的证据**。
>
> **真正的鼠标相关缺陷（已定位并修复，详见 05 文档 §十）**：
> `drivers/peripheral/display/composer/vdi_base/src/hdi_drm_composition.cpp` 的 `Apply()` **每帧都重设**
> connector `CRTC_ID` 与 CRTC `ACTIVE` → 内核把每一帧都当作 modeset →
> `dw_hdmi_rockchip_encoder_atomic_check()`（`dw_hdmi-rockchip.c:2368`）→ `hdmi_select_link_config()`
> → 实测内核 `use tmds mode` **41 次/秒**（静止期也有 ~7.5 次/秒），并伴随
> `drmModeAtomicCommit` **EBUSY(-16) 36 次/秒** → 丢帧。
> 修复后（去掉每帧 modeset 属性 + EBUSY 重试）：**tmds 41/秒 → 0；EBUSY 36/秒 → 0；用户确认"滑动不闪烁了"** ✓
>
> ⚠️ **新现象（2026-10-01 用户实测，待查）**：**移动鼠标后出现过一次"全屏黑、只剩鼠标光标"，
> 数十秒后自行恢复正常**（与 5.0.3 时代"只有移动鼠标才刷新画面"同族，但表现更重）。
> 已记入 05 文档 §10.6 待办。

---

## 一、原分析三条结论的逐条核实

| 原分析 | 核实结果 | 证据（当前 6.1 树） |
|---|---|---|
| "`SetPostPointerEvent` 是必然的 double free" ✗ | **不成立** ✔（原分析已自行更正，此处确认） | `adapter/ohos/entrance/mmi_event_convertor.cpp:342-368` |
| "`mouseEvents_` 无锁是主线缺陷" ✗ | **表述过重** ✔（同意更正为"设计前提下的合理选择"） | `pipeline_context.h:1587`，访问点均在 `CHECK_RUN_ON(UI)` 函数内经手 |
| "release 里 `ACE_DCHECK` 被编译掉 → 没有守卫" ✗ | **在当前 6.1 树上不成立** ⚠️（见 §三） | `frameworks/core/common/thread_checker.h:22-32` |

### 1.1 所有权契约（确认自洽）

```cpp
// adapter/ohos/entrance/mmi_event_convertor.cpp
342: void SetClonedPointerEvent(const MMI::PointerEvent* pointerEvent, ArkUITouchEvent* arkUITouchEventCloned)
345:     MMI::PointerEvent* clonedEvent = new MMI::PointerEvent(*pointerEvent);   // 克隆①
346:     arkUITouchEventCloned->rawPointerEvent = clonedEvent;                    // → raw 槽
350: void SetPostPointerEvent(TouchEvent& touchEvent, ArkUITouchEvent* arkUITouchEventCloned)
352:     MMI::PointerEvent* pointerEvent = reinterpret_cast<...>(arkUITouchEventCloned->rawPointerEvent);
354:     MMI::PointerEvent* clonedEvent = new MMI::PointerEvent(*pointerEvent);   // 克隆②
355:     arkUITouchEventCloned->rawPointerEvent = clonedEvent;                    // raw 槽换成克隆②
357:     std::shared_ptr<const MMI::PointerEvent> pointer(pointerEvent);          // 克隆① 交给 shared_ptr
358:     touchEvent.SetPointerEvent(pointer);
361: void DestroyRawPointerEvent(ArkUITouchEvent* arkUITouchEvent)
365:     delete pointerEvent;            // 释放克隆②
```

**两条所有权各走一路**：克隆① → `shared_ptr`（随 `TouchEvent` 走）；克隆② → raw 槽（由
`DestroyRawPointerEvent` 释放）。**不重不漏** ✔。它只是**潜在危险**（若 raw 槽被塞进非堆指针就会崩，
上游自检项正是禁这种写法）。

调用侧印证：`frameworks/core/interfaces/native/node/node_common_modifier.cpp:9190` 调 `SetPostPointerEvent`、
`:9291-9292` 调 `SetClonedPointerEvent`、`:9266-9272` 的 `DestroyTouchEvent` 里先
`DestroyRawPointerEvent` 再 `delete arkUITouchEvent`。

### 1.2 线程契约（确认"都在 UI 线程"是设计前提）

- `pipeline_context.h:1587`：`std::map<RefPtr<FrameNode>, std::list<MouseEvent>> mouseEvents_;` —— **无互斥**。
- `pipeline_context.cpp` 全文有 **58 处 `CHECK_RUN_ON`**；所有碰 `mouseEvents_` 的函数都在其中：
  `OnMouseEvent`(`:4498`)、`FlushMouseEvent`(`:4669`)、`FlushMouseEventVoluntarily`(`:1051`)、
  `OnMouseMoveEventForAxisEvent`(`:4987`)、`FlushMouseEventForHover`(`:7234`) 均带 `CHECK_RUN_ON(UI)`。
- 唯一"看起来可疑"的 `FlushMouseEventInVsync()`(`:7296`) 自身不带断言，但它唯一调用点在
  `FlushVsync()` 内（`:997`），而 `FlushVsync()` 第一行就是 `CHECK_RUN_ON(UI)`（`:841`）→ **仍受守护** ✔。

→ 所以"无锁"是**契约成立时的合理选择**，不是 bug ✗；但**契约一旦被破坏就是静默数据竞争** ✔（§三）。

### 1.3 ★ 现场复现：鼠标一动就整机重启（2026-09-30 实测，HDC 在线）

> 这是目前最硬的一手证据：**现象可稳定复现 + 有崩溃栈**。用它来锚定 §三 的实验。

**复现步骤与结果**（HDC，板子 `LubanCat4-0001`）：

| 时刻 | 动作 | 观测 |
|---|---|---|
| T+0 | 记录基线 | `uptime` = **`up 38 min`**；`pidof com.ohos.systemui` = 1697；faultlog **28 份** |
| T+0 | `hilog -r` 清缓冲，随后每 8 秒采样一次 | — |
| **T+8s** | **手移动鼠标** | `hdc` **立即掉线**（`Failed to communicate with daemon`）|
| T+70s | 重连 | `uptime` = **`up 0 min`** ✗ → **整机重启**；`pidof` = 604 / 620 / 1707（新的一轮）|

- **判据**：`uptime` 归零 ✓ + 采样在第一窗口（8 秒）内即断开 ✓ → 与"移动鼠标"强相关。
- **对照（排除误判）**：重启前设备已**稳定运行 38 分钟** ✓，说明不是"置 `bootevent.*` 导致的延迟重启"
  （那条路径已单独记录在 05 文档）；用 `uitest uiInput`（合成触摸）做过**十余次**上滑/拖拽
  （含解锁成功那次 ✓）**从未触发重启** ✗ → 触发条件是**鼠标事件路径**，不是"有输入就崩" ✓。

**两份崩溃报告**（`/data/log/faultlog/faultlogger/`）：

| 报告 | 进程 | 结论 |
|---|---|---|
| `cppcrash-com.ohos.systemui-10008-20260920014823780.log` | `com.ohos.systemui` | **鼠标路径**，与本案直接相关（栈见下）|
| `cppcrash-composer_host-3036-19700101080410909.log` / `…080411267.log`（相隔 0.3s）| `composer_host` | `HdiDeviceInterface::DiscoveryDevice()` ← `drm file:rockchip open failed` → NULL 解引用；`Process life time: 1s`。**这是独立的 DRM 竞态崩溃**（05 文档"开机偶发黑屏"那一族），不是鼠标问题 |

**SystemUI 的崩溃栈（关键）**：

```
Reason: Signal:SIGSEGV(SEGV_MAPERR)@0x0  probably caused by NULL pointer dereference
#00 ld-musl-aarch64.so.1      get_meta                                  ← free() 内部取堆块元数据
#01 ld-musl-aarch64.so.1      __libc_free
#02 libmmi-client.z.so        MMI::PointerEvent::~PointerEvent()+116
#03 libmmi-client.z.so        MMI::PointerEvent::~PointerEvent()+48
#04 libace_compatible.z.so    std::shared_ptr<unsigned char[]>::~shared_ptr()
#05 libace_compatible.z.so    std::allocator<OHOS::Ace::MouseEvent>::destroy(...)
#10 libace_compatible.z.so    PipelineContext::OnFlushMouseEvent(FrameNode, std::list<MouseEvent> const&, TouchRestrict&)
#12 libace_compatible.z.so    PipelineContext::FlushMouseEvent()
#13 libace_compatible.z.so    PipelineContext::FlushMouseEventInVsync()
```

**读法（重要）**：崩点正是 **`FlushMouseEventInVsync` → 逐个析构队列里的 `MouseEvent`** ✓ ——
也就是说它在 §1.2 说的那条"无锁队列"路径上 ✗；被 `free()` 掉的是 `MouseEvent` 持有的
MMI 事件里那块 `shared_ptr<unsigned char[]>`（**事件原始数据**）✗。

形态上只有两种可能，**正好分别对应 §三 / §四 的开关**：
- **A｜容器被并发改坏** ✗（生产者 `mouseEvents_[node].emplace_back` 与消费端 `std::move`/`clear` 重叠）
  → 析构时读到的 `MouseEvent` 是垃圾 → 其 `shared_ptr` 是随机值 → `free(垃圾指针)` ✔ —— 用 **bit0** 抓；
- **B｜事件对象生命周期已失效** ✗（`MouseEvent` 持有的 MMI 事件早已被释放/复用）→ 用 **bit5 / bit2** 抓。

> 附：`mouseEvents_` 的全部访问点（便于加锁/校验时逐处对照）——
> 生产 `pipeline_context.cpp:4541`（在 `OnMouseEvent` 内，带 `CHECK_RUN_ON(UI)`）；
> 读取/擦除 `:4607`、`:4611-4624`；搬空 `:4698`（`std::move`，在 `OnFlushMouseEvent` 内）；
> 清空 `:5412`；`FlushMouseEventInVsync` 的 `:7298-7302`（`size()/empty()/clear()`）。

### 1.4 ★ 上游对照：没有现成补丁可参考（2026-09-30 抓取 gitee master）

| 位置 | 上游 `master` | 本树 6.1 |
|---|---|---|
| `pipeline_context.h` 的 `mouseEvents_` | `std::map<...> mouseEvents_;` **仍无互斥**（全文只有无关的 `navigationMutex_`）| 相同 |
| `mmi_event_convertor.cpp` 的 `SetPostPointerEvent` | **仍用裸指针**：`std::shared_ptr<...> pointer(pointerEvent);`（不是 `clonedEvent`）| 相同 |
| 产品/板卡参考 | 仓库自带产品只有 `system_arm_default.json` / `system_arm64_default.json`，**没有 PC / 2in1 产品** | 板卡目录只有 embedfire / hihope / hisilicon |

- 上游 PR 模板自检项明确写着 **"禁止将外部传入的裸指针在内部直接构造智能指针"** ✔ ——
  即 §1.1 那个写法**违反上游自身规范**，但至今未修（关联 PR !50459「修复capi崩溃问题」，
  2024-12-09 合并、**1 文件 1 commit**；页面未提供 diff，无法据此对照）。
- **结论**：没有可直接抄的补丁 ✗；本修复属**自研正向修复** ✔，且正是"做 PC / 2in1 版必须带上"的那一类改动 ✔。

---

## 二、★ 本次新发现的真实缺陷：`DestroyRawPointerEvent` 把 nullptr 赋给了局部变量

```cpp
361: void DestroyRawPointerEvent(ArkUITouchEvent* arkUITouchEvent)
362: {
363:     MMI::PointerEvent* pointerEvent = reinterpret_cast<MMI::PointerEvent*>(arkUITouchEvent->rawPointerEvent);
364:     if (pointerEvent) {
365:         delete pointerEvent;
366:         pointerEvent = nullptr;        // ★ 只置空了"局部变量"
367:     }                                  //   槽 arkUITouchEvent->rawPointerEvent 仍是悬垂指针
368: }
```

- 第 366 行显然是**想清空槽位**，却写成了给局部变量赋值 → **死代码 + 槽里留悬垂指针**。
- 正常路径（`DestroyTouchEvent` 紧接着 `delete arkUITouchEvent`）不会立刻出事；
  但**同一个 `ArkUITouchEvent` 被复用、或销毁两次**，就会 double free / use-after-free。
- 这正是原分析在找的"潜在危险"这一类；也说明上游对 raw 槽的自检项确有存在价值。
- **主线可提的 issue**：改为 `arkUITouchEvent->rawPointerEvent = nullptr;`。
  本板是否要改由你定（不改也不影响当前启动链路）。

---

## 三、★ 关键更正：release 版**有守卫**，而且**不用重编**就能打开

原分析（基于 v5.0.3）看到的是 `macros.h` 的 `#else ((void)0)`，于是判断"release 完全没有守卫" ✗。
**当前 6.1 树的真实情况**：

```cpp
// frameworks/core/common/thread_checker.h:22-32
#ifdef ACE_DEBUG
#define CHECK_RUN_ON(threadType) ACE_DCHECK(OHOS::Ace::CheckThread(TaskExecutor::TaskType::threadType))
#else
#define CHECK_RUN_ON(threadType)                                                         \
    do {                                                                                 \
        if (ACE_UNLIKELY(OHOS::Ace::SystemProperties::DetectContainerMultiThread() &&    \
                         !OHOS::Ace::CheckThread(TaskExecutor::TaskType::threadType))) { \
            LOGF_ABORT("CheckThread fail: expected [%{public}s]", #threadType);          \
        }                                                                                \
    } while (0)
#endif
```

release 分支**会真的 abort**（`LOGF_ABORT` = `LOGF(...)` + `abort()`，`frameworks/base/log/log_wrapper.h:92-97`），
只是被一个**运行时开关**门控：

```cpp
// frameworks/base/utils/system_properties.h:478-481
static bool DetectContainerMultiThread()
{
    return debugEnabled_ && debugFlags_.bits_.containerMultiThread_;
}
```

两个门都来自**系统参数**（`adapter/ohos/osal/system_properties.cpp`）：

| 参数 | 读取处 | 作用 |
|---|---|---|
| `persist.ace.debug.enabled` = `"1"` | `:262-265` `IsDebugEnabled()` → `debugEnabled_`(`:936`) | 总开关 |
| `persist.ace.debug.flags` = int64 位掩码 | `:291-294` `GetDebugFlags()` → `debugFlags_`(`:938`) | 逐项开关 |

`DebugFlags` 位序（`system_properties.h:71-83`）：

```
bit0 containerMultiThread_   bit1 getHostOnDetach_   bit2 claimDeathObj_
bit3 aceObjTypeCvt_          bit4 jsObjTypeCvt_      bit5 objDestroyInUse_
bit6 useInvalidIter_
```

### 实验命令（**零编译**，几十秒）

```bash
HDC="<HDC>"; D=LubanCat4-0001
"$HDC" -t $D shell "param set persist.ace.debug.enabled 1"
"$HDC" -t $D shell "param set persist.ace.debug.flags 1"     # 1 = bit0 containerMultiThread
# 然后必须重启 ACE 所在进程（或重启整机）
```

> ⚠️ **必须重启进程才生效**：这两个值在 `ReadSystemParametersCallOnce()` 里经
> `std::call_once` **每进程只读一次**（`system_properties.cpp:934-938`），运行中改参数不会即时生效。

判读（与原分析一致，这是铁证式的二选一）：
- **abort + `CheckThread fail: expected [UI]`** → 契约确实被破坏 ✔ → 记下进程名/hilog 上下文，再决定补守卫还是改架构；
- **不 abort** → 契约没被破坏 → 方向转到事件对象的**生命周期**（MMI 侧）。

---

## 四、★ 本次新增收获：两个比"线程契约"更对口的自检开关

`frameworks/base/utils/lifecycle_checkable.cpp`（全文仅 38 行）里还有两个**同样由位掩码门控、
release 可用**的致命自检：

```cpp
24: void LifeCycleCheckable::OnDetectedObjDestroyInUse()
26:     if (SystemProperties::DetectObjDestroyInUse()) {                 // bit5
27:         LOGF_ABORT("this object is still in use, use_count=%{public}d", usingCount_.load());
31: void Referenced::OnDetectedClaimDeathObj(bool isNewOrRecycle)
33:     if (SystemProperties::DetectClaimDeathObj()) {                   // bit2
34:         LOGF_ABORT("invalid claim: refCount=%{public}d, isNewOrRecycle=%{public}d", ...);
```

| 位 | 开关 | 抓什么 | 对本案价值 |
|---|---|---|---|
| bit0 | `containerMultiThread_` | `CHECK_RUN_ON` 违反 | 原分析的目标 |
| **bit5** | `objDestroyInUse_` | **对象仍在使用中被销毁**（`use_count`） | **直接命中"随机 free() 崩溃"那一类** ★ |
| **bit2** | `claimDeathObj_` | **认领正在死亡的对象**（悬垂引用） | 悬垂引用类问题 ★ |
| bit1/bit3/bit4 | getHostOnDetach / aceObjTypeCvt / jsObjTypeCvt | 各自类型/生命周期检查 | 顺带开 |
| bit6 | `useInvalidIter_` | — | 访问器存在（`:508`）但**全树 grep 不到调用点** → 存疑，别当有效开关 ✗ |

**建议一次全开**（bit0–bit5 = 1+2+4+8+16+32 = **63**），把"契约破坏"和"生命周期错误"一起抓：

```bash
"$HDC" -t $D shell "param set persist.ace.debug.enabled 1"
"$HDC" -t $D shell "param set persist.ace.debug.flags 63"
```

---

## 五、原计划需要修正的两点

| 原计划 | 建议改为 | 理由 |
|---|---|---|
| "用 `enable_ace_debug=true` 编一个 ACE" | **先跑 §三 的运行时开关** | 零编译、几十秒见效；`enable_ace_debug` 是"最后手段"，且会连带打开 mem-monitor 等特性、改变产物行为 |
| "当场 abort + 打印调用栈" | 期望值下调：**只打印消息，不含回溯** | `LOGF_ABORT` 只做 `LOGF(...) + abort()`；要调用栈须另配：debug 版 `assert` + core dump 事后 `gdb`，或调试器 attach |

### 备用手段：`ACE_DEBUG` 编译路径（行号与原分析完全一致 ✔）

```gni
# ace_config.gni:19-21
  # ace debug flag, enable debug features: like dcheck, thread-checker, mem-monitor...
  enable_ace_debug = false

# ace_config.gni:212-214
if (enable_ace_debug) {
  ace_common_defines += [ "ACE_DEBUG" ]
}
```

```bash
./build.sh --product-name lubancat4 --ccache --gn-args enable_ace_debug=true
```

> 打开后 `macros.h:45-63` 走 `ACE_DCHECK(expr) = assert(expr)`（并临时 `#undef NDEBUG` 保证 assert 生效）。
> **只适合做取证版**，不要当发布版。

---

## 六、待确认 / 待办

1. **（已明确 ✔）** 该现象属 **6.1 阶段**，且**可稳定复现**：**移动鼠标 → 8 秒内整机重启**（§1.3，`uptime` 归零；
   同样条件下用合成触摸（`uitest uiInput`）十余次均不触发 ✗）。它与 5.0.3 时代的"鼠标移动闪烁"是
   **同一路径（鼠标事件）**在不同阶段的不同表现。**已挂进 05 文档待办表**，进一步取证见第 5 条。
2. **§三实验尚未执行**（**串口不是必需** ✗）：HDC 通道本次实测全程可用（`hdc.exe` + `LubanCat4-0001`），
   而 §三 给的命令本身就是走 HDC 的 → **可直接执行**；串口只在"abort 之后要抓 coredump/回溯"时才用得上。
3. **执行前先明确"一动鼠标就重启一轮"的代价**：按原计划，实验期间先别动鼠标；触发 abort 后从
   hilog / `coredump` 取进程名与上下文。
4. `DestroyRawPointerEvent` 的悬垂槽（§二）是否要向主线提 issue —— 待你决定。
5. **★ "鼠标 → 整机重启"的取证与修复路线（新增，优先级最高）**：
   a) 先执行 §三（`persist.ace.debug.enabled=1` + `persist.ace.debug.flags=63`）→ 用 **bit0** 判 A 类
      （线程契约被破坏），用 **bit5 / bit2** 判 B 类（事件对象生命周期失效）——两类对应完全不同的修法；
   b) A 类 → 给 `mouseEvents_` 补守卫，并建议把该断言改成 **release 也生效**（现在的门控等于"默认没有守卫"）；
   c) B 类 → 改成"**入队只带纯数据、不跨线程持有 MMI 事件对象**"的形态（对 PC / 2in1 更正确）；
   d) **不刷机即可验证**：`libace_compatible.z.so` 在 `/system/lib64/platformsdk/`，板子 `/system`
      已确认可 `mount -o remount,rw /` 后直接替换（09-29 的锁屏 HAP 就是这么验的 ✔）；
   e) 实验期间**先别动鼠标**（一动就重启一轮），用 `uitest` 注入代替交互。

---

## 七、本次核实的信息来源（全部为当前 6.1 树逐行核对）

| 文件 | 行号 | 内容 |
|---|---|---|
| `adapter/ohos/entrance/mmi_event_convertor.cpp` | 342-368 | 克隆/移交/释放三函数（§1.1、§二） |
| `frameworks/core/interfaces/native/node/node_common_modifier.cpp` | 9190, 9266-9272, 9291-9292 | 调用侧与 `DestroyTouchEvent` |
| `frameworks/core/pipeline_ng/pipeline_context.h` | 1587 | `mouseEvents_` 声明（无互斥） |
| `frameworks/core/pipeline_ng/pipeline_context.cpp` | 839-841, 997, 1051, 4498, 4669, 4987, 7234, 7296 | `FlushVsync`/`CHECK_RUN_ON(UI)`/`FlushMouseEventInVsync` |
| `frameworks/core/pipeline/pipeline_base.cpp` | 57-67, 84-94 | vsync 回调注册 |
| `frameworks/core/common/thread_checker.h` | 22-32 | ★ release 守卫（§三） |
| `frameworks/base/log/log_wrapper.h` | 92-97 | `LOGF_ABORT` 定义 |
| `interfaces/inner_api/ace_kit/include/ui/base/macros.h` | 45-63 | `ACE_DCHECK` 的 debug/release 分支 |
| `frameworks/base/utils/system_properties.h` | 71-83, 478-510 | `DebugFlags` 位序 + 各 `Detect*` 访问器 |
| `adapter/ohos/osal/system_properties.cpp` | 262-265, 291-294, 934-938 | 参数读取与 `call_once` |
| `frameworks/base/utils/lifecycle_checkable.cpp` | 24-36 | ★ 两个致命自检（§四） |
| `ace_config.gni` | 19-21, 212-214 | `enable_ace_debug` |
| `frameworks/core/event/mouse_event.h` | 41-67, 316-363 | `MouseEvent` 结构（`pointerEvent` / 递归 `history` / `mockFlushEvent`）——§1.2、§1.3 |
| `adapter/ohos/entrance/ace_container.cpp` | 1327-1360 | 鼠标回调：`[context, event, ...]` **按值捕获**后 `PostTask` 到 UI 线程（跨线程持有事件）——§1.2、§1.3 |
| `frameworks/core/pipeline_ng/pipeline_context.cpp` | 4541, 4607-4624, 4698, 5412, 7298-7302 | `mouseEvents_` 全部访问点 ——§1.3 |
| `/data/log/faultlog/faultlogger/cppcrash-com.ohos.systemui-10008-20260920014823780.log` | 全文 | ★ **鼠标路径崩溃栈**（§1.3）|
| `/data/log/faultlog/faultlogger/cppcrash-composer_host-3036-19700101080410909.log`、`…080411267.log` | 全文 | composer 的 DRM 竞态崩溃（**独立问题**，= 05 §三"开机偶发黑屏"族）——§1.3 |
| 上游 `arkui_ace_engine` master（gitee，2026-09-30 抓取） | `pipeline_context.h`、`mmi_event_convertor.cpp` | 两处**至今未修** ——§1.4 |
| 上游 PR !50459「修复capi崩溃问题」+ PR 模板自检项 | 页面 | 同区域修复（1 文件 1 commit，无 diff）；模板明确禁止"裸指针建智能指针" ——§1.4 |
