String safeStorageFileName(String name, {String fallback = 'file'}) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').trim();
  return safe.isEmpty ? fallback : safe;
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
