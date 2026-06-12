# Repository Instructions

## Commands
- Install deps before verification: `flutter pub get`.
- CI quality gate is `flutter pub get` -> `flutter analyze` -> `flutter test`.
- If deps are already current, use faster checks: `flutter analyze --no-pub` and `flutter test --no-pub`.
- Run one test file with `flutter test test/<name>_test.dart`; add `--plain-name '<test name>'` for a single test case.
- After changing Drift tables or database annotations in `lib/services/storage_v2_database.dart`, regenerate committed code with `dart run build_runner build --delete-conflicting-outputs`.
- Root analyzer excludes `third_party/**`; analyze vendored packages separately from their own package roots only when intentionally editing them.

## Architecture Boundaries
- `lib/main.dart` is the real app entrypoint: registers Providers, runs storage migration readiness, loads all data partitions, repairs model references, migrates legacy resource paths, then syncs built-in plugins.
- Keep the app layering strict: Pages handle UI, Providers own in-memory state and save queues, Repositories hide `storage_v2` vs legacy `SharedPreferences`, Services handle APIs/platform/files/migrations, Models only define serializable data contracts.
- Providers intentionally update memory and notify UI before queued persistence; do not make UI wait on disk writes unless the existing flow already does.
- Historical conversations and roleplay threads keep settings/model snapshots; global settings changes must not silently rewrite old sessions.
- `HomePage` keeps the three main tabs alive with an `IndexedStack`; avoid fixes that assume switching tabs disposes feature/chat/settings state.
- `HomePage` also owns root back handling and double-tap navigation: feature tab double-tap jumps to its dashboard, chat tab double-tap starts a new conversation.
- `ApiService` normalizes protocol differences into `StreamChunk`/`ChatResponse`; keep OpenAI/Ollama/Anthropic request quirks inside the service instead of scattering protocol handling into pages.
- `ChatPage` owns streaming UI, attachments, speech, screenshot export, tool-call loops, and model-recognition pre-send work; do not move protocol or device logic into widget helpers unless it stays page-local.
- Tool calls flow through `ToolCallService` and plugin tools through `PluginLuaRuntimeService`; add schema, validation, execution, permissions, and tests together.
- Roleplay uses scenario templates plus per-thread snapshots; deleting or changing a global role/model must repair references without rewriting old thread state.

## Storage And Data
- `storage_v2/app.db` is the structured source of truth; `storage_v2/data/*.json` is compatibility/debug/import mirror data, not the primary store.
- Notes in `storage_v2` store page bodies as Markdown files; `Note.content` is legacy compatibility and is not the only note body source.
- Long-lived attachments/resources must be copied into the app-private storage path and saved as paths/metadata, not embedded into message JSON.
- Storage-relative paths must go through the existing `StorageV2Service` safety checks; avoid manual path joins for user/plugin/archive-controlled paths.
- Migration constants live in code, especially `StorageMigrationService.currentSchemaVersion` and `BackupService.currentSchemaVersion`; do not duplicate schema numbers in docs.
- `StorageMigrationService` migrates legacy `SharedPreferences` JSON through a staging directory before activating `storage_v2`; preserve rollback behavior on migration failures.
- `LegacyResourceMigrationService` copies old private resource paths and updates Providers after startup; it intentionally does not delete old files.
- Backups are ZIPs with manifest, selected JSON partitions, note page Markdown, resources, and app-private assets; import must tolerate missing assets by warning and clearing invalid references.
- `ConversationProvider` saves through a debounced serial queue; flush pending saves on lifecycle/dispose paths instead of forcing synchronous writes from the UI.
- Schedule and tool-provided times are normalized to local time; avoid changing date parsing without focused schedule/tool tests.

## Generated And Vendored Code
- `lib/services/storage_v2_database.g.dart` is generated Drift code and is committed; update it only via build_runner after database source changes.
- `third_party/**` is excluded from root analyzer checks, but root `pubspec.yaml` overrides `webview_all_linux`, `webview_all_windows`, and `lua_dardo` to local vendored packages.
- `third_party/lua_dardo` is a LynAI fork with async Dart callback support used by Agent Lua; do not replace it with upstream assumptions.
- Native tree-sitter code lives under `native/tree_sitter/`; Dart uses FFI when available and falls back to stub/Dart highlighting on unsupported platforms.

## Plugins And Assets
- Built-in plugins live under `assets/plugins/status-dashboard/` and `assets/plugins/weather-query/`; keep their directories listed in `pubspec.yaml` assets when adding or moving plugin files.
- Plugin manifests enforce safe route/file identifiers and permission-gated tools/functions; update manifest parsing, runtime registration, permissions, and tests together.
- Feature-page plugin files can be user-editable only when declared in `editableFiles`; do not add generic plugin file writes that bypass this allowlist.
- Built-in plugins are synced on startup from Flutter assets into the app plugin directory; changing shipped plugin files affects both first install and sync of existing installs.
- Plugin WebView functions are not model tools; keep `functions`, `tools`, `skills`, feature pages, and permissions distinct when editing manifests or runtime registration.
- Plugin path handling should use existing safe path helpers; reject absolute paths, `..`, route-breaking IDs, and URLs where a local plugin file is expected.
- `PluginProvider` only tracks plugin metadata, enabled state, permissions, and manifest sync; the runtime executes Lua/WebView code elsewhere, and enabling/disabling must respect existing API-conflict checks.

## Tests And Platform Notes
- Tests commonly use `SharedPreferences.setMockInitialValues({})` and `Directory.systemTemp`; reset or isolate those when adding focused tests.
- Storage, plugin, migration, and attachment tests create temp directories and must clean them in `finally`; follow that pattern for new filesystem tests.
- Widget tests that instantiate `LynAIApp` need the same Provider set as `main.dart`; keep test provider registration in sync when adding global Providers.
- Linux release builds need native packages from CI (`cmake`, `clang`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `liblzma-dev`, `zstd`).
- macOS CI patches `speech_to_text` in the pub cache before `flutter build macos --release`; local macOS release failures may need the same workaround.
- CI builds Android APKs, Linux packages, Windows ZIPs, and macOS x64/arm64 artifacts only after the quality job passes.

## Documentation Sync
- Keep `doc/architecture.md` in sync with startup flow, storage authority, or layer boundary changes.
- Keep `doc/models.md`, `doc/providers.md`, and `doc/services.md` in sync when changing model fields, provider save/load behavior, API/tool/plugin behavior, backup, or migrations.
- Keep `doc/pages.md` in sync when adding pages, routes, feature entries, or user-visible manual test paths.
