import 'dart:io';

import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// 为单个测试文件安装隔离的 path_provider fake。
Future<Directory> installFakePathProvider(
  String prefix, {
  String temporaryDirectoryName = 'tmp',
}) async {
  final root = await Directory.systemTemp.createTemp(prefix);
  PathProviderPlatform.instance = FakePathProviderPlatform(
    root,
    temporaryDirectoryName: temporaryDirectoryName,
  );
  return root;
}

/// 删除 [installFakePathProvider] 创建的根目录。
Future<void> deleteFakePathProviderRoot(Directory? root) async {
  if (root != null && await root.exists()) {
    await root.delete(recursive: true);
  }
}

/// 将所有系统目录映射到同一个测试根目录下，避免测试读写真实用户目录。
class FakePathProviderPlatform extends PathProviderPlatform {
  FakePathProviderPlatform(this.root, {this.temporaryDirectoryName = 'tmp'});

  final Directory root;
  final String temporaryDirectoryName;

  @override
  Future<String?> getTemporaryPath() => _path(temporaryDirectoryName);

  @override
  Future<String?> getApplicationSupportPath() => _path('support');

  @override
  Future<String?> getApplicationDocumentsPath() => _path('documents');

  @override
  Future<String?> getApplicationCachePath() => _path('cache');

  @override
  Future<String?> getDownloadsPath() => _path('downloads');

  Future<String> _path(String name) async {
    final directory = Directory('${root.path}/$name');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory.path;
  }
}
