import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/widgets/chat_composer_keyboard.dart';

void main() {
  ChatComposerEnterAction resolve({
    TargetPlatform platform = TargetPlatform.linux,
    bool control = false,
    bool meta = false,
    bool shift = false,
    bool alt = false,
    bool composing = false,
  }) => resolveChatComposerEnterAction(
    platform: platform,
    controlPressed: control,
    metaPressed: meta,
    shiftPressed: shift,
    altPressed: alt,
    composing: composing,
  );

  test('desktop bare Enter sends and Shift+Enter inserts newline', () {
    expect(resolve(), ChatComposerEnterAction.send);
    expect(resolve(shift: true), ChatComposerEnterAction.newline);
  });

  test('mobile bare Enter inserts newline', () {
    expect(
      resolve(platform: TargetPlatform.android),
      ChatComposerEnterAction.newline,
    );
    expect(
      resolve(platform: TargetPlatform.iOS),
      ChatComposerEnterAction.newline,
    );
  });

  test('Ctrl+Enter and Meta+Enter send on every platform', () {
    for (final platform in TargetPlatform.values) {
      expect(
        resolve(platform: platform, control: true),
        ChatComposerEnterAction.send,
      );
      expect(
        resolve(platform: platform, meta: true),
        ChatComposerEnterAction.send,
      );
    }
  });

  test('Alt+Enter and composing Enter never send', () {
    expect(resolve(alt: true), ChatComposerEnterAction.newline);
    expect(resolve(control: true, alt: true), ChatComposerEnterAction.newline);
    expect(resolve(composing: true), ChatComposerEnterAction.newline);
    expect(
      resolve(control: true, composing: true),
      ChatComposerEnterAction.newline,
    );
  });
}
