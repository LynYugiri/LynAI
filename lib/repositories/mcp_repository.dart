import 'dart:convert';

import '../models/agent_persistence.dart';
import '../repositories/agent_persistence_repository.dart';
import '../services/secret_store.dart';

class McpServerPreferences {
  const McpServerPreferences({
    this.allowHttp = false,
    this.allowPrivateNetwork = false,
    this.enabledTools = const {},
    this.credentialTargets = const {},
  });

  final bool allowHttp;
  final bool allowPrivateNetwork;
  final Map<String, bool> enabledTools;
  final Map<String, String> credentialTargets;
}

abstract interface class McpRepository {
  Future<List<AgentMcpServerRecord>> loadServers();

  Future<void> saveServer(AgentMcpServerRecord server);

  Future<McpServerPreferences> loadPreferences(String serverId);

  Future<void> savePreferences(
    String serverId,
    McpServerPreferences preferences,
  );

  Future<Map<String, String>> loadCredentials(
    String serverId,
    Iterable<String> names,
  );

  Future<void> saveCredentials(
    String serverId,
    Map<String, String> values,
    Iterable<String> removedNames,
  );
}

class PersistentMcpRepository implements McpRepository {
  PersistentMcpRepository({
    required AgentPersistenceRepository persistence,
    required SecretStore secretStore,
  }) : _persistence = persistence,
       _secretStore = secretStore;

  final AgentPersistenceRepository _persistence;
  final SecretStore _secretStore;

  @override
  Future<List<AgentMcpServerRecord>> loadServers() =>
      _persistence.loadMcpServers();

  @override
  Future<void> saveServer(AgentMcpServerRecord server) =>
      _persistence.saveMcpServer(server);

  @override
  Future<McpServerPreferences> loadPreferences(String serverId) async {
    final value = await _secretStore.read(_preferencesKey(serverId));
    if (value == null) return const McpServerPreferences();
    try {
      final json = jsonDecode(value);
      if (json is! Map) return const McpServerPreferences();
      final tools = json['enabledTools'];
      return McpServerPreferences(
        allowHttp: json['allowHttp'] == true,
        allowPrivateNetwork: json['allowPrivateNetwork'] == true,
        enabledTools: tools is Map
            ? tools.map(
                (key, value) => MapEntry(key.toString(), value != false),
              )
            : const {},
        credentialTargets: json['credentialTargets'] is Map
            ? (json['credentialTargets'] as Map).map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
            : const {},
      );
    } catch (_) {
      return const McpServerPreferences();
    }
  }

  @override
  Future<void> savePreferences(
    String serverId,
    McpServerPreferences preferences,
  ) {
    return _secretStore.write(
      _preferencesKey(serverId),
      jsonEncode({
        'allowHttp': preferences.allowHttp,
        'allowPrivateNetwork': preferences.allowPrivateNetwork,
        'enabledTools': preferences.enabledTools,
        'credentialTargets': preferences.credentialTargets,
      }),
    );
  }

  @override
  Future<Map<String, String>> loadCredentials(
    String serverId,
    Iterable<String> names,
  ) async {
    final values = <String, String>{};
    for (final name in names) {
      final value = await _secretStore.read(_credentialKey(serverId, name));
      if (value != null) values[name] = value;
    }
    return values;
  }

  @override
  Future<void> saveCredentials(
    String serverId,
    Map<String, String> values,
    Iterable<String> removedNames,
  ) async {
    for (final entry in values.entries) {
      if (entry.value.isEmpty) {
        await _secretStore.delete(_credentialKey(serverId, entry.key));
      } else {
        await _secretStore.write(
          _credentialKey(serverId, entry.key),
          entry.value,
        );
      }
    }
    for (final name in removedNames) {
      await _secretStore.delete(_credentialKey(serverId, name));
    }
  }

  static String _preferencesKey(String serverId) =>
      'mcp.server.${Uri.encodeComponent(serverId)}.preferences';

  static String _credentialKey(String serverId, String name) =>
      'mcp.server.${Uri.encodeComponent(serverId)}.credential.${Uri.encodeComponent(name)}';
}
