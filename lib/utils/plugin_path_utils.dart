import 'dart:io';

String? safePluginFilePath(String pluginRoot, String relativePath) {
  final trimmed = relativePath.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) return null;
  final normalized = trimmed.replaceAll('\\', '/');
  if (normalized.startsWith('/') ||
      RegExp(r'^[a-zA-Z]:/').hasMatch(normalized)) {
    return null;
  }
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList(growable: false);
  if (parts.isEmpty || parts.any((part) => part == '..')) return null;
  final root = Directory(pluginRoot).absolute.path.replaceAll('\\', '/');
  final path = '$root/${parts.join('/')}'.replaceAll('\\', '/');
  if (path == root || !path.startsWith('$root/')) return null;
  return path;
}

bool isSupportedPluginImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.svg');
}
