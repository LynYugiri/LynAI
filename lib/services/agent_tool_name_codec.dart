import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/agent_runtime.dart';

typedef AgentToolNameDigest = List<int> Function(List<int> input);

class AgentToolNameCollisionException implements Exception {
  const AgentToolNameCollisionException(this.canonicalName);

  final String canonicalName;

  @override
  String toString() => 'Agent tool canonical name collision: $canonicalName';
}

class AgentToolNameCodec {
  static const reservedPrefixes = <String>[
    'builtin_',
    'mcp_',
    'plugin_',
    'runtime_',
    'system_',
  ];

  final int maxLength;
  final AgentToolNameDigest _digest;
  final Map<String, String> _canonicalByIdentity = {};
  final Map<String, String> _identityByCanonical = {};

  AgentToolNameCodec({this.maxLength = 64, AgentToolNameDigest? digest})
    : _digest = digest ?? ((input) => sha256.convert(input).bytes) {
    if (maxLength < 24) {
      throw ArgumentError.value(maxLength, 'maxLength', 'must be at least 24');
    }
  }

  String encode({
    required AgentToolSource source,
    required String namespace,
    required String name,
  }) {
    final identity = _frame([source.name, namespace, name]);
    final existing = _canonicalByIdentity[identity];
    if (existing != null) return existing;
    final encoded = base64Url.encode(utf8.encode(identity)).replaceAll('=', '');
    final readable = 'tool_v1_$encoded';
    if (readable.length <= maxLength && !_isReserved(readable)) {
      return _claim(identity, readable);
    }
    final hash = _hex(_digest(utf8.encode(identity)));
    final available = maxLength - 'tool_v1_h_'.length;
    final candidate =
        'tool_v1_h_${hash.substring(0, available.clamp(1, hash.length))}';
    final owner = _identityByCanonical[candidate];
    if (owner != null && owner != identity) {
      throw AgentToolNameCollisionException(candidate);
    }
    return _claim(identity, candidate);
  }

  String _claim(String identity, String canonical) {
    _canonicalByIdentity[identity] = canonical;
    _identityByCanonical[canonical] = identity;
    return canonical;
  }

  bool _isReserved(String value) =>
      reservedPrefixes.any((prefix) => value.startsWith(prefix));

  String _frame(List<String> values) =>
      values.map((value) => '${utf8.encode(value).length}:$value').join('|');

  String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
