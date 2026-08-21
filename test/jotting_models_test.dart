import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/jotting.dart';

void main() {
  group('Jotting.normalizeTags', () {
    test('trims lowercases deduplicates and drops empty tags', () {
      expect(
        Jotting.normalizeTags([' 灵感 ', 'INSPIRATION', '灵感', '', '  ']),
        ['灵感', 'inspiration'],
      );
    });

    test('caps tags at maxTagCount', () {
      final tags = List.generate(
        Jotting.maxTagCount + 5,
        (index) => 'tag$index',
      );
      expect(Jotting.normalizeTags(tags), hasLength(Jotting.maxTagCount));
    });

    test('drops tags longer than maxTagLength', () {
      expect(
        Jotting.normalizeTags(['ok', 'x' * (Jotting.maxTagLength + 1)]),
        ['ok'],
      );
    });
  });

  test('json roundtrip preserves fields', () {
    final createdAt = DateTime.utc(2026, 8, 16, 12, 30);
    final updatedAt = DateTime.utc(2026, 8, 16, 13);
    final jotting = Jotting(
      id: 'j1',
      content: '今天想到了一个点子\n\n第二段',
      tags: ['灵感', '生活'],
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

    final restored = Jotting.fromJson(jotting.toJson());

    expect(restored.id, 'j1');
    expect(restored.content, jotting.content);
    expect(restored.tags, ['灵感', '生活']);
    expect(restored.createdAt.toUtc(), createdAt);
    expect(restored.updatedAt.toUtc(), updatedAt);
  });

  test('fromJson tolerates missing or invalid tags', () {
    final jotting = Jotting.fromJson({
      'id': 'j2',
      'content': '正文',
      'createdAt': DateTime.utc(2026, 8, 16).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 8, 16).toIso8601String(),
    });
    expect(jotting.tags, isEmpty);

    final invalidTags = Jotting.fromJson({
      'id': 'j3',
      'content': '正文',
      'tags': 'not-a-list',
      'createdAt': DateTime.utc(2026, 8, 16).toIso8601String(),
      'updatedAt': DateTime.utc(2026, 8, 16).toIso8601String(),
    });
    expect(invalidTags.tags, isEmpty);
  });

  test('references and attachments roundtrip and tolerate invalid values', () {
    final createdAt = DateTime.utc(2026, 8, 16, 12);
    final jotting = Jotting(
      id: 'j4',
      content: '带引用和附件的随记',
      tags: const [],
      references: const [
        JottingReference(
          type: JottingReferenceType.note,
          id: 'n1',
          title: '笔记一',
          snippet: '摘要',
        ),
      ],
      attachments: const [
        JottingAttachment(
          resourceId: 'res_1',
          originalName: 'photo.png',
          mimeType: 'image/png',
        ),
      ],
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = Jotting.fromJson(jotting.toJson());
    expect(restored.references.single.id, 'n1');
    expect(restored.references.single.type, JottingReferenceType.note);
    expect(restored.attachments.single.resourceId, 'res_1');
    expect(restored.attachments.single.isImage, isTrue);

    final invalid = Jotting.fromJson({
      'id': 'j5',
      'content': '正文',
      'references': 'not-a-list',
      'attachments': 'not-a-list',
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': createdAt.toIso8601String(),
    });
    expect(invalid.references, isEmpty);
    expect(invalid.attachments, isEmpty);
  });
}
