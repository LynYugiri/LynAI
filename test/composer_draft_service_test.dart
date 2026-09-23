import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/services/composer_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _textOf(List<ComposerSegment> segments) => segments
    .whereType<ComposerTextSegment>()
    .map((segment) => segment.text)
    .join();

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('草稿按对话隔离，清空只影响当前对话', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', const [ComposerTextSegment('会话 A 的内容')]);
    drafts.saveDraft('b', const [ComposerTextSegment('会话 B 的内容')]);

    expect(_textOf(drafts.draftFor('a')), '会话 A 的内容');
    expect(_textOf(drafts.draftFor('b')), '会话 B 的内容');

    drafts.saveDraft('a', const []);
    expect(drafts.draftFor('a'), isEmpty);
    expect(_textOf(drafts.draftFor('b')), '会话 B 的内容');
    await drafts.flush();
  });

  test('尚未创建对话时使用独立槽位', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft(null, const [ComposerTextSegment('还没发出去')]);

    expect(_textOf(drafts.draftFor(null)), '还没发出去');
    expect(drafts.draftFor('a'), isEmpty);
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
    drafts.saveDraft('a', const [
      ComposerTextSegment('看下 '),
      ComposerReferenceSegment(reference),
    ]);
    await drafts.flush();

    final reloaded = ComposerDraftService();
    await reloaded.ensureLoaded();
    final segments = reloaded.draftFor('a');
    expect(segments, hasLength(2));
    expect(_textOf(segments), '看下 ');
    final restored = segments.whereType<ComposerReferenceSegment>().single;
    expect(restored.reference.id, 'note-1');
    expect(restored.reference.title, '笔记一');
    expect(restored.reference.qualifiers['noteId'], 'note-1');
  });

  test('新实例能恢复上一个进程写下的草稿', () async {
    final before = ComposerDraftService();
    await before.ensureLoaded();
    before.saveDraft('a', const [ComposerTextSegment('未发送的内容')]);
    await before.flush();

    // 模拟进程结束后重新打开应用。
    final after = ComposerDraftService();
    await after.ensureLoaded();
    expect(_textOf(after.draftFor('a')), '未发送的内容');
    expect(_textOf(after.draftFor('b')), isEmpty);
  });

  test('落盘前也能读到内存中的最新草稿', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', const [ComposerTextSegment('刚输入')]);

    // 防抖窗口内不依赖落盘，页面切走时读到的仍是最新内容。
    expect(_textOf(drafts.draftFor('a')), '刚输入');
    await drafts.flush();
  });

  test('删除草稿后不再恢复', () async {
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();
    drafts.saveDraft('a', const [ComposerTextSegment('待删除')]);
    drafts.removeDraft('a');
    await drafts.flush();

    final reloaded = ComposerDraftService();
    await reloaded.ensureLoaded();
    expect(reloaded.draftFor('a'), isEmpty);
  });

  test('损坏的草稿记录不会打断读取', () async {
    // 键格式是存储契约：改动前缀必须同时迁移旧草稿。
    SharedPreferences.setMockInitialValues({
      'chat.composer_draft.v1.a': '{not json',
      'chat.composer_draft.v1.b': '[{"t":"text","v":"正常"}]',
    });
    final drafts = ComposerDraftService();
    await drafts.ensureLoaded();

    expect(drafts.draftFor('a'), isEmpty);
    expect(_textOf(drafts.draftFor('b')), '正常');
  });
}
