import 'dart:math' as math;
import 'dart:ui';

enum OcrTextOrientation { horizontal, vertical, unknown }

class OcrRecognitionResult {
  final int angle;
  final double imageWidth;
  final double imageHeight;
  final List<OcrTextBlock> blocks;

  const OcrRecognitionResult({
    required this.angle,
    required this.imageWidth,
    required this.imageHeight,
    required this.blocks,
  });

  bool get hasGeometry => blocks.any((block) => block.hasGeometry);

  String get text => blocks
      .map((block) => block.text.trim())
      .where((text) => text.isNotEmpty)
      .join('\n');

  factory OcrRecognitionResult.fromVivoJson(
    Map<String, dynamic> json, {
    required double imageWidth,
    required double imageHeight,
  }) {
    final result = json['result'] as Map<String, dynamic>?;
    final angle = _intValue(result?['angle']) ?? 0;
    final sourceBlocks = result?['OCR'] is List
        ? result!['OCR'] as List
        : result?['words'] is List
        ? result!['words'] as List
        : const [];
    final blocks = <OcrTextBlock>[];
    for (var index = 0; index < sourceBlocks.length; index++) {
      final raw = sourceBlocks[index];
      if (raw is! Map) continue;
      final block = OcrTextBlock.fromVivoJson(
        Map<String, dynamic>.from(raw),
        id: 'ocr_$index',
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        angle: angle,
      );
      if (block.text.isNotEmpty) blocks.add(block);
    }
    return OcrRecognitionResult(
      angle: angle,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      blocks: blocks,
    );
  }
}

class OcrTextBlock {
  final String id;
  final String text;
  final Rect? bounds;
  final List<Offset> polygon;
  final double? confidence;
  final OcrTextOrientation orientation;

  const OcrTextBlock({
    required this.id,
    required this.text,
    required this.bounds,
    required this.polygon,
    this.confidence,
    required this.orientation,
  });

  bool get hasGeometry => polygon.length >= 4 && bounds != null;

  factory OcrTextBlock.fromVivoJson(
    Map<String, dynamic> json, {
    required String id,
    required double imageWidth,
    required double imageHeight,
    int angle = 0,
  }) {
    final text = (json['words'] as String? ?? '').trim();
    final polygon = _parseVivoLocation(
      json['location'],
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      angle: angle,
    );
    return OcrTextBlock(
      id: id,
      text: text,
      bounds: polygon.isEmpty ? null : _boundsFor(polygon),
      polygon: polygon,
      confidence: _doubleValue(json['confidence'] ?? json['probability']),
      orientation: _orientationFor(polygon),
    );
  }

  static List<Offset> _parseVivoLocation(
    Object? raw, {
    required double imageWidth,
    required double imageHeight,
    required int angle,
  }) {
    if (raw is! Map) return const [];
    final map = Map<String, dynamic>.from(raw);
    final points = [
      _point(map['top_left'], imageWidth, imageHeight),
      _point(map['top_right'], imageWidth, imageHeight),
      _point(map['down_right'], imageWidth, imageHeight),
      _point(map['down_left'], imageWidth, imageHeight),
    ];
    if (points.any((point) => point == null)) return const [];
    return points
        .cast<Offset>()
        .map((point) => _rotateBack(point, angle, imageWidth, imageHeight))
        .toList(growable: false);
  }

  static Offset? _point(Object? raw, double imageWidth, double imageHeight) {
    if (raw is! Map) return null;
    final x = _doubleValue(raw['x']);
    final y = _doubleValue(raw['y']);
    if (x == null || y == null) return null;
    return Offset(_coordinate(x, imageWidth), _coordinate(y, imageHeight));
  }

  static double _coordinate(double value, double size) {
    if (value >= 0 && value <= 1) return value * size;
    if (value >= 0 && value <= 100) return value / 100 * size;
    return value;
  }

  static Offset _rotateBack(
    Offset point,
    int angle,
    double imageWidth,
    double imageHeight,
  ) {
    return switch (angle % 360) {
      90 => Offset(point.dy, imageWidth - point.dx),
      180 => Offset(imageWidth - point.dx, imageHeight - point.dy),
      270 => Offset(imageHeight - point.dy, point.dx),
      _ => point,
    };
  }

  static Rect _boundsFor(List<Offset> polygon) {
    var left = double.infinity;
    var top = double.infinity;
    var right = -double.infinity;
    var bottom = -double.infinity;
    for (final point in polygon) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static OcrTextOrientation _orientationFor(List<Offset> polygon) {
    if (polygon.length < 4) return OcrTextOrientation.unknown;
    final bounds = _boundsFor(polygon);
    if (bounds.height > bounds.width * 1.35) {
      return OcrTextOrientation.vertical;
    }
    if (bounds.width > bounds.height * 1.35) {
      return OcrTextOrientation.horizontal;
    }
    return OcrTextOrientation.unknown;
  }
}

double? _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}
