#!/usr/bin/env bash
# 按本机安装的 HarmonyOS SDK 同步 ohos/build-profile.json5 的 SDK 版本。
#
# DevEco command-line-tools / DevEco Studio 不同版本内置的 SDK 不同，而
# build-profile.json5 里的 compatibleSdkVersion/targetSdkVersion 必须与本机 SDK
# 匹配。版本号格式随 API 级别分两套（hvigor 的 FIRST_DOT_API_VERSION = 26）：
#   - API < 26：`"5.1.0(18)"` 这种「版本(API)」字符串；
#   - API ≥ 26：只接受点分形式 `"26.0.0"`，写成 `"26.0.0(26)"` 会被 hvigor 拒绝
#     （00308018 api version parameter is illegal）。
# 这个脚本读取 SDK 自带的 sdk-pkg.json，按上述规则生成字符串并写回工程配置。
#
# 用法：
#   CLT=/path/to/command-line-tools bash scripts/ohos-sync-sdk-version.sh [--dry-run]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLT="${CLT:-$HOME/ohos-dev/command-line-tools}"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

SDK_PKG="${DEVECO_SDK_HOME:-$CLT/sdk}/default/sdk-pkg.json"
if [[ ! -f "$SDK_PKG" ]]; then
  echo "找不到 SDK 描述文件：$SDK_PKG" >&2
  echo "可用 DEVECO_SDK_HOME=/path/to/<clt>/sdk 或 CLT=/path/to/command-line-tools 指定。" >&2
  exit 1
fi

# displayName 里带空格（"HarmonyOS 5.1.0"），因此逐项读取而不是一次 read 两个变量。
DISPLAY="$(python3 - "$SDK_PKG" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['data'].get('displayName', ''))
PY
)"
PLATFORM_VERSION="$(python3 - "$SDK_PKG" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))['data']
version = (data.get('platformVersion') or '').strip()
if not version:
    display = (data.get('displayName') or '').strip()
    parts = [part for part in display.split(' ') if part[:1].isdigit()]
    version = parts[-1] if parts else ''
print(version or data.get('apiVersion', ''))
PY
)"
read -r API < <(python3 - "$SDK_PKG" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))['data'].get('apiVersion', ''))
PY
)

if [[ -z "$API" ]]; then
  echo "无法从 $SDK_PKG 解析 apiVersion" >&2
  exit 1
fi

# API ≥ 26 用点分形式；此时 platformVersion 本身已是 26.0.0 这样的三段式。
if [[ "$API" -ge 26 ]] 2>/dev/null; then
  SDK_STRING="$PLATFORM_VERSION"
  FORMAT_HINT="（API ≥ 26：hvigor 只接受点分形式的版本号）"
else
  SDK_STRING="${PLATFORM_VERSION}(${API})"
  FORMAT_HINT=""
fi

echo "本机 SDK：$DISPLAY（API $API）→ compatibleSdkVersion = \"$SDK_STRING\"$FORMAT_HINT"

python3 - "$SDK_STRING" "$DRY_RUN" <<'PY'
import re, sys

sdk_string, dry_run = sys.argv[1], sys.argv[2] == '1'
paths = ['ohos/build-profile.json5']
changed = []
for path in paths:
    src = open(path, encoding='utf-8').read()
    original = src
    for key in ('compatibleSdkVersion', 'targetSdkVersion'):
        src = re.sub(
            r'("%s"\s*:\s*)"[^"]*"' % key,
            lambda m: f'{m.group(1)}"{sdk_string}"',
            src,
        )
    if src != original:
        changed.append(path)
        if not dry_run:
            open(path, 'w', encoding='utf-8').write(src)

if not changed:
    print('build-profile.json5 已经是该版本，无需修改。')
elif dry_run:
    print('（dry-run）将更新：' + '、'.join(changed))
else:
    print('已更新：' + '、'.join(changed))
PY

echo
echo "提示：运行时仍需与引擎 flutter.har 的 compileSdkVersion 一致；"
echo "      可用 bash scripts/ohos-doctor.sh 检查工具链是否齐备。"
