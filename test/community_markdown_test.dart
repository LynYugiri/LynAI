import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/widgets/community_post_card.dart';

void main() {
  test('community markdown removes remote images and dangerous links', () {
    final sanitized = sanitizeCommunityMarkdown(
      '![track](https://example.test/pixel.png) '
      '[safe](https://example.test) '
      '[bad](javascript:alert(1)) <script>alert(1)</script>',
    );

    expect(sanitized, contains('[图片: track]'));
    expect(sanitized, contains('[safe](https://example.test)'));
    expect(sanitized, isNot(contains('javascript:')));
    expect(sanitized, isNot(contains('<script>')));
  });
}
