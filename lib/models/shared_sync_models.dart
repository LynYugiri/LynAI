import 'model_config.dart';

class SharedSettingsV1 {
  static const schemaVersion = 1;
  static const recordId = 'app-settings';

  final Map<String, dynamic> data;

  const SharedSettingsV1._(this.data);

  factory SharedSettingsV1.fromLocalJson(Map<String, dynamic> local) {
    final storage = local['storageV2'];
    final backgroundResourceId = storage is Map
        ? storage['backgroundResourceId'] as String?
        : null;
    return SharedSettingsV1._({
      'id': recordId,
      'schemaVersion': schemaVersion,
      'themeColor': local['themeColor'],
      'baseThemeColor': local['baseThemeColor'],
      'themeMode': local['themeMode'],
      'blurEnabled': local['blurEnabled'],
      'blurAmount': local['blurAmount'],
      'speechModelId': local['speechModelId'],
      'imageModelId': local['imageModelId'],
      'imageOcrEnabled': local['imageOcrEnabled'],
      'imageRecognitionModelId': local['imageRecognitionModelId'],
      'imageRecognitionEnabled': local['imageRecognitionEnabled'],
      'imageGenerationModelId': local['imageGenerationModelId'],
      'imageGenerationEnabled': local['imageGenerationEnabled'],
      'lastChatModelId': local['lastChatModelId'],
      'imageRecognitionPrompt': local['imageRecognitionPrompt'],
      'systemPrompt': local['systemPrompt'],
      'systemPrompts': local['systemPrompts'] ?? const [],
      'selectedSystemPromptId': local['selectedSystemPromptId'],
      'roles': local['roles'] ?? const [],
      'roleGroups': local['roleGroups'] ?? const [],
      'currentRoleId': local['currentRoleId'],
      if (backgroundResourceId != null && backgroundResourceId.isNotEmpty)
        'backgroundResourceId': backgroundResourceId,
    });
  }

  factory SharedSettingsV1.fromRemote(Map<String, dynamic> remote) {
    if (remote['id'] != recordId || remote['schemaVersion'] != schemaVersion) {
      throw const FormatException('unsupported shared settings schema');
    }
    return SharedSettingsV1._(Map<String, dynamic>.from(remote));
  }

  Map<String, dynamic> mergeIntoLocal(Map<String, dynamic> local) {
    final next = Map<String, dynamic>.from(local);
    for (final key in const [
      'themeColor',
      'baseThemeColor',
      'themeMode',
      'blurEnabled',
      'blurAmount',
      'speechModelId',
      'imageModelId',
      'imageOcrEnabled',
      'imageRecognitionModelId',
      'imageRecognitionEnabled',
      'imageGenerationModelId',
      'imageGenerationEnabled',
      'lastChatModelId',
      'imageRecognitionPrompt',
      'systemPrompt',
      'systemPrompts',
      'selectedSystemPromptId',
      'roles',
      'roleGroups',
      'currentRoleId',
    ]) {
      if (data.containsKey(key)) {
        next[key] = data[key];
      } else {
        next.remove(key);
      }
    }

    final storage = next['storageV2'] is Map
        ? Map<String, dynamic>.from(next['storageV2'] as Map)
        : <String, dynamic>{};
    final backgroundId = data['backgroundResourceId'] as String?;
    if (backgroundId == null || backgroundId.isEmpty) {
      storage.remove('backgroundResourceId');
    } else {
      storage['backgroundResourceId'] = backgroundId;
    }
    next.remove('backgroundImagePath');
    if (storage.isEmpty) {
      next.remove('storageV2');
    } else {
      next['storageV2'] = storage;
    }
    return next;
  }
}

class SyncedModelConfigV1 {
  static const schemaVersion = 1;

  final Map<String, dynamic> data;

  const SyncedModelConfigV1._(this.data);

  factory SyncedModelConfigV1.fromLocal(ModelConfig model) {
    if (model.managed || !model.cloudSyncEnabled) {
      throw ArgumentError('model is not eligible for cloud sync');
    }
    return SyncedModelConfigV1._({
      'id': model.id,
      'schemaVersion': schemaVersion,
      'name': model.name,
      'category': model.category,
      'endpoint': _nonSecretEndpoint(model.endpoint),
      'modelName': model.modelName,
      'apiType': model.apiType,
      'priority': model.priority,
      'models': model.models.map((entry) => entry.toJson()).toList(),
      if (model.maxTokens != null) 'maxTokens': model.maxTokens,
      if (model.temperature != null) 'temperature': model.temperature,
      if (model.topP != null) 'topP': model.topP,
      if (model.extraParams.isNotEmpty)
        'extraParams': _nonSecretParams(model.extraParams),
      'cloudSyncEnabled': true,
    });
  }

  factory SyncedModelConfigV1.fromRemote(Map<String, dynamic> remote) {
    final id = remote['id'] as String?;
    if (id == null || id.isEmpty || remote['schemaVersion'] != schemaVersion) {
      throw const FormatException('unsupported synced model schema');
    }
    if (remote.containsKey('apiKey') || remote.containsKey('apiKeySecretRef')) {
      throw const FormatException('synced model payload contains a secret');
    }
    return SyncedModelConfigV1._(Map<String, dynamic>.from(remote));
  }

  Map<String, dynamic> toLocalJson({Map<String, dynamic>? existing}) {
    final next = <String, dynamic>{
      'id': data['id'],
      'name': data['name'],
      'category': data['category'],
      'endpoint': _nonSecretEndpoint(data['endpoint'] as String? ?? ''),
      'modelName': data['modelName'],
      'apiType': data['apiType'],
      'priority': data['priority'],
      'models': data['models'] ?? const [],
      if (data.containsKey('maxTokens')) 'maxTokens': data['maxTokens'],
      if (data.containsKey('temperature')) 'temperature': data['temperature'],
      if (data.containsKey('topP')) 'topP': data['topP'],
      if (data['extraParams'] is Map)
        'extraParams': _nonSecretParams(
          Map<String, dynamic>.from(data['extraParams'] as Map),
        ),
      'cloudSyncEnabled': true,
    };
    final secretRef = existing?['apiKeySecretRef'];
    if (secretRef is String && secretRef.isNotEmpty) {
      next['apiKeySecretRef'] = secretRef;
    }
    return next;
  }

  static Map<String, dynamic> _nonSecretParams(Map<String, dynamic> params) {
    return {
      for (final entry in params.entries)
        if (!_secretKey.hasMatch(entry.key))
          entry.key: _sanitizeValue(entry.value),
    };
  }

  static dynamic _sanitizeValue(dynamic value) {
    if (value is Map) {
      return _nonSecretParams(Map<String, dynamic>.from(value));
    }
    if (value is List) return value.map(_sanitizeValue).toList();
    return value;
  }

  static String _nonSecretEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || uri.userInfo.isEmpty) return endpoint;
    return uri.replace(userInfo: '').toString();
  }

  static final RegExp _secretKey = RegExp(
    r'(api.?key|secret|token|password|credential|authorization|auth.?key)',
    caseSensitive: false,
  );
}
