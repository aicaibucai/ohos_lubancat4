#!/bin/bash
# 编译 + 手动签名探针 HAP（hvigor 的签名需要加密口令，这里跳过它自己签）
# 用法: SDK=<sdk根目录> MODE=debug|release bash build-probe.sh
set -e
cd $DEV_HOME/oh-probe-app
export PATH="$NODE_BIN:$PATH"
export OHOS_BASE_SDK_HOME="${SDK:-$OH_SRC/prebuilts/ohos-sdk/linux}"
export DEVECO_SDK_HOME="$OHOS_BASE_SDK_HOME"
MODE="${MODE:-debug}"

bash ./hvigorw assembleHap --mode module -p product=default -p module=entry@default \
  -p buildMode="$MODE" 2>&1 | grep -E "ERROR|BUILD|Failed" | tail -5 || true

SDKLIB="$OHOS_BASE_SDK_HOME/23/toolchains/lib"
[ -d "$SDKLIB" ] || SDKLIB="$OH_SRC/prebuilts/ohos-sdk/linux/23/toolchains/lib"

# 注意：signature/ 目录（OpenHarmony.p12 私钥 + cer + p7b profile）未随仓库发布，
#       请从 OpenHarmony SDK 获取或替换为你自己的调试签名：
#       $OH_SRC/prebuilts/ohos-sdk/linux/23/toolchains/lib/ 下有官方调试证书
java -jar "$SDKLIB/hap-sign-tool.jar" sign-app \
  -keyAlias "openharmony application release" -signAlg "SHA256withECDSA" -mode "localSign" \
  -appCertFile signature/OpenHarmonyApplication.cer -profileFile signature/probe.p7b \
  -inFile entry/build/default/outputs/default/entry-default-unsigned.hap \
  -keystoreFile signature/OpenHarmony.p12 -outFile /tmp/probe-signed.hap \
  -keyPwd "123456" -keystorePwd "123456" 2>&1 | tail -1

cp /tmp/probe-signed.hap <FLASH_DIR>/probe-app.hap
python3 - <<'EOF'
import zipfile, json
z = zipfile.ZipFile('/tmp/probe-signed.hap')
d = json.loads(z.read('module.json'))
a, m = d['app'], d['module']
print('HAP: bundle=%s minAPI=%s targetAPI=%s compileSdkVersion=%s debug=%s virtualMachine=%s' %
      (a.get('bundleName'), a.get('minAPIVersion'), a.get('targetAPIVersion'),
       a.get('compileSdkVersion'), a.get('debug'), m.get('virtualMachine')))
EOF
