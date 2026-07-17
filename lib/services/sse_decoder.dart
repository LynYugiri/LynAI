import 'dart:async';

/// A decoded Server-Sent Events event.
class SseEvent {
  final String? event;
  final String data;

  const SseEvent({this.event, required this.data});
}

/// Decodes text chunks into SSE events after UTF-8 decoding has completed.
class SseDecoder extends StreamTransformerBase<String, SseEvent> {
  const SseDecoder();

  @override
  Stream<SseEvent> bind(Stream<String> stream) async* {
    var buffer = '';
    String? eventName;
    final dataLines = <String>[];

    SseEvent? dispatch() {
      if (dataLines.isEmpty) {
        eventName = null;
        return null;
      }
      final event = SseEvent(event: eventName, data: dataLines.join('\n'));
      eventName = null;
      dataLines.clear();
      return event;
    }

    SseEvent? processLine(String line) {
      if (line.isEmpty) return dispatch();
      if (line.startsWith(':')) return null;

      final separator = line.indexOf(':');
      final field = separator == -1 ? line : line.substring(0, separator);
      var value = separator == -1 ? '' : line.substring(separator + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          eventName = value;
          return null;
        case 'data':
          dataLines.add(value);
          return null;
      }
      return null;
    }

    await for (final chunk in stream) {
      buffer += chunk;
      while (true) {
        final cr = buffer.indexOf('\r');
        final lf = buffer.indexOf('\n');
        final newline = cr == -1
            ? lf
            : lf == -1
            ? cr
            : cr < lf
            ? cr
            : lf;
        if (newline == -1 ||
            (buffer.codeUnitAt(newline) == 13 &&
                newline == buffer.length - 1)) {
          break;
        }
        final event = processLine(buffer.substring(0, newline));
        final terminatorLength =
            buffer.codeUnitAt(newline) == 13 &&
                buffer.codeUnitAt(newline + 1) == 10
            ? 2
            : 1;
        buffer = buffer.substring(newline + terminatorLength);
        if (event != null) yield event;
      }
    }

    if (buffer.endsWith('\r')) {
      final event = processLine(buffer.substring(0, buffer.length - 1));
      buffer = '';
      if (event != null) yield event;
    }
    if (buffer.isNotEmpty) {
      final event = processLine(buffer);
      if (event != null) yield event;
    }
    final finalEvent = dispatch();
    if (finalEvent != null) yield finalEvent;
  }
}
