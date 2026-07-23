import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/floating_assistant_service.dart';

void main() {
  test('floating assistant channel parses safe numeric coordinates', () {
    expect(floatingAssistantChannelInt(12), 12);
    expect(floatingAssistantChannelInt(12.9), 12);
    expect(floatingAssistantChannelInt(-1), isNull);
    expect(floatingAssistantChannelInt(double.nan), isNull);
    expect(floatingAssistantChannelInt(double.infinity), isNull);
    expect(floatingAssistantChannelInt(1e30), isNull);
    expect(floatingAssistantChannelInt('12'), isNull);
  });

  test('floating assistant position debounce preserves earlier fields', () {
    const bubbleUpdate = (
      bubbleX: 10,
      bubbleY: 20,
      panelX: null,
      panelY: null,
      panelWidth: null,
      panelHeight: null,
    );
    const panelUpdate = (
      bubbleX: null,
      bubbleY: null,
      panelX: 30,
      panelY: 40,
      panelWidth: 360,
      panelHeight: 320,
    );

    final merged = mergeFloatingAssistantPosition(bubbleUpdate, panelUpdate);

    expect(merged.bubbleX, 10);
    expect(merged.bubbleY, 20);
    expect(merged.panelX, 30);
    expect(merged.panelY, 40);
    expect(merged.panelWidth, 360);
    expect(merged.panelHeight, 320);
  });
}
