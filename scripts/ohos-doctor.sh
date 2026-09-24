#!/usr/bin/env bash
# 检查鸿蒙构建所需的工具链是否齐备，并指出缺什么。
#
# 用法：
#   CLT=/path/to/command-line-tools bash scripts/ohos-doctor.sh
#   FLUTTER_BIN=/path/to/flutter_flutter/bin/flutter CLT=... bash scripts/ohos-doctor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CLT="${CLT:-$HOME/ohos-dev/command-line-tools}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
ok=0
warn=0
fail=0

pass() { echo "  [✓] $1"; ok=$((ok + 1)); }
caution() { echo "  [!] $1"; warn=$((warn + 1)); }
problem() { echo "  [✗] $1"; fail=$((fail + 1)); }

echo "鸿蒙构建工具链检查"
echo

echo "Flutter SDK"
if command -v "$FLUTTER_BIN" >/dev/null 2>&1 || [[ -x "$FLUTTER_BIN" ]]; then
  version="$("$FLUTTER_BIN" --version 2>/dev/null | head -1)"
  if "$FLUTTER_BIN" --version 2>/dev/null | grep -q "flutter_flutter"; then
    pass "$version（鸿蒙分支）"
  else
    problem "当前 flutter 不是 openharmony-sig/flutter_flutter 分支：$version（可用 FLUTTER_BIN=... 覆盖）"
  fi
else
  problem "找不到 flutter：$FLUTTER_BIN（可用 FLUTTER_BIN=/path/to/flutter_flutter/bin/flutter 覆盖）"
fi

echo
echo "DevEco command-line-tools（$CLT）"
if [[ -d "$CLT" ]]; then
  pass "目录存在"
  sdk_pkg="$CLT/sdk/default/sdk-pkg.json"
  if [[ -f "$sdk_pkg" ]]; then
    api="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['data'].get('apiVersion',''))" "$sdk_pkg" 2>/dev/null)"
    name="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['data'].get('displayName',''))" "$sdk_pkg" 2>/dev/null)"
    sdk_version="$(python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))['data']
print(data.get('platformVersion') or data.get('version') or '')
" "$sdk_pkg" 2>/dev/null)"
    # 比的是 SDK 自身的版本（platformVersion，如 5.1.0 / 6.1.1），不是 apiVersion：
    # 引擎自带 flutter.har 的 module.json 声明 compileSdkVersion 6.1.1.125，
    # 低于 6.1 的 SDK 会在 CompileArkTS 阶段报引擎 API 缺失。
    sdk_version_ok=0
    if python3 -c "
import sys
parts = (sys.argv[1] or '').split('.')
def num(index):
    try:
        return int(parts[index])
    except (IndexError, ValueError):
        return 0
sys.exit(0 if (num(0), num(1)) >= (6, 1) else 1)
" "$sdk_version" 2>/dev/null; then
      sdk_version_ok=1
      pass "HarmonyOS SDK $name（$sdk_version，apiVersion $api）"
    else
      problem "HarmonyOS SDK $name（${sdk_version:-未知版本}，apiVersion $api）：引擎 flutter.har 声明 compileSdkVersion 6.1.1.125，需要 DevEco 6.1 及以上（实测 5.1.0(18) 会在 CompileArkTS 阶段报引擎 API 缺失）"
    fi
    # 引擎的 OhosAutoFillHelper.ets 使用 autoFillManager 的自动填充接口，这些接口
    # 在公开 SDK 里到 API 26 才从系统接口转为公开（@systemapi [since 11 - 24]），
    # 因此 API < 26 的公开 SDK 会在 CompileArkTS 阶段稳定报错（实测 6.1.1/API 24：
    # 14 处，全部落在该文件里）。版本本身就不够时只报上面那条，避免重复。
    if [[ "$sdk_version_ok" -eq 1 ]] && [[ -n "$api" ]] && [[ "$api" -lt 26 ]] 2>/dev/null; then
      problem "SDK 的 API 级别为 $api（< 26）：引擎用的 autoFillManager 自动填充接口在公开 SDK 里到 API 26 才公开，编译会在 CompileArkTS 阶段因缺声明失败；请换 API ≥ 26 的 command-line-tools（HarmonyOS 7 起）或带系统接口的 Full SDK"
    fi
  else
    problem "缺少 $sdk_pkg（SDK 未随 command-line-tools 解压？）"
  fi
  for tool in bin/hvigorw ohpm/bin/ohpm tool/node/bin/node; do
    if [[ -x "$CLT/$tool" ]]; then
      pass "$tool"
    else
      caution "缺少或不可执行：$CLT/$tool"
    fi
  done
else
  problem "找不到 $CLT（可用 CLT=/path/to/command-line-tools 覆盖）"
fi

echo
echo "JDK"
if command -v java >/dev/null 2>&1; then
  pass "$(java -version 2>&1 | head -1)"
else
  caution "PATH 中没有 java（hvigor 打包阶段需要 JDK 17 及以上）"
fi

echo
echo "工程状态"
if [[ -f pubspec_overrides.yaml ]]; then
  pass "鸿蒙依赖覆盖已生效（pubspec_overrides.yaml 存在）"
else
  caution "尚未应用鸿蒙依赖覆盖，先执行 bash scripts/ohos-pub-get.sh"
fi
if [[ -d build/ohos_deps ]]; then
  pass "已生成打过补丁的依赖副本 build/ohos_deps/"
else
  caution "缺少 build/ohos_deps/（由 scripts/ohos-pub-get.sh 生成）"
fi
if [[ -d ohos/entry/libs ]]; then
  caution "ohos/entry/libs 存在：切换 sqlite3 方案后需要删除，否则 ProcessLibs 会报同名 .so 冲突"
fi

echo
echo "结论：$ok 项通过，$warn 项提示，$fail 项阻塞"
[[ "$fail" -eq 0 ]]
