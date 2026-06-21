import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/conversation_repository.dart';
import 'package:lynai/repositories/model_config_repository.dart';
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

  @override
  Future<ModelConfigLoadResult> load() async {
    return ModelConfigLoadResult(
      models: List<ModelConfig>.from(_models),
      usingStorageV2: false,
    );
  }

  @override
  Future<void> save(
    List<ModelConfig> models, {
    required bool usingStorageV2,
  }) async {
    _models = List<ModelConfig>.from(models);
  }
}

class MemorySettingsRepository implements SettingsRepository {
  AppSettings? _settings;

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

ConversationProvider memoryConversationProvider() {
  return ConversationProvider(repository: MemoryConversationRepository());
}

ModelConfigProvider memoryModelConfigProvider() {
  return ModelConfigProvider(repository: MemoryModelConfigRepository());
}

SettingsProvider memorySettingsProvider() {
  return SettingsProvider(repository: MemorySettingsRepository());
}
