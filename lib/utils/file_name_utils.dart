import 'dart:convert';

import 'package:crypto/crypto.dart';

String safeStorageFileName(String name, {String fallback = 'file'}) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
  if (safe.isEmpty || safe == '.' || safe == '..') return fallback;
  return safe;
}

String safeStorageSegment(String value, {String fallback = 'item'}) {
  final hash = sha256.convert(utf8.encode(value)).toString().substring(0, 8);
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').trim();
  final segment = safe.isEmpty || safe == '_' ? fallback : safe;
  return '${segment}_$hash';
}

String safeExportFileName(String name, {String fallback = 'export'}) {
  final safe = name
      .replaceAll(RegExp(r'[\x00-\x1F\x7F\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (safe.isEmpty || safe == '.' || safe == '..') return fallback;

  final baseName = safe.split('.').first.toUpperCase();
  const reservedNames = {
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };
  return reservedNames.contains(baseName) ? fallback : safe;
}
