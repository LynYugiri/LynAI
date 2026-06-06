import 'dart:io';

/// 将插件根目录内的相对路径安全解析为绝对文件路径。
///
/// 组件只使用相对路径（相对于插件根目录）。此函数做了多层安全检查：
/// - 拒绝空路径和包含 URI scheme 的路径
/// - 拒绝绝对路径（以 `/` 或盘符开头）
/// - 拒绝包含 `..` 的路径穿越攻击
/// - 拒绝解析后不在插件根目录内的路径
/// - 将 Windows 反斜杠统一转换为正斜杠
///
/// 返回 null 表示路径不安全或无效。
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

/// 判断文件路径是否为插件支持的图片格式。
///
/// 支持格式：PNG、JPG、JPEG、WebP、SVG。
bool isSupportedPluginImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.svg');
}
