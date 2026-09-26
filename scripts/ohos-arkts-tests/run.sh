#!/usr/bin/env bash
# 跑鸿蒙 ArkTS 侧的纯逻辑单元测试。
#
# 这些测试直接用 Node 执行 ohos/entry/src/main/ets/lynai/*.ts 里的原生实现
# （Node 的类型剥离：>= 22.6 需要 --experimental-strip-types，>= 23 默认开启），
# 因此验证的就是 ArkTS 构建实际编译的那份源码，而不是复制出来的逻辑。
#
# 用法：bash scripts/ohos-arkts-tests/run.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
  echo "需要 Node.js（>= 22.6）：未在 PATH 中找到 node" >&2
  exit 1
fi

NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
# ohos/package.json 是构建期生成的（不入库），这里直接关掉「模块类型未声明」的提示。
FLAGS=(--disable-warning=MODULE_TYPELESS_PACKAGE_JSON)
if [[ "$NODE_MAJOR" -ge 23 ]]; then
  :
elif [[ "$NODE_MAJOR" -eq 22 ]]; then
  FLAGS+=(--experimental-strip-types)
else
  echo "需要 Node.js >= 22.6（当前 $(node --version)）才能直接运行 TypeScript 源码" >&2
  exit 1
fi

# 显式列出测试文件，不把目录交给 `--test`：Node 22 会把目录参数当成模块去加载
# （MODULE_NOT_FOUND），而 Node 23+ 才按目录递归查找，同一个脚本在两端行为不同。
# 通配符由 shell 展开，任何 Node 版本都只看到一组文件参数。
shopt -s nullglob
TESTS=(scripts/ohos-arkts-tests/*.test.mjs)
if [[ ${#TESTS[@]} -eq 0 ]]; then
  echo "没有找到 ArkTS 单元测试（scripts/ohos-arkts-tests/*.test.mjs）" >&2
  exit 1
fi

node "${FLAGS[@]}" --test "${TESTS[@]}"
