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
    expect(ctrl.modelText, '帮我总结<lynai_ref type="note" id="note-1"/>');
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
    expect(segments.map((s) => s.runtimeType).toList(), [
      ComposerTextSegment,
      ComposerReferenceSegment,
      ComposerReferenceSegment,
      ComposerTextSegment,
    ]);
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

  test('replaceRangeWithReference swaps the @query trigger for a chip', () {
    final ctrl = ReferenceComposerController();
    ctrl.text = '看看 @项目 的进度';
    ctrl.selection = const TextSelection.collapsed(offset: 6);

    ctrl.replaceRangeWithReference(3, 6, _note('r1', 'note-1', '项目规划'));

    expect(ctrl.text.contains('@'), isFalse);
    expect(ctrl.displayText, '看看 @项目规划 的进度');
    expect(ctrl.references.single.id, 'note-1');
    // Chip 只占一个私用区码点，因此光标停在 3 + 1 = 4，用户可以接着打字。
    expect(ctrl.selection.baseOffset, 4);
  });

  test('replaceRangeWithText eats a slash command or leaves inserted text', () {
    final runCtrl = ReferenceComposerController();
    runCtrl.text = '/压缩';
    runCtrl.selection = const TextSelection.collapsed(offset: 3);
    runCtrl.replaceRangeWithText(0, 3, '');
    expect(runCtrl.text, '');
    expect(runCtrl.selection.baseOffset, 0);

    final insertCtrl = ReferenceComposerController();
    insertCtrl.text = '/翻译 下面这段话';
    insertCtrl.selection = const TextSelection.collapsed(offset: 3);
    insertCtrl.replaceRangeWithText(0, 3, '把下面内容翻译成中文：');
    expect(insertCtrl.text, '把下面内容翻译成中文： 下面这段话');
  });

  test('replaceSelectionWithText powers the @ button without state', () {
    final ctrl = ReferenceComposerController();
    ctrl.text = '先说明再引用';
    ctrl.selection = const TextSelection.collapsed(offset: 2);
    ctrl.replaceSelectionWithText('@');
    expect(ctrl.text, '先说@明再引用');
    expect(ctrl.selection.baseOffset, 3);
  });

  test('folder-scope references render a distinguishing display title', () {
    final ctrl = ReferenceComposerController();
    ctrl.replaceSegments([
      const ComposerReferenceSegment(
        ComposerReference(
          localId: 'r1',
          type: ComposerReferenceType.note,
          id: 'folder-1',
          title: '工作',
          scope: ComposerReferenceScope.folder,
        ),
      ),
      const ComposerReferenceSegment(
        ComposerReference(
          localId: 'r2',
          type: ComposerReferenceType.conversation,
          id: 'conv-9',
          title: '上周排期',
        ),
      ),
    ]);

    expect(ctrl.displayText, '@工作（整个文件夹）@上周排期');
    expect(
      ctrl.modelText,
      '<lynai_ref type="note" id="folder-1" scope="folder"/>'
      '<lynai_ref type="conversation" id="conv-9"/>',
    );
  });
}
