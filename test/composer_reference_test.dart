import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/models/composer_reference.dart';

void main() {
  test('codec encodes only type and id for a note', () {
    final encoded = ComposerReferenceCodec.encode(
      const ComposerReference(
        localId: 'draft-1',
        type: ComposerReferenceType.note,
        id: 'note-123',
        title: '项目规划',
        subtitle: '本周需要完成版本发布准备',
      ),
    );
    expect(encoded, '<lynai_ref type="note" id="note-123"/>');
    expect(encoded, isNot(contains('项目规划')));
    expect(encoded, isNot(contains('版本发布')));
  });

  test('codec encodes qualifiers for note page and plugin resource', () {
    expect(
      ComposerReferenceCodec.encode(
        const ComposerReference(
          localId: 'draft-2',
          type: ComposerReferenceType.notePage,
          id: 'page-1',
          title: 'Page',
          qualifiers: {'note_id': 'note-123'},
        ),
      ),
      '<lynai_ref type="note_page" id="page-1" note_id="note-123"/>',
    );
    expect(
      ComposerReferenceCodec.encode(
        const ComposerReference(
          localId: 'draft-3',
          type: ComposerReferenceType.pluginResource,
          id: 'city:beijing',
          title: '北京',
          qualifiers: {'plugin_id': 'weather-query'},
        ),
      ),
      '<lynai_ref type="plugin_resource" id="city:beijing" '
      'plugin_id="weather-query"/>',
    );
  });

  test('codec escapes special characters in id', () {
    final encoded = ComposerReferenceCodec.encode(
      const ComposerReference(
        localId: 'draft-4',
        type: ComposerReferenceType.task,
        id: 'a<b>&"c',
        title: 'Task',
      ),
    );
    expect(encoded, contains('id="a&lt;b&gt;&amp;&quot;c"'));
  });

  test('codec decodes back to type and id', () {
    final decoded = ComposerReferenceCodec.decode(
      '<lynai_ref type="note_page" id="page-1" note_id="note-123"/>',
    );
    expect(decoded, isNotNull);
    expect(decoded!.type, ComposerReferenceType.notePage);
    expect(decoded.id, 'page-1');
    expect(decoded.qualifiers, {'note_id': 'note-123'});
  });

  test('segment serialization round-trips', () {
    final segments = <ComposerSegment>[
      const ComposerTextSegment('请总结 '),
      const ComposerReferenceSegment(
        ComposerReference(
          localId: 'draft-1',
          type: ComposerReferenceType.note,
          id: 'note-123',
          title: '项目规划',
        ),
      ),
      const ComposerTextSegment(' 并列出风险。'),
    ];
    final restored = decodeComposerSegments(encodeComposerSegments(segments));
    expect(restored, hasLength(3));
    expect((restored[0] as ComposerTextSegment).text, '请总结 ');
    expect(
      (restored[1] as ComposerReferenceSegment).reference.id,
      'note-123',
    );
    expect((restored[2] as ComposerTextSegment).text, ' 并列出风险。');
  });
}
