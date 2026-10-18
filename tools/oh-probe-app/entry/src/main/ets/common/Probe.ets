import hilog from '@ohos.hilog';
import bundleManager from '@ohos.bundle.bundleManager';
import preferences from '@ohos.data.preferences';
import relationalStore from '@ohos.data.relationalStore';
import display from '@ohos.display';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';

const DOMAIN: number = 0x0000;
const TAG: string = 'ProbeApp';
const BUNDLE: string = 'com.lubancat.probe';

class ProbeState {
  microtask: boolean = false;
  timer: boolean = false;
  syncNapi: boolean = false;
  napiPromise: boolean = false;
  napiCallback: boolean = false;
  preferencesPromise: boolean = false;
  rdbPromise: boolean = false;

  summary(): string {
    return 'microtask=' + this.microtask + ' timer=' + this.timer + ' syncNapi=' + this.syncNapi +
      ' napiPromise=' + this.napiPromise + ' napiCallback=' + this.napiCallback +
      ' preferencesPromise=' + this.preferencesPromise + ' rdbPromise=' + this.rdbPromise;
  }
}

/**
 * 四类形态一次性探测，用来判断"卡在哪一层"：
 *   1. 纯 JS 微任务 / 定时器      -> JS 事件循环是否活着
 *   2. 同步 napi                  -> napi 绑定本身是否可用
 *   3. napi promise 形态          -> 异步完成回调是否回到 JS（Promise 路径）
 *   4. napi callback 形态         -> 异步完成回调是否回到 JS（callback 路径）
 *   5. preferences / RDB promise  -> 其它 napi 模块是否同样不回
 */
export function runProbe(ctx: common.Context, stage: string): void {
  const st = new ProbeState();
  hilog.info(DOMAIN, TAG, '=== probe begin [%{public}s] ===', stage);

  Promise.resolve().then(() => {
    st.microtask = true;
    hilog.info(DOMAIN, TAG, '[%{public}s] JsMicrotask fired', stage);
  });

  setTimeout(() => {
    st.timer = true;
    hilog.info(DOMAIN, TAG, '[%{public}s] JsTimer fired', stage);
  }, 1000);

  try {
    const d = display.getDefaultDisplaySync();
    st.syncNapi = true;
    hilog.info(DOMAIN, TAG, '[%{public}s] SyncNapi ok %{public}dx%{public}d', stage, d.width, d.height);
  } catch (e) {
    hilog.error(DOMAIN, TAG, '[%{public}s] SyncNapi throw %{public}s', stage, JSON.stringify(e));
  }

  try {
    bundleManager.getBundleInfo(BUNDLE, 0).then((info: bundleManager.BundleInfo) => {
      st.napiPromise = true;
      hilog.info(DOMAIN, TAG, '[%{public}s] AsyncNapiPromise resolved, %{public}s', stage, info.name);
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, '[%{public}s] AsyncNapiPromise rejected, %{public}s', stage, JSON.stringify(err));
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, '[%{public}s] AsyncNapiPromise throw %{public}s', stage, JSON.stringify(e));
  }

  try {
    bundleManager.getBundleInfo(BUNDLE, 0, (err: BusinessError, info: bundleManager.BundleInfo) => {
      st.napiCallback = true;
      hilog.info(DOMAIN, TAG, '[%{public}s] AsyncNapiCallback fired, err=%{public}s', stage, JSON.stringify(err));
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, '[%{public}s] AsyncNapiCallback throw %{public}s', stage, JSON.stringify(e));
  }

  try {
    preferences.getPreferences(ctx, 'probe_store').then((pref: preferences.Preferences) => {
      st.preferencesPromise = true;
      hilog.info(DOMAIN, TAG, '[%{public}s] PreferencesPromise resolved', stage);
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, '[%{public}s] PreferencesPromise rejected, %{public}s', stage, JSON.stringify(err));
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, '[%{public}s] PreferencesPromise throw %{public}s', stage, JSON.stringify(e));
  }

  try {
    const cfg: relationalStore.StoreConfig = {
      name: 'probe.db',
      securityLevel: relationalStore.SecurityLevel.S1
    };
    relationalStore.getRdbStore(ctx, cfg).then((store: relationalStore.RdbStore) => {
      st.rdbPromise = true;
      hilog.info(DOMAIN, TAG, '[%{public}s] RdbPromise resolved, version=%{public}d', stage, store.version);
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, '[%{public}s] RdbPromise rejected, %{public}s', stage, JSON.stringify(err));
    });
  } catch (e) {
    hilog.error(DOMAIN, TAG, '[%{public}s] RdbPromise throw %{public}s', stage, JSON.stringify(e));
  }

  setTimeout(() => {
    hilog.info(DOMAIN, TAG, '[%{public}s] SUMMARY %{public}s', stage, st.summary());
  }, 8000);

  hilog.info(DOMAIN, TAG, '=== probe submitted [%{public}s] ===', stage);
}
