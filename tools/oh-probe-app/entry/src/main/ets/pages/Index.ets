import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { runProbe } from '../common/Probe';

const DOMAIN: number = 0x0000;
const TAG: string = 'ProbeApp';

@Entry
@Component
struct Index {
  @State message: string = 'LubanCat4 napi probe';

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'Index aboutToAppear');
    const ctx = getContext(this) as common.Context;
    runProbe(ctx, 'ui');
  }

  build() {
    Column() {
      Text(this.message)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      Text('see hilog tag ProbeApp')
        .fontSize(16)
        .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
