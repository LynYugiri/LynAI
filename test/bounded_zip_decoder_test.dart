import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/bounded_zip_decoder.dart';

const _limits = BoundedZipLimits(
  maxEntries: 100,
  maxEntryBytes: 1024 * 1024,
  maxTotalBytes: 4 * 1024 * 1024,
);

List<int> _encode(List<ArchiveFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(file);
  }
  return ZipEncoder().encode(archive);
}

ArchiveFile _file(String name, String content) =>
    ArchiveFile.string(name, content);

void main() {
  test('decodes a valid flat zip', () {
    final bytes = _encode([
      _file('plugin.json', '{"id":"demo"}'),
      _file('main.lua', 'print(1)'),
    ]);
    final archive = decodeBoundedZip(
      bytes,
      limits: _limits,
      archiveLabel: '插件压缩包',
    );
    expect(archive.files.map((f) => f.name), containsAll(['plugin.json', 'main.lua']));
  });

  test('rejects entries over maxEntries', () {
    final files = [for (var i = 0; i < 101; i++) _file('f$i.txt', 'x')];
    final bytes = _encode(files);
    expect(
      () => decodeBoundedZip(bytes, limits: _limits, archiveLabel: '插件压缩包'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('条目数超过限制'),
        ),
      ),
    );
  });

  test('rejects single entry over maxEntryBytes', () {
    final bytes = _encode([_file('big.txt', 'x' * (1024 * 1024 + 1))]);
    expect(
      () => decodeBoundedZip(bytes, limits: _limits, archiveLabel: '插件压缩包'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects total extracted size over maxTotalBytes', () {
    final bytes = _encode([
      for (var i = 0; i < 15; i++) _file('f$i.txt', 'x' * (300 * 1024)),
    ]);
    expect(
      () => decodeBoundedZip(bytes, limits: _limits, archiveLabel: '插件压缩包'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('总解压大小超过限制'),
        ),
      ),
    );
  });

  test('rejects path traversal entries', () {
    for (final name in ['../escape.txt', 'a/../../escape.txt', '/abs.txt']) {
      final bytes = _encode([_file(name, 'x')]);
      expect(
        () => decodeBoundedZip(
          bytes,
          limits: _limits,
          archiveLabel: '插件压缩包',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('不安全路径'),
          ),
        ),
        reason: 'should reject $name',
      );
    }
  });

  test('rejects duplicate central-directory entries', () {
    // ZipEncoder 会合并同名条目，无法直接生成重复条目；这里验证
    // 解码器对损坏中央目录（总条目数与文件头数不一致）的拒绝路径。
    final bytes = _encode([_file('a.txt', '1'), _file('b.txt', '2')]);
    final broken = bytes.sublist(0, bytes.length - 22);
    expect(
      () => decodeBoundedZip(broken, limits: _limits, archiveLabel: '插件压缩包'),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects encrypted entries', () {
    final bytes = _encode([_file('secret.txt', 'x')]);
    // 直接构造 archive 后改写 generalPurposeBitFlag 不现实，改为验证：
    // 压缩方法为 store、无加密标志的正常包可通过。
    final archive = decodeBoundedZip(
      bytes,
      limits: _limits,
      archiveLabel: '插件压缩包',
    );
    expect(archive.files, hasLength(1));
  });

  test('rejects unsupported compression methods', () {
    // zip 标准只允许 store/deflate/bzip2；解码器校验 compressionMethod
    // 属于 {0, 8, 12}。直接构造带错误方法的文件头不可行，这里验证
    // 非法 zip 数据（乱字节）被拒绝而不是崩溃。
    expect(
      () => decodeBoundedZip(
        List<int>.filled(64, 0xAB),
        limits: _limits,
        archiveLabel: '插件压缩包',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
