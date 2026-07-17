import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/plugin_market_entry.dart';
import 'package:lynai/repositories/plugin_repository.dart';
import 'package:lynai/services/market_plugin_package.dart';

void main() {
  List<int> pluginZip(String id) {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string('plugin.json', jsonEncode({'id': id, 'name': id})),
      );
    return ZipEncoder().encode(archive);
  }

  MarketPluginEntry entry(String id, {String? hash}) => MarketPluginEntry(
    id: id,
    name: id,
    author: '',
    description: '',
    version: '1.0.0',
    downloadUrl: '/download',
    sha256: hash,
  );

  test('accepts matching SHA-256 and manifest ID', () {
    final bytes = pluginZip('safe-plugin');
    expect(
      () => validateMarketPluginPackage(
        bytes,
        entry('safe-plugin', hash: sha256.convert(bytes).toString()),
      ),
      returnsNormally,
    );
  });

  test('rejects mismatched SHA-256 before installation', () {
    final bytes = pluginZip('safe-plugin');
    expect(
      () => validateMarketPluginPackage(
        bytes,
        entry('safe-plugin', hash: '0' * 64),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects input over the repository ZIP limit before decoding', () {
    expect(
      () => validateMarketPluginPackage(
        List<int>.filled(PluginRepository.maxPluginZipInputBytes + 1, 0),
        entry('safe-plugin'),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('32 MiB'),
        ),
      ),
    );
  });

  test('rejects mismatched manifest ID before installation', () {
    expect(
      () => validateMarketPluginPackage(
        pluginZip('other-plugin'),
        entry('safe-plugin'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a nested manifest alongside the root manifest', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'plugin.json',
          jsonEncode({'id': 'safe-plugin', 'name': 'Safe'}),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'nested/plugin.json',
          jsonEncode({'id': 'other-plugin', 'name': 'Other'}),
        ),
      );

    expect(
      () => validateMarketPluginPackage(
        ZipEncoder().encode(archive),
        entry('safe-plugin'),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
