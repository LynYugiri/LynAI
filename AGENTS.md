# Repository Instructions

## Commands
- CI quality gate is `flutter pub get` -> `flutter analyze` -> `flutter test` on Flutter stable.
- If dependencies are already current, use `flutter analyze --no-pub` and `flutter test --no-pub`.
- Run focused tests with `flutter test test/<name>_test.dart`; add `--plain-name '<test name>'` for one case.
- After Drift table/database annotation changes in `lib/services/storage_v2_database.dart`, run `dart run build_runner build --delete-conflicting-outputs` and commit `storage_v2_database.g.dart`.
- Root analysis excludes `third_party/**`; analyze vendored packages only from their own package roots when editing them.
- Local Android builds default to a single ABI for speed: `flutter build apk --release --target-platform android-arm64`; CI still uses `--split-per-abi`.
- Tree-sitter grammar sources are fetched once into `native/tree_sitter/.fetch-cache/` (gitignored) and shared across ABIs/build types; do not commit that cache.

## App Shape
- `lib/main.dart` is the real entrypoint: registers global Providers, runs `StorageV2UpgradeService.ensureReady()`, loads all data partitions, repairs model references, syncs built-in plugins, then builds `HomePage`.
- Preserve the layers: Pages handle UI/lifecycle, Providers own in-memory state and save queues, Repositories persist to `storage_v2`, Services handle API/platform/files/storage upgrades, Models define serializable contracts only.
- Providers notify from memory before queued persistence; do not make UI wait for disk unless the existing flow already does.
- Flush `ConversationProvider.flushPendingSaves()` on lifecycle/dispose paths instead of forcing synchronous writes from UI code.
- Historical conversations and roleplay threads keep settings/model snapshots; global setting/model changes must not silently rewrite old sessions.
- `HomePage` keeps Feature/Chat/Settings alive with an `IndexedStack`; tab switching does not dispose child state.
- `HomePage` owns root back handling and bottom-nav double-tap behavior: Feature -> dashboard, Chat -> new conversation.
- `ChatPage` owns streaming UI, attachments, speech, screenshot export, tool-call loops, and pre-send model recognition; keep protocol/device logic page-local or in Services.
- `ApiService` normalizes OpenAI/Ollama/Anthropic/custom quirks into `StreamChunk`/`ChatResponse`; avoid scattering protocol handling into pages.
- Tool calls route through `ToolCallService`; plugin Lua handlers execute through `PluginLuaRuntimeService`; update schema, validation, permissions, execution, and tests together.
- Roleplay separates reusable scenarios from per-thread snapshots; repair references without mutating old thread state.

## Storage And Data
- `storage_v2/app.db` is the structured source of truth; do not reintroduce `storage_v2/data/*.json` mirrors or back up raw `app.db`.
- Note page bodies live as Markdown files under `storage_v2/notes`; `Note.content` is legacy compatibility.
- Long-lived attachments/resources must be imported into app-private storage through `StorageV2Service.importResourceFile()` and saved as resource IDs/paths/metadata, not embedded message JSON.
- Storage-relative paths must go through `StorageV2Service` safety checks; avoid manual joins for user/plugin/archive-controlled paths.
- Layout and backup schema numbers live in code constants (`StorageV2Service.currentLayoutVersion`, `BackupService.currentSchemaVersion`); do not duplicate numbers in docs.
- `StorageV2UpgradeService` upgrades current storage in place and creates a sibling backup before layout changes.
- Resources are SHA blobs under `assets/blobs/{sha256Prefix}/{sha256}`; display names and MIME data belong in metadata.
- Backups are ZIP partition exports with manifest, note Markdown, resources, and app-private assets; imports should tolerate missing assets by warning and clearing invalid refs.
- Schedule and tool-provided times are normalized to local time; add focused schedule/tool tests when changing date parsing.

## Generated And Vendored Code
- `lib/services/storage_v2_database.g.dart` is committed Drift output; do not hand-edit it.
- Root `pubspec.yaml` overrides `webview_all_linux`, `webview_all_windows`, and `lua_dardo` to local `third_party/**` packages.
- `third_party/lua_dardo` is a LynAI fork with async Dart callback support for Agent Lua; do not replace it with upstream sync-only assumptions.
- Native tree-sitter code lives under `native/tree_sitter/`; Dart uses FFI when available and falls back to stub/Dart highlighting on unsupported platforms.

## Plugins And Assets
- Built-in plugins are `assets/plugins/status-dashboard/`, `assets/plugins/weather-query/`, and `assets/plugins/mobile-agent-skills/`; keep `pubspec.yaml` assets and `PluginRepository.builtInPluginFiles` in sync.
- Built-ins sync from Flutter assets on startup; shipped file changes affect first installs and existing installs, while user-editable files/config should remain preserved where declared.
- Plugin manifest concepts are distinct: `tools` are model tools, `functions` are UI/Agent-callable functions, `skills` are loadable docs, and `featurePages` are WebViews.
- Manifest parsing enforces safe route/file identifiers and permission-gated APIs; add tests with schema, validation, runtime, or permission changes.
- Plugin file writes must respect `editableFiles`; use existing safe path helpers and reject absolute paths, `..`, route-breaking IDs, and URLs where local files are expected.
- `PluginProvider` tracks metadata, enabled state, permissions, config, and API conflicts; Lua/WebView execution lives in Services/widgets.

## Tests And Platform Notes
- Tests commonly call `SharedPreferences.setMockInitialValues({})` and create temp dirs under `Directory.systemTemp`; isolate and clean filesystem tests in `finally`.
- Widget tests that pump `LynAIApp` need the full `main.dart` Provider set, including `RecycleBinProvider` and `PluginProvider`.
- Linux release builds need CI packages: `cmake`, `clang`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `liblzma-dev`, `zstd`.
- macOS release CI patches `speech_to_text` in the pub cache before `flutter build macos --release`; local macOS release failures may need the same patch.
- CI builds Android split APKs, Linux deb/Arch packages, Windows x64 ZIP, and macOS x64/arm64 only after the quality job passes.

## Documentation Sync
- Keep `doc/architecture.md` and `doc/README.md` in sync with startup flow, storage authority, or layer boundary changes.
- Keep `doc/models.md`, `doc/providers.md`, and `doc/services.md` in sync with model fields, provider persistence/load behavior, API/tool/plugin behavior, backup, or migrations.
- Keep `doc/pages.md` in sync when adding pages, routes, feature entries, or user-visible manual test paths.
