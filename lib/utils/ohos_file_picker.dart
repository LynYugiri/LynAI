import 'package:flutter/services.dart';

import 'platform_info.dart';

/// 鸿蒙上的文件选择桥接。
///
/// 工程使用的 `file_picker 11.x` 没有鸿蒙实现，社区鸿蒙分支是 API 不兼容的
/// `file_picker 12.x`；因此鸿蒙改走自有通道 `lynai/file_picker`
/// （原生实现见 `ohos/entry/src/main/ets/lynai/LynaiFilePicker.ets`），
/// 上层 `utils/file_picker_io_utils.dart` 据此产出与 file_picker 相同的
/// [OhosPickedFile] 结构，调用方无需感知平台差异。
class OhosFilePicker {
  OhosFilePicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('lynai/file_picker');

  final MethodChannel _channel;

  /// 当前平台是否需要走鸿蒙实现。
  static bool get isSupported => isOhosPlatform;

  /// 打开系统选择器；用户取消时返回空列表。
  ///
  /// [type] 取 `any` 或 `image`，[allowedExtensions] 用于文件选择器的后缀过滤
  /// （不带点，例如 `pdf`）。单个文件读取失败时抛出 [PlatformException]。
  Future<List<OhosPickedFile>> pickFiles({
    String type = 'any',
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>('pickFiles', {
      'type': type,
      'allowedExtensions': allowedExtensions ?? const <String>[],
      'allowMultiple': allowMultiple,
    });
    _throwIfFailed(response, '选择文件失败');
    final files = response?['files'];
    if (files is! List) return const [];
    return files
        .whereType<Map>()
        .map(
          (entry) => OhosPickedFile(
            name: entry['name'] as String? ?? '未命名文件',
            path: entry['path'] as String?,
            size: (entry['size'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((file) => file.path != null)
        .toList(growable: false);
  }

  /// 另存为；用户取消或失败时返回 null，成功时返回沙箱内的副本路径。
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final response = await _channel.invokeMapMethod<String, dynamic>('saveFile', {
      'fileName': fileName,
      'bytes': bytes,
    });
    _throwIfFailed(response, '保存文件失败');
    return response?['path'] as String?;
  }

  void _throwIfFailed(Map<String, dynamic>? response, String fallback) {
    if (response == null) {
      throw PlatformException(code: 'no_response', message: fallback);
    }
    if (response['ok'] != true) {
      throw PlatformException(
        code: 'ohos_file_picker_failed',
        message: response['error'] as String? ?? fallback,
      );
    }
  }
}

/// 鸿蒙选择器返回的单个文件；[path] 一定是应用沙箱内的真实路径。
class OhosPickedFile {
  const OhosPickedFile({required this.name, required this.path, required this.size});

  final String name;
  final String? path;
  final int size;
}
