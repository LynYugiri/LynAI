import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/sync_change.dart';

final _pluginIdPattern = RegExp(r'^[a-zA-Z0-9_.-]+$');
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

const pluginSyncManifestVersion = 1;
const maxPluginSyncFiles = 1024;
const maxPluginSyncFileBytes = 16 * 1024 * 1024;
const maxPluginSyncPackageBytes = 64 * 1024 * 1024;

String pluginSyncPackageVersion(Iterable<Map<String, dynamic>> values) {
  final files =
      values
          .map(
            (value) => {
              'path': value['path'],
              'sha256': value['sha256'],
              'size': value['size'],
            },
          )
          .toList(growable: false)
        ..sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  return sha256.convert(utf8.encode(jsonEncode(files))).toString();
}

bool isValidPluginId(String value) =>
    value.isNotEmpty &&
    value != '.' &&
    value != '..' &&
    _pluginIdPattern.hasMatch(value);

void validatePluginSyncChange(SyncChange change) {
  if (!const {
    'plugin_files',
    'plugin_settings',
    'plugin_config',
  }.contains(change.table)) {
    return;
  }
  if (change.op == 'delete') {
    _validateDeleteIdentity(change.table, change.recordId);
    return;
  }
  if (change.op != 'upsert') {
    throw StateError('unsupported remote sync operation: ${change.op}');
  }
  final data = change.data;
  if (data == null || data['id'] != change.recordId) {
    throw StateError(
      'remote sync data.id does not match recordId: ${change.recordId}',
    );
  }
  final pluginId = data['pluginId'];
  if (pluginId is! String || !isValidPluginId(pluginId)) {
    throw StateError('remote plugin metadata has an invalid pluginId');
  }
  if (change.table == 'plugin_files') {
    _validateFileRow(change.recordId, pluginId, data);
    return;
  }
  _validateJsonRow(change.table, change.recordId, pluginId, data);
}

void _validateDeleteIdentity(String table, String recordId) {
  if (table != 'plugin_files') {
    if (!isValidPluginId(recordId)) {
      throw StateError('remote plugin metadata identity is invalid');
    }
    return;
  }
  if (isValidPluginId(recordId)) return;
  final separator = recordId.indexOf('/');
  if (separator <= 0) {
    throw StateError('remote plugin file metadata has an unsafe path');
  }
  final pluginId = recordId.substring(0, separator);
  final path = recordId.substring(separator + 1);
  if (!isValidPluginId(pluginId) ||
      !_isCanonicalSafePath(path) ||
      recordId != '$pluginId/$path') {
    throw StateError('remote plugin file metadata has an unsafe path');
  }
}

void _validateFileRow(
  String recordId,
  String pluginId,
  Map<String, dynamic> data,
) {
  final path = data['path'];
  final kind = data['kind'];
  final builtIn = data['builtIn'];
  if (path == null) {
    if (recordId != pluginId ||
        builtIn is! bool ||
        (kind != 'package' && kind != 'builtInOverlay') ||
        (kind == 'package') == builtIn ||
        data['manifestVersion'] != pluginSyncManifestVersion ||
        !const {'installed', 'deleted'}.contains(data['state']) ||
        data['files'] is! List ||
        data.containsKey('sha256') ||
        data.containsKey('size')) {
      throw StateError('remote plugin marker metadata is invalid');
    }
    final state = data['state'] as String;
    final files = data['files'] as List;
    if (state == 'deleted') {
      if (builtIn ||
          files.isNotEmpty ||
          data.containsKey('packageVersion') ||
          data.containsKey('pluginJsonSha256')) {
        throw StateError('remote plugin tombstone metadata is invalid');
      }
      return;
    }
    final packageVersion = data['packageVersion'];
    if (packageVersion is! String || !_sha256Pattern.hasMatch(packageVersion)) {
      throw StateError('remote plugin marker version is invalid');
    }
    if (!builtIn) {
      final pluginJsonSha256 = data['pluginJsonSha256'];
      if (pluginJsonSha256 is! String ||
          !_sha256Pattern.hasMatch(pluginJsonSha256)) {
        throw StateError('remote plugin marker is missing plugin.json hash');
      }
    } else if (data.containsKey('pluginJsonSha256')) {
      throw StateError('remote built-in overlay marker is invalid');
    }
    _validateManifestFiles(files, builtIn: builtIn);
    return;
  }
  if (path is! String ||
      !_isCanonicalSafePath(path) ||
      recordId != '$pluginId/$path' ||
      builtIn is! bool ||
      (kind != 'content' && kind != 'overlay') ||
      (kind == 'content') == builtIn ||
      data['packageVersion'] is! String ||
      !_sha256Pattern.hasMatch(data['packageVersion'] as String)) {
    throw StateError('remote plugin file metadata has an unsafe path');
  }
  _validateBlob(data);
}

void _validateManifestFiles(List files, {required bool builtIn}) {
  if (files.length > maxPluginSyncFiles) {
    throw StateError('remote plugin manifest has too many files');
  }
  final paths = <String>{};
  var totalSize = 0;
  for (final value in files) {
    if (value is! Map) {
      throw StateError('remote plugin manifest file metadata is invalid');
    }
    final file = Map<String, dynamic>.from(value);
    final path = file['path'];
    if (file.length != 3 ||
        path is! String ||
        !_isCanonicalSafePath(path) ||
        !paths.add(path)) {
      throw StateError('remote plugin manifest file path is invalid');
    }
    _validateBlob(file);
    final size = file['size'] as int;
    if (size > maxPluginSyncFileBytes) {
      throw StateError('remote plugin manifest file is too large');
    }
    totalSize += size;
    if (totalSize > maxPluginSyncPackageBytes) {
      throw StateError('remote plugin manifest package is too large');
    }
  }
  if (!builtIn && !paths.contains('plugin.json')) {
    throw StateError('remote plugin manifest does not allow plugin.json');
  }
}

void _validateJsonRow(
  String table,
  String recordId,
  String pluginId,
  Map<String, dynamic> data,
) {
  if (recordId != pluginId ||
      data['domain'] != table ||
      data['kind'] != table ||
      data.containsKey('path') ||
      data.containsKey('builtIn')) {
    throw StateError('remote plugin metadata identity is invalid');
  }
  _validateBlob(data);
}

void _validateBlob(Map<String, dynamic> data) {
  final hash = data['sha256'];
  final size = data['size'];
  if (hash is! String ||
      !_sha256Pattern.hasMatch(hash) ||
      size is! int ||
      size < 0 ||
      size > 64 * 1024 * 1024) {
    throw StateError('remote plugin metadata has invalid blob metadata');
  }
}

bool _isCanonicalSafePath(String path) {
  if (path.isEmpty ||
      path != path.trim() ||
      path.startsWith('/') ||
      path.startsWith('\\') ||
      path.contains('\\') ||
      path.contains('\u0000') ||
      RegExp(r'^[a-zA-Z]:').hasMatch(path) ||
      Uri.tryParse(path)?.hasScheme == true) {
    return false;
  }
  final segments = path.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}
