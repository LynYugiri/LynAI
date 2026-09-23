import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_draft.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/services/composer_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _textOf(ComposerDraft draft) => draft.segments
    .whereType<ComposerTextSegment>()
    .map((segment) => segment.text)
    .join();

ComposerDraft _text(String text) =>
    ComposerDraft(segments: [ComposerTextSegment(text)]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('草稿按对话隔离，清空只影响当前对话', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', _text('会话 A 的内容'));
    drafts.saveDraft('b', _text('会话 B 的内容'));

    expect(_textOf(drafts.draftFor('a')), '会话 A 的内容');
    expect(_textOf(drafts.draftFor('b')), '会话 B 的内容');

    drafts.saveDraft('a', const ComposerDraft());
    expect(drafts.draftFor('a').isEmpty, isTrue);
    expect(_textOf(drafts.draftFor('b')), '会话 B 的内容');
    await drafts.flush();
  });

  test('尚未创建对话时使用独立槽位', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft(null, _text('还没发出去'));

    expect(_textOf(drafts.draftFor(null)), '还没发出去');
    expect(drafts.draftFor('a').isEmpty, isTrue);
    await drafts.flush();
  });

  test('引用 Chip 与正文一起暂存', () async {
    const reference = ComposerReference(
      localId: 'ref-1',
      type: ComposerReferenceType.note,
      id: 'note-1',
      title: '笔记一',
      subtitle: '开头',
      qualifiers: {'noteId': 'note-1'},
    );
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft(
      'a',
      const ComposerDraft(
        segments: [
          ComposerTextSegment('看下 '),
          ComposerReferenceSegment(reference),
        ],
      ),
    );
    await drafts.flush();

    final reloaded = ComposerDraftService();
    await reloaded.ensureLoaded();
    final draft = reloaded.draftFor('a');
    expect(draft.segments, hasLength(2));
    expect(_textOf(draft), '看下 ');
    final restored = draft.segments
        .whereType<ComposerReferenceSegment>()
        .single;
    expect(restored.reference.id, 'note-1');
    expect(restored.reference.title, '笔记一');
    expect(restored.reference.qualifiers['noteId'], 'note-1');
  });

  test('暂存附件随草稿一起保存', () async {
    const image = MessageImage(
      path: '/tmp/message_images/1_cat.png',
      name: 'cat.png',
      size: 2048,
      mimeType: 'image/png',
    );
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft(
      'a',
      const ComposerDraft(
        segments: [ComposerTextSegment('看看这张')],
        images: [image],
      ),
    );
    await drafts.flush();

    final reloaded = ComposerDraftService();
    await reloaded.ensureLoaded();
    final draft = reloaded.draftFor('a');
    expect(_textOf(draft), '看看这张');
    expect(draft.images, hasLength(1));
    expect(draft.images.single.path, '/tmp/message_images/1_cat.png');
    expect(draft.images.single.name, 'cat.png');
    expect(draft.images.single.size, 2048);
    expect(draft.images.single.mimeType, 'image/png');
  });

  test('只有附件也算草稿，删掉最后一个附件即清空', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft(
      'a',
      const ComposerDraft(
        images: [MessageImage(path: '/tmp/a.png', name: 'a.png', size: 1)],
      ),
    );
    expect(drafts.draftFor('a').isEmpty, isFalse);

    drafts.saveDraft('a', const ComposerDraft(images: []));
    expect(drafts.draftFor('a').isEmpty, isTrue);
    await drafts.flush();
  });

  test('新实例能恢复上一个进程写下的草稿', () async {
    final before = ComposerDraftService();
    await before.ensureLoaded();
    before.saveDraft('a', _text('未发送的内容'));
    await before.flush();

    // 模拟进程结束后重新打开应用。
    final after = ComposerDraftService();
    await after.ensureLoaded();
    expect(_textOf(after.draftFor('a')), '未发送的内容');
    expect(after.draftFor('b').isEmpty, isTrue);
  });

  test('落盘前也能读到内存中的最新草稿', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', _text('刚输入'));

    // 防抖窗口内不依赖落盘，页面切走时读到的仍是最新内容。
    expect(_textOf(drafts.draftFor('a')), '刚输入');
    await drafts.flush();
  });

  test('删除草稿后不再恢复', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', _text('待删除'));
    drafts.removeDraft('a');
    await drafts.flush();

    final reloaded = ComposerDraftService();
    await reloaded.ensureLoaded();
    expect(reloaded.draftFor('a').isEmpty, isTrue);
  });

  test('只存片段列表的旧草稿仍能读取', () async {
    // 键格式与旧值格式都是存储契约：改动必须同时迁移已写下的草稿。
    SharedPreferences.setMockInitialValues({
      'chat.composer_draft.v1.a': '[{"t":"text","v":"旧格式"}]',
    });
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();

    final draft = drafts.draftFor('a');
    expect(_textOf(draft), '旧格式');
    expect(draft.images, isEmpty);
  });

  test('损坏的草稿记录不会打断读取', () async {
    SharedPreferences.setMockInitialValues({
      'chat.composer_draft.v1.a': '{not json',
      'chat.composer_draft.v1.b': '{"segments":[{"t":"text","v":"正常"}]}',
    });
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();

    expect(drafts.draftFor('a').isEmpty, isTrue);
    expect(_textOf(drafts.draftFor('b')), '正常');
  });
}
