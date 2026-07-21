import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/models/recycle_bin_item.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/conversation_repository.dart';
import 'package:lynai/repositories/model_config_repository.dart';
import 'package:lynai/repositories/recycle_bin_repository.dart';
import 'package:lynai/repositories/roleplay_repository.dart';
import 'package:lynai/repositories/settings_repository.dart';

class MemoryConversationRepository implements ConversationRepository {
  List<Conversation> _conversations = const [];

  @override
  Future<ConversationLoadResult> load() async {
    return ConversationLoadResult(
      conversations: List<Conversation>.from(_conversations),
      usingStorageV2: false,
    );
  }

  @override
  Future<void> save(
    List<Conversation> conversations, {
    required bool usingStorageV2,
  }) async {
    _conversations = List<Conversation>.from(conversations);
  }
}

class MemoryModelConfigRepository implements ModelConfigRepository {
  List<ModelConfig> _models = const [];
  Map<String, String> _pendingMigrations = const {};

  @override
  Future<ModelConfigLoadResult> load() async {
    return ModelConfigLoadResult(
      models: List<ModelConfig>.from(_models),
      usingStorageV2: false,
      pendingManagedModelIdMigrations: Map.of(_pendingMigrations),
    );
  }

  @override
  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
    Map<String, String> pendingManagedModelIdMigrations = const {},
  }) async {
    _models = List<ModelConfig>.from(models);
    _pendingMigrations = Map.of(pendingManagedModelIdMigrations);
  }
}

class MemorySettingsRepository implements SettingsRepository {
  AppSettings? _settings;

  AppSettings? get savedSettings => _settings;

  @override
  Future<SettingsLoadResult> load(AppSettings fallback) async {
    return SettingsLoadResult(
      settings: _settings ?? fallback,
      usingStorageV2: false,
    );
  }

  @override
  Future<void> save(
    AppSettings settings, {
    required bool usingStorageV2,
  }) async {
    _settings = settings;
  }
}

class MemoryRoleplayRepository implements RoleplayRepository {
  List<RoleplayScenario> _scenarios = const [];
  List<RoleplayThread> _threads = const [];

  @override
  Future<RoleplayLoadResult> load() async {
    return RoleplayLoadResult(
      scenarios: List<RoleplayScenario>.from(_scenarios),
      threads: List<RoleplayThread>.from(_threads),
      usingStorageV2: false,
    );
  }

  @override
  Future<void> save({
    required List<RoleplayScenario> scenarios,
    required List<RoleplayThread> threads,
    required bool usingStorageV2,
  }) async {
    _scenarios = List<RoleplayScenario>.from(scenarios);
    _threads = List<RoleplayThread>.from(threads);
  }
}

class MemoryRecycleBinRepository implements RecycleBinRepository {
  final List<RecycleBinItem> _items = [];

  @override
  Future<void> add(RecycleBinItem item) async {
    _items.removeWhere((existing) => existing.id == item.id);
    _items.add(item);
  }

  @override
  Future<List<RecycleBinItem>> load() async => List.of(_items);

  @override
  Future<void> remove(String id) async {
    _items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> save(List<RecycleBinItem> items) async {
    _items
      ..clear()
      ..addAll(items);
  }
}

ConversationProvider memoryConversationProvider() {
  return ConversationProvider(repository: MemoryConversationRepository());
}

ModelConfigProvider memoryModelConfigProvider() {
  return ModelConfigProvider(repository: MemoryModelConfigRepository());
}

SettingsProvider memorySettingsProvider() {
  return SettingsProvider(repository: MemorySettingsRepository());
}

RoleplayProvider memoryRoleplayProvider() {
  return RoleplayProvider(
    repository: MemoryRoleplayRepository(),
    recycleBinRepository: MemoryRecycleBinRepository(),
  );
}
