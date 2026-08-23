import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/local_bluelm_prompt_codec.dart';

void main() {
  test('builds demo-format prompt and ends with assistant marker', () {
    final prompt = buildLocalBlueLmPrompt([
      {'role': 'user', 'content': '你好'},
    ]);

    expect(prompt, '[|Human|]:你好\n[|AI|]:');
  });

  test('flattens multi-turn history in order', () {
    final prompt = buildLocalBlueLmPrompt([
      {'role': 'user', 'content': '第一问'},
      {'role': 'assistant', 'content': '第一答'},
      {'role': 'user', 'content': '第二问'},
    ]);

    expect(prompt, '[|Human|]:第一问\n[|AI|]:第一答\n[|Human|]:第二问\n[|AI|]:');
  });

  test('folds system content into first human turn', () {
    final prompt = buildLocalBlueLmPrompt([
      {'role': 'system', 'content': '你是一个助手'},
      {'role': 'user', 'content': '你好'},
      {'role': 'assistant', 'content': '你好！'},
      {'role': 'user', 'content': '再见'},
    ]);

    expect(prompt, '[|Human|]:你是一个助手\n\n你好\n[|AI|]:你好！\n[|Human|]:再见\n[|AI|]:');
  });

  test('extracts text from list content and describes attachments', () {
    final prompt = buildLocalBlueLmPrompt([
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '看图'},
          {'type': 'input_file', 'name': 'photo.png'},
        ],
      },
    ]);

    expect(prompt, '[|Human|]:看图\n[附件: photo.png]\n[|AI|]:');
  });

  test('does not append assistant marker after assistant-only history', () {
    final prompt = buildLocalBlueLmPrompt([
      {'role': 'assistant', 'content': '已经完成'},
    ]);

    expect(prompt, '[|AI|]:已经完成');
  });
}
