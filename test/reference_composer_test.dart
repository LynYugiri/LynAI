import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/widgets/reference_composer.dart';

ComposerReference _note(String localId, String id, String title) {
  return ComposerReference(
    localId: localId,
    type: ComposerReferenceType.note,
    id: id,
    title: title,
  );
}

void main() {
  test('insertReference adds a chip with model and display projections', () {
    final ctrl = ReferenceComposerController();
    ctrl.text = '帮我总结';
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    ctrl.insertReference(_note('r1', 'note-1', '项目规划'));

    expect(ctrl.hasReferences, isTrue);
    expect(ctrl.references, hasLength(1));
    expect(ctrl.displayText, '帮我总结@项目规划');
    expect(
      ctrl.modelText,
      '帮我总结<lynai_ref type="note" id="note-1"/>',
    );
  });

  test('segments preserve text/reference interleaving order', () {
    final ctrl = ReferenceComposerController();
    ctrl.text = '比较 ';
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    ctrl.insertReference(_note('r1', 'a', 'A'));
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    ctrl.insertReference(_note('r2', 'b', 'B'));
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    ctrl.text = '${ctrl.text} 的差异';

    final segments = ctrl.segments;
    expect(segments.whereType<ComposerTextSegment>(), hasLength(2));
    expect(segments.whereType<ComposerReferenceSegment>(), hasLength(2));
    expect(
      segments.map((s) => s.runtimeType).toList(),
      [
        ComposerTextSegment,
        ComposerReferenceSegment,
        ComposerReferenceSegment,
        ComposerTextSegment,
      ],
    );
  });

  test('removeReference removes the chip by localId', () {
    final ctrl = ReferenceComposerController();
    ctrl.insertReference(_note('r1', 'a', 'A'));
    ctrl.insertReference(_note('r2', 'b', 'B'));

    ctrl.removeReference('r1');

    expect(ctrl.references.map((r) => r.id), ['b']);
  });

  test('deleting the placeholder char drops the reference atomically', () {
    final ctrl = ReferenceComposerController();
    ctrl.text = 'x';
    ctrl.insertReference(_note('r1', 'a', 'A'));
    // Simulate backspace deleting the single placeholder character.
    final raw = ctrl.text;
    ctrl.value = TextEditingValue(
      text: raw.substring(0, raw.length - 1),
      selection: TextSelection.collapsed(offset: raw.length - 1),
    );

    expect(ctrl.hasReferences, isFalse);
    expect(ctrl.references, isEmpty);
  });

  test('replaceSegments restores references from persisted segments', () {
    final ctrl = ReferenceComposerController();
    ctrl.replaceSegments([
      const ComposerTextSegment('总结 '),
      ComposerReferenceSegment(_note('r1', 'note-9', '灵感')),
    ]);

    expect(ctrl.hasReferences, isTrue);
    expect(ctrl.displayText, '总结 @灵感');
    expect(ctrl.modelText, '总结 <lynai_ref type="note" id="note-9"/>');
  });
}
