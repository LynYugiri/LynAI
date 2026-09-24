#!/usr/bin/env bash
# 用 SDK 自带的 OpenHarmony 材料给未签名 HAP 做「本地自签名」。
#
# 适用场景与限制（详见 doc/harmonyos.md §4「签名与安装」）：
#   - 不需要华为账号，用 command-line-tools 自带的 OpenHarmony 演示证书链签名；
#   - 只能安装到信任 OpenHarmony 根证书的设备/模拟器（通常还要开发者模式），
#     **装不到零售 HarmonyOS 手机**——那需要华为签发的调试证书 + 绑定设备 UDID 的
#     调试 Profile，或者走发布证书 + AppGallery 分发（发布证书签名包无法本地安装，
#     hdc 会报 INSTALL_FAILED_APP_SOURCE_NOT_TRUSTED）；
#   - 用途：验证签名链路与产物完整性、给 OpenHarmony 设备/CI 提供可安装包。
#
# 用法：
#   CLT=/path/to/command-line-tools bash scripts/ohos-sign-local.sh
#   CLT=... bash scripts/ohos-sign-local.sh --in <unsigned.hap> --out <signed.hap>
#
# 可覆盖的环境变量：KEYSTORE_PWD / APP_KEY_ALIAS / PROFILE_KEY_ALIAS
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLT="${CLT:-$HOME/ohos-dev/command-line-tools}"
IN_HAP="build/ohos/hap/entry-default-unsigned.hap"
OUT_HAP="build/ohos/hap/entry-default-signed.hap"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in) IN_HAP="$2"; shift 2 ;;
    --out) OUT_HAP="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

LIB="$CLT/sdk/default/openharmony/toolchains/lib"
SIGN_TOOL="$LIB/hap-sign-tool.jar"
KEYSTORE="$LIB/OpenHarmony.p12"
PROFILE_CERT="$LIB/OpenHarmonyProfileRelease.pem"
RELEASE_TEMPLATE="$LIB/UnsgnedReleasedProfileTemplate.json"
KEYSTORE_PWD="${KEYSTORE_PWD:-123456}"          # 演示密钥库的公开口令
APP_KEY_ALIAS="${APP_KEY_ALIAS:-openharmony application release}"
PROFILE_KEY_ALIAS="${PROFILE_KEY_ALIAS:-openharmony application profile release}"
WORK="build/ohos/sign-local"

for f in "$SIGN_TOOL" "$KEYSTORE" "$PROFILE_CERT" "$RELEASE_TEMPLATE"; do
  if [[ ! -f "$f" ]]; then
    echo "缺少签名材料：$f（CLT=$CLT，可用 CLT=/path/to/command-line-tools 覆盖）" >&2
    exit 1
  fi
done
if [[ ! -f "$IN_HAP" ]]; then
  echo "找不到待签名 HAP：$IN_HAP（先执行 bash scripts/ohos-build.sh）" >&2
  exit 1
fi
for bin in java keytool; do
  command -v "$bin" >/dev/null 2>&1 || { echo "PATH 中缺少 $bin（需要 JDK 17+）" >&2; exit 1; }
done

# HAP 的 bundleName 必须与 Profile 里写的一致，否则设备会拒绝安装。
BUNDLE="$(python3 - <<'PY'
import json, re
src = open('ohos/AppScope/app.json5', encoding='utf-8').read()
src = '\n'.join(line for line in src.splitlines() if not line.strip().startswith('//'))
src = re.sub(r',(\s*[}\]])', r'\1', src)
print(json.loads(src)['app']['bundleName'])
PY
)"
HAP_BUNDLE="$(python3 - "$IN_HAP" <<'PY'
import json, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    print(json.loads(z.read('module.json'))['app']['bundleName'])
PY
)"
if [[ "$BUNDLE" != "$HAP_BUNDLE" ]]; then
  echo "bundleName 不一致：app.json5=$BUNDLE，HAP=$HAP_BUNDLE" >&2
  exit 1
fi

mkdir -p "$WORK"
echo "签名材料：$LIB"
echo "bundleName：$BUNDLE"
echo "待签名：$IN_HAP → $OUT_HAP"

# 1) 应用证书链：应用证书取 Profile 模板里的 distribution-certificate
#    （它与密钥库里 APP_KEY_ALIAS 的私钥是同一对密钥），CA 与根证书用 keytool
#    从密钥库导出，再按工具要求的 leaf → CA → root 顺序拼成一个 PEM。
for alias in "openharmony application ca" "openharmony application root ca"; do
  keytool -exportcert -rfc -alias "$alias" -keystore "$KEYSTORE" -storetype PKCS12 \
    -storepass "$KEYSTORE_PWD" 2>/dev/null \
    | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
    > "$WORK/$(echo "$alias" | tr ' ' '_').pem"
done
python3 - "$LIB" "$WORK" <<'PY'
import json, pathlib, sys
lib, work = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
template = json.loads((lib / 'UnsgnedReleasedProfileTemplate.json').read_text())
dist = template['bundle-info']['distribution-certificate'].strip()
ca = (work / 'openharmony_application_ca.pem').read_text().strip()
root = (work / 'openharmony_application_root_ca.pem').read_text().strip()
(work / 'OpenHarmonyApplication.pem').write_text('\n'.join([dist, ca, root]) + '\n')
print('  应用证书链：leaf → CA → root')
PY

# 2) Profile 证书链：SDK 自带文件是 root 开头，工具要求 leaf 开头，这里重排。
python3 - "$PROFILE_CERT" "$WORK/OpenHarmonyProfileRelease.pem" <<'PY'
import pathlib, re, sys
blocks = re.findall(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',
                    pathlib.Path(sys.argv[1]).read_text(), re.S)
assert len(blocks) == 3, f'预期 3 级证书链，实际 {len(blocks)} 级'
pathlib.Path(sys.argv[2]).write_text('\n'.join(b.strip() for b in reversed(blocks)) + '\n')
print('  Profile 证书链：leaf → CA → root')
PY

# 3) 生成本工程的 Provision Profile（release 型：不绑定设备 UDID）。
python3 - "$RELEASE_TEMPLATE" "$WORK/lynai-profile.json" "$BUNDLE" <<'PY'
import json, pathlib, sys, time, uuid
template = json.loads(pathlib.Path(sys.argv[1]).read_text())
template['uuid'] = str(uuid.uuid4())
template['validity'] = {
    'not-before': int(time.time()) - 86400,   # 昨天
    'not-after': 2524608000,                  # 2049-12-31，不超出应用证书有效期
}
template['bundle-info']['bundle-name'] = sys.argv[3]
pathlib.Path(sys.argv[2]).write_text(json.dumps(template, indent=4, ensure_ascii=False) + '\n')
print(f'  Profile：bundle-name={sys.argv[3]} type={template["type"]} uuid={template["uuid"]}')
PY

# 4) 签 Profile，再用它签 HAP。
java -jar "$SIGN_TOOL" sign-profile \
  -mode localSign -keyAlias "$PROFILE_KEY_ALIAS" -keyPwd "$KEYSTORE_PWD" \
  -profileCertFile "$WORK/OpenHarmonyProfileRelease.pem" \
  -inFile "$WORK/lynai-profile.json" -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" \
  -outFile "$WORK/lynai.p7b" > "$WORK/sign-profile.log" 2>&1

java -jar "$SIGN_TOOL" sign-app \
  -mode localSign -keyAlias "$APP_KEY_ALIAS" -keyPwd "$KEYSTORE_PWD" \
  -appCertFile "$WORK/OpenHarmonyApplication.pem" -profileFile "$WORK/lynai.p7b" \
  -inFile "$IN_HAP" -signAlg SHA256withECDSA \
  -keystoreFile "$KEYSTORE" -keystorePwd "$KEYSTORE_PWD" \
  -outFile "$OUT_HAP" -compatibleVersion 26 > "$WORK/sign-app.log" 2>&1

# 5) 校验签名（digest + 权限签名 + 证书链），并单独导出 Profile 的 JSON 便于核对。
java -jar "$SIGN_TOOL" verify-app -inFile "$OUT_HAP" \
  -outCertChain "$WORK/verify-certchain.cer" -outProfile "$WORK/verify-profile.p7b" \
  > "$WORK/verify-app.log" 2>&1
if ! grep -q "verify-app success" "$WORK/verify-app.log"; then
  echo "签名校验失败，日志：$WORK/verify-app.log" >&2
  tail -20 "$WORK/verify-app.log" >&2
  exit 1
fi
java -jar "$SIGN_TOOL" verify-profile -inFile "$WORK/lynai.p7b" \
  -outFile "$WORK/verify-profile.json" > "$WORK/verify-profile.log" 2>&1

python3 - "$OUT_HAP" "$WORK/verify-profile.json" <<'PY'
import hashlib, json, pathlib, sys
hap = pathlib.Path(sys.argv[1])
data = hap.read_bytes()
profile = json.loads(pathlib.Path(sys.argv[2]).read_text())
content = profile.get('content', profile)
print()
print(f'✅ 已签名：{hap}（{len(data):,} 字节）')
print(f'   sha256：{hashlib.sha256(data).hexdigest()}')
print(f'   Profile：bundle-name={content["bundle-info"]["bundle-name"]} '
      f'type={content["type"]} apl={content["bundle-info"]["apl"]} '
      f'verified={profile.get("verifiedPassed")}')
PY

cat <<'EOF'

说明：本包用 OpenHarmony 演示证书链签名，只能装到信任 OpenHarmony 根证书的
      设备/模拟器；零售 HarmonyOS 手机需要华为签发的调试证书 + 绑定 UDID 的
      调试 Profile（见 doc/harmonyos.md §4「签名与安装」）。
EOF
