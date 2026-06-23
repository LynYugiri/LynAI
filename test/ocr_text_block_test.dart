import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/ocr_text_block.dart';

void main() {
  test('parses vivo OCR absolute coordinates', () {
    final result = OcrRecognitionResult.fromVivoJson(
      {
        'result': {
          'angle': 0,
          'OCR': [
            {
              'words': '编辑',
              'location': {
                'top_left': {'x': 398.0, 'y': 825.0},
                'top_right': {'x': 1912.0, 'y': 825.0},
                'down_left': {'x': 398.0, 'y': 1004.0},
                'down_right': {'x': 1912.0, 'y': 1004.0},
              },
            },
          ],
        },
      },
      imageWidth: 2400,
      imageHeight: 1200,
    );

    expect(result.text, '编辑');
    expect(result.hasGeometry, isTrue);
    expect(
      result.blocks.single.bounds,
      const Rect.fromLTRB(398, 825, 1912, 1004),
    );
    expect(result.blocks.single.orientation, OcrTextOrientation.horizontal);
  });

  test('normalizes vivo OCR percent coordinates', () {
    final result = OcrRecognitionResult.fromVivoJson(
      {
        'result': {
          'angle': 0,
          'OCR': [
            {
              'words': '取消',
              'location': {
                'top_left': {'x': 10, 'y': 20},
                'top_right': {'x': 20, 'y': 20},
                'down_left': {'x': 10, 'y': 60},
                'down_right': {'x': 20, 'y': 60},
              },
            },
          ],
        },
      },
      imageWidth: 1000,
      imageHeight: 2000,
    );

    expect(
      result.blocks.single.bounds,
      const Rect.fromLTRB(100, 400, 200, 1200),
    );
    expect(result.blocks.single.orientation, OcrTextOrientation.vertical);
  });

  test('keeps text-only OCR responses without geometry', () {
    final result = OcrRecognitionResult.fromVivoJson(
      {
        'result': {
          'angle': 0,
          'words': [
            {'words': '取消'},
            {'words': '编辑'},
          ],
        },
      },
      imageWidth: 1000,
      imageHeight: 2000,
    );

    expect(result.text, '取消\n编辑');
    expect(result.hasGeometry, isFalse);
    expect(result.blocks.every((block) => block.bounds == null), isTrue);
  });
}
