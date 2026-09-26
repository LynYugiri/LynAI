#!/usr/bin/env bash
# 为鸿蒙（HarmonyOS / OpenHarmony）构建准备依赖。
#
# 做三件事：
#   1. 用默认依赖解析一次，确保 pub 缓存里已有需要打补丁的包；
#   2. 把 `fluent_ui`、`flutter_math_fork` 复制到 build/ohos_deps/ 并打上各自的
#      补丁（scripts/ohos_patches/<包名>.patch：鸿蒙 Flutter SDK 给 TargetPlatform
#      增加了 ohos，上游这两个包里的 switch 不穷尽，会在鸿蒙上编译失败）；
#   3. 应用 `pubspec_overrides.ohos.yaml` 并执行 flutter pub get。
#
# `--restore` 会移除生效中的覆盖文件并还原默认 pubspec.lock，
# 保证 Android/iOS/桌面/Web 的依赖图与锁文件不受影响。
#
# 前置条件：PATH 中的 `flutter` 是鸿蒙 Flutter SDK（openharmony-sig/flutter_flutter）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OVERRIDES="pubspec_overrides.ohos.yaml"
ACTIVE="pubspec_overrides.yaml"
LOCK_BACKUP="pubspec.lock.ohos-backup"
VENDOR_DIR="build/ohos_deps"
PATCH_DEPS=(fluent_ui flutter_math_fork)

lock_version() {
  python3 - "$1" <<'PY'
import re, sys
name = sys.argv[1]
text = open('pubspec.lock', encoding='utf-8').read()
match = re.search(r'\n  ' + re.escape(name) + r':\n(?:.*\n)*?    version: "([^"]+)"', text)
if not match:
    sys.exit(f'pubspec.lock 中找不到 {name}')
print(match.group(1))
PY
}

restore() {
  rm -f "$ACTIVE"
  if [[ -f "$LOCK_BACKUP" ]]; then
    mv -f "$LOCK_BACKUP" pubspec.lock
    echo "已还原 pubspec.lock"
  fi
  flutter pub get
}

vendor_patched_deps() {
  local cache_root="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev"
  mkdir -p "$VENDOR_DIR"
  for dep in "${PATCH_DEPS[@]}"; do
    local version source
    version="$(lock_version "$dep")"
    source="$cache_root/$dep-$version"
    if [[ ! -d "$source" ]]; then
      echo "缺少 $source，请先执行 flutter pub get" >&2
      exit 1
    fi
    rm -rf "${VENDOR_DIR:?}/$dep"
    cp -r "$source" "$VENDOR_DIR/$dep"
    if ! patch -p1 -d "$VENDOR_DIR" --forward --silent \
      < "scripts/ohos_patches/$dep.patch"; then
      echo "$dep 的鸿蒙补丁应用失败：scripts/ohos_patches/$dep.patch" >&2
      exit 1
    fi
    echo "已准备 $dep-$version（含鸿蒙 switch 补丁）"
  done
}

if [[ "${1:-}" == "--restore" ]]; then
  restore
  exit 0
fi

if [[ ! -f "$OVERRIDES" ]]; then
  echo "缺少 $OVERRIDES" >&2
  exit 1
fi

if ! flutter --version | grep -q "flutter_flutter"; then
  echo "警告：当前 flutter 不是鸿蒙 Flutter SDK，构建 HAP 需要 openharmony-sig/flutter_flutter。" >&2
fi

# 覆盖生效前的 pubspec.lock 必须是「干净」的默认解析结果，否则 --restore 会把
# 带版本漂移的锁文件当成默认状态还原回去。
if [[ ! -f "$LOCK_BACKUP" ]] && command -v git >/dev/null 2>&1 &&
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
  ! git diff --quiet -- pubspec.lock; then
  echo "警告：pubspec.lock 相对 HEAD 已有改动，请先确认它就是你想要的默认解析结果" >&2
  echo "      （例如 git checkout -- pubspec.lock），再重新运行本脚本。" >&2
fi

rm -f "$ACTIVE"
flutter pub get
vendor_patched_deps

if [[ ! -f "$LOCK_BACKUP" ]]; then
  cp pubspec.lock "$LOCK_BACKUP"
fi
cp "$OVERRIDES" "$ACTIVE"
flutter pub get

echo
echo "鸿蒙依赖覆盖已生效。构建完成后执行：bash scripts/ohos-pub-get.sh --restore"
