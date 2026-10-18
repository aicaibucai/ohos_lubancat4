#!/bin/bash
# 对已签名的探针 HAP 做 module.json 字段替换并重新签名
# 用法: bash patch-hap.sh '<python 表达式，作用于 dict d["app"]/d["module"]>'
# 例:   bash patch-hap.sh 'd["app"]["targetAPIVersion"]=10; d["app"]["minAPIVersion"]=10'
set -e
cd $DEV_HOME/oh-probe-app
SRC=/tmp/probe-signed.hap
OUT=/tmp/probe-patched.hap
EXPR="$1"

rm -rf /tmp/hapwork && mkdir -p /tmp/hapwork && cd /tmp/hapwork
unzip -q "$SRC"
python3 - "$EXPR" <<'EOF'
import json, sys
expr = sys.argv[1]
d = json.load(open('module.json'))
exec(expr)
json.dump(d, open('module.json', 'w'), separators=(',', ':'))
a, m = d['app'], d['module']
print('patched: minAPI=%s targetAPI=%s virtualMachine=%s debug=%s' %
      (a.get('minAPIVersion'), a.get('targetAPIVersion'), m.get('virtualMachine'), a.get('debug')))
EOF
rm -f "$OUT"
zip -q -r -X "$OUT" . -x '.*'
cd $DEV_HOME/oh-probe-app
SDKLIB=$OH_SRC/prebuilts/ohos-sdk/linux/23/toolchains/lib
# 注意：signature/ 目录（OpenHarmony.p12 私钥 + cer + p7b profile）未随仓库发布，
#       请从 OpenHarmony SDK 获取或替换为你自己的调试签名：
#       $OH_SRC/prebuilts/ohos-sdk/linux/23/toolchains/lib/ 下有官方调试证书
java -jar "$SDKLIB/hap-sign-tool.jar" sign-app \
  -keyAlias "openharmony application release" -signAlg "SHA256withECDSA" -mode "localSign" \
  -appCertFile signature/OpenHarmonyApplication.cer -profileFile signature/probe.p7b \
  -inFile "$OUT" -keystoreFile signature/OpenHarmony.p12 -outFile <FLASH_DIR>/probe-app.hap \
  -keyPwd "123456" -keystorePwd "123456" 2>&1 | tail -1
ls -l <FLASH_DIR>/probe-app.hap
