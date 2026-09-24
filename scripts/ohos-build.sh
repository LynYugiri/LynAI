#!/usr/bin/env bash
# 在已准备好的鸿蒙工具链上构建未签名 HAP。
#
# 前置条件（详见 doc/harmonyos.md）：
#   1. `flutter`（或 FLUTTER_BIN）指向鸿蒙 Flutter SDK
#      （openharmony-sig/flutter_flutter，oh-3.44.9-dev）；
#   2. DevEco command-line-tools 解压在本地（需 API ≥ 26 的 HarmonyOS SDK：
#      引擎 flutter.har 的 ArkTS 用到 API 26 才公开的 autoFillManager 接口，
#      详见 doc/harmonyos.md §4）；
#   3. 已执行过 scripts/ohos-pub-get.sh 应用鸿蒙依赖覆盖。
#
# 用法：
#   CLT=$HOME/ohos-dev/command-line-tools bash scripts/ohos-build.sh [--debug|--release]
#
# 需要在 PATH 里提供鸿蒙 Flutter SDK，或用 FLUTTER_BIN 指向它的 bin/flutter：
#   FLUTTER_BIN=$HOME/dev/ohos/flutter_flutter_probe/bin/flutter bash scripts/ohos-build.sh
#
# 构建失败时会按错误归属给出结论（引擎自带 HAR / 工程自有代码 / 依赖），
# 避免把 30 多个 ArkTS 报错直接甩给使用者。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="${1:---debug}"
CLT="${CLT:-$HOME/ohos-dev/command-line-tools}"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
BUILD_LOG="$(mktemp -t lynai-ohos-build.XXXXXX.log)"

cleanup() {
  rm -f "$BUILD_LOG"
}
trap cleanup EXIT

if [[ ! -d "$CLT" ]]; then
  echo "找不到 command-line-tools：$CLT（可用 CLT=/path/to/command-line-tools 覆盖）" >&2
  exit 1
fi

# 构建 HAP 必须用 openharmony-sig/flutter_flutter；官方 stable 没有 hap target，
# 否则会在解析参数时报出与鸿蒙无关的“Could not find an option named --debug”。
if ! "$FLUTTER_BIN" --version 2>/dev/null | grep -q "flutter_flutter"; then
  cat >&2 <<EOF
当前 flutter 不是鸿蒙 Flutter SDK：$FLUTTER_BIN
构建 HAP 需要 openharmony-sig/flutter_flutter（oh-3.44.9-dev）。

请指向鸿蒙 SDK 后重试：
  FLUTTER_BIN=/path/to/flutter_flutter/bin/flutter bash scripts/ohos-build.sh $MODE
EOF
  exit 1
fi

export DEVECO_SDK_HOME="$CLT/sdk"
export NODE_HOME="$CLT/tool/node"
export PATH="$CLT/bin:$CLT/ohpm/bin:$CLT/hvigor/bin:$CLT/tool/node/bin:$PATH"

if [[ ! -f pubspec_overrides.yaml ]]; then
  echo "提示：尚未应用鸿蒙依赖覆盖，先执行 bash scripts/ohos-pub-get.sh" >&2
  exit 1
fi

# 诊断：区分「引擎自带 HAR 需要更新的 SDK」与「工程/依赖自身的问题」。
#
# ArkTS 编译错误在日志里成对出现（Error Message + At File: <路径>），只统计
# At File 行，避免把 WARN 或生成文件提示算进来；同一处报错会在日志里出现两次
# （hvigor 原始输出 + flutter 转发），因此按去重后的「文件:行:列」计数。
#
# 注意：各类路径并不互斥——引擎 HAR 与三方插件都通过软链接落在
# $ROOT/ohos/**/oh_modules/ 下（如 ohos/oh_modules/.ohpm/@ohos+flutter_ohos@…），
# 所以必须先把 oh_modules 与 .pub-cache 排除，剩下的才算「工程自有 ArkTS」。
diagnose_failure() {
  local summary total engine_errors project_errors dependency_errors other_errors attributed
  summary="$(grep -oE "ERROR:[0-9]+ WARN:[0-9]+" "$BUILD_LOG" | tail -1 || true)"
  total="$(printf '%s' "$summary" | sed -nE 's/^ERROR:([0-9]+).*/\1/p' || true)"

  local files engine_files dependency_files owned project_files
  files="$(grep -oE "At File: [^ ]+" "$BUILD_LOG" | sed 's|At File: ||' | sort -u || true)"
  engine_files="$(printf '%s\n' "$files" | grep "oh_modules/.ohpm/@ohos+flutter_ohos" || true)"
  dependency_files="$(printf '%s\n' "$files" | grep "\.pub-cache/" || true)"
  # 先剔除依赖目录，剩下的才可能是工程自有代码；再丢掉空行，避免把空串当成 1 处。
  owned="$(printf '%s\n' "$files" \
    | grep -v -e "oh_modules/" -e "\.pub-cache/" | grep -v '^$' || true)"
  project_files="$(printf '%s\n' "$owned" | grep "^$ROOT/ohos/" || true)"

  engine_errors="$(printf '%s\n' "$engine_files" | grep -c . || true)"
  dependency_errors="$(printf '%s\n' "$dependency_files" | grep -c . || true)"
  project_errors="$(printf '%s\n' "$project_files" | grep -c . || true)"
  other_errors="$(printf '%s\n' "$owned" | grep -v "^$ROOT/ohos/" | grep -c . || true)"

  echo
  echo "构建失败。ArkTS 报错归属（按去重后的 At File 统计）："
  if [[ -z "$files" ]]; then
    echo "  - 日志里没有任何 ArkTS 编译错误（At File），失败发生在更早的阶段。"
    echo "    常见原因：SDK 版本不匹配、ohpm 依赖未安装、hvigor 配置错误。"
    echo
    echo "  —— 日志末尾 ——"
    tail -n 30 "$BUILD_LOG"
    return
  fi
  echo "  - 引擎自带 HAR（@ohos/flutter_ohos）：$engine_errors 处"
  echo "  - 工程自有 ArkTS（ohos/）：$project_errors 处"
  echo "  - 三方依赖（pub-cache 里的鸿蒙适配插件，如 record_ohos）：$dependency_errors 处"
  echo "  - 其它：$other_errors 处"
  if [[ "$other_errors" -gt 0 ]]; then
    # 归类不确定时把原始路径打出来，方便核对（例如 SDK 自带文件）。
    printf '%s\n' "$owned" | grep -v "^$ROOT/ohos/" | grep . | sed 's/^/      /'
  fi
  [[ -n "$summary" ]] && echo "  - 编译器汇总：$summary"

  attributed=$((engine_errors + project_errors + dependency_errors + other_errors))
  if [[ -n "$total" && "$total" -gt "$attributed" ]]; then
    echo "  - hvigor 汇总比可定位报错多 $((total - attributed)) 处（统计口径差异，不影响归属）"
  fi
  echo

  if [[ "$project_errors" -eq 0 && "$engine_errors" -gt 0 ]]; then
    local autofill_only=1 file
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      if [[ "$file" != *"plugin/editing/OhosAutoFillHelper.ets"* ]]; then
        autofill_only=0
      fi
    done <<< "$engine_files"

    echo "结论：工程自有代码没有编译错误，失败来自 Flutter 引擎预编译的 flutter.har。" >&2
    echo >&2
    if [[ "$autofill_only" -eq 1 ]]; then
      cat >&2 <<'EOF'
具体原因：引擎的 OhosAutoFillHelper.ets 直接使用 autoFillManager 的自动填充接口
（AutoFillType / ViewData / FillRequest / SaveRequest / AutoFillCallback /
requestAutoFill 等），这些接口在 API ≤ 24 的公开 SDK 里仍是系统接口
（SDK 声明为 @systemapi [since 11 - 24]，到 26.0.0 才转公开），因此公开 SDK
编译不过。引擎自身有 AUTOFILL_SUPPORT_API = 26 的运行时短路，设备 API < 26
时不会调用它们，所以这纯粹是编译期缺声明的问题。
EOF
    fi
    cat >&2 <<'EOF'

下一步：
  1. 换用 API ≥ 26 的 command-line-tools / DevEco Studio（HarmonyOS 7 起公开了
     上述接口），或使用带系统接口的 Full SDK；
  2. CLT=/path/to/command-line-tools bash scripts/ohos-doctor.sh 确认工具链；
  3. CLT=... bash scripts/ohos-sync-sdk-version.sh 校准 build-profile.json5；
  4. 重新执行本脚本。

详见 doc/harmonyos.md §4「公开 SDK 与引擎要求的差距」。
EOF
  elif [[ "$project_errors" -gt 0 ]]; then
    echo "结论：失败包含工程自有 ArkTS 错误，请先修下面这些文件：" >&2
    echo >&2
    printf '%s\n' "$project_files" >&2
  else
    echo "结论：失败不在工程自有代码，请查看完整日志（已保留在上面的输出里）。" >&2
  fi
  echo
  echo "提示：完整日志同时写入了 $BUILD_LOG（脚本退出时会删除）。" >&2
  echo "      如需保留，请改用手动命令：flutter build hap ${MODE} --no-codesign | tee build.log" >&2
}

set +e
"$FLUTTER_BIN" build hap "${MODE}" --no-codesign 2>&1 | tee "$BUILD_LOG"
STATUS="${PIPESTATUS[0]}"
set -e

if [[ "$STATUS" -ne 0 ]]; then
  diagnose_failure
  exit "$STATUS"
fi

echo
echo "产物：build/ohos/hap/"
