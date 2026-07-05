# LynAI Third-Party Notices

本文件补充 LynAI 前端随包分发、vendored、本地构建或平台构建时引入的第三方开源组件说明。Flutter/Dart 通过 pub 获取的依赖会由 Flutter 构建流程生成 `NOTICES` 并显示在应用的开源许可页；本文件主要覆盖仓库内本地包、静态前端资产、字体和原生构建依赖。

LynAI 自身遵循 GPL-3.0，完整文本见仓库根目录 `LICENSE`。

## Bundled and Vendored Components

| 组件 | 位置/来源 | 许可证 | 说明 |
|------|-----------|--------|------|
| webview_all_linux | `third_party/webview_all_linux/` | BSD-3-Clause | 完整文本见 `third_party/webview_all_linux/LICENSE`。 |
| webview_all_windows | `third_party/webview_all_windows/` | BSD-3-Clause | 完整文本见 `third_party/webview_all_windows/LICENSE`。 |
| lua_dardo LynAI fork | `third_party/lua_dardo/` | Apache-2.0 | 完整文本见 `third_party/lua_dardo/LICENSE`；LynAI fork 保留上游同步 API 并加入异步 Dart 回调路径。 |
| MathLive 0.109.2 | `assets/mathlive/mathlive.min.js`、`assets/mathlive/editor.html`、`assets/mathlive/sounds/` | MIT | Copyright (c) 2017-present Arno Gourdol. |
| KaTeX fonts/static assets | `assets/mathlive/fonts/`、`assets/mathlive/mathlive-fonts.css` | MIT | Copyright (c) 2013-2020 Khan Academy and other contributors. |
| Mermaid | `assets/mermaid/mermaid.min.js`、`assets/mermaid/renderer.html` | MIT | Copyright (c) 2014-2022 Knut Sveidqvist；打包文件末尾保留了 Mermaid 及其依赖的 bundled license block。 |
| DOMPurify | bundled inside `assets/mermaid/mermaid.min.js` | Apache-2.0 OR MPL-2.0 | Mermaid bundle 中的安全清理依赖；bundle 内保留版本和许可声明。 |
| Mermaid bundled dependencies | bundled inside `assets/mermaid/mermaid.min.js` | MIT | 包含 js-yaml、lodash、cytoscape 相关子依赖及其保留声明。 |
| Hurmit Nerd Font 3.4.0 | `assets/fonts/HurmitNerdFont-*.otf` | OFL-1.1 | Copyright (c) 2017 Pablo Caro；Reserved Font Name: Hermit；字体元数据内含完整 SIL Open Font License 1.1 文本。 |

## Native and Platform Build Components

| 组件 | 位置/来源 | 许可证 | 说明 |
|------|-----------|--------|------|
| ncnn 20260526 | Android OCR 构建时由 `scripts/fetch-ncnn-deps.sh` 下载到 `android/app/src/main/jni/` | BSD-3-Clause | 预构建包及相关 third-party notices 随下载包提供；`native/ocr/ppocrv5.*` 源文件保留 ncnn BSD-3-Clause 头部。 |
| opencv-mobile 4.13.0 v35 | Android OCR 构建时由 `scripts/fetch-ncnn-deps.sh` 下载到 `android/app/src/main/jni/` | Apache-2.0 | 下载包内含 `LICENSE`。 |
| PPOCRv5 mobile models | Android OCR 构建时由 `scripts/fetch-ncnn-deps.sh` 从 `nihui/ncnn-android-ppocrv5` 下载到 `android/app/src/main/assets/ocr_models/` | Apache-2.0 | 用于本地 OCR 模型推理；模型文件未提交到 git。 |
| Tree-sitter core 0.25.10 | `native/tree_sitter/CMakeLists.txt` 在配置阶段拉取 | MIT | 拉取目录为 gitignored 的 `native/tree_sitter/.fetch-cache/`。 |
| Tree-sitter grammars | `native/tree_sitter/CMakeLists.txt` 拉取 JavaScript、TypeScript/TSX、HTML、CSS、Python、Go、Rust、C、C++、Java、JSON、Bash、YAML、TOML、Markdown 语法 | MIT | 各 grammar 的 `LICENSE` 保留在构建拉取目录中，发布构建仅打包编译产物。 |

## Notes

- 仓库内 `native/tree_sitter/.fetch-cache/`、`android/app/src/main/jni/`、`android/app/src/main/assets/ocr_models/` 属于构建缓存或平台依赖输出，不提交到 git。
- 若发布包包含上述构建时下载组件，应随发布工件保留本文件及对应下载包内的许可证文本。
