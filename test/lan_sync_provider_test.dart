import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/providers/lan_sync_provider.dart';

void main() {
  test('desired hosting waits for runtime readiness', () async {
    final host = _TestHost();
    final lifecycle = host.lifecycle();

    await lifecycle.setDesired(true);

    expect(host.starts, 0);
    expect(lifecycle.hosting, isFalse);

    await lifecycle.markReady();

    expect(host.starts, 1);
    expect(lifecycle.hosting, isTrue);
  });

  test('pause during a slow start stops after start completes', () async {
    final host = _TestHost(blockStart: true);
    final lifecycle = host.lifecycle();
    await lifecycle.markReady();

    final resume = lifecycle.setDesired(true);
    await host.startEntered.future;
    final pause = lifecycle.setDesired(false);

    expect(host.stops, 0);
    host.allowStart.complete();
    await Future.wait([resume, pause]);

    expect(host.starts, 1);
    expect(host.stops, 1);
    expect(lifecycle.hosting, isFalse);
  });

  test('rapid resume pause resume converges to hosting', () async {
    final host = _TestHost(blockStart: true);
    final lifecycle = host.lifecycle();
    await lifecycle.markReady();

    final firstResume = lifecycle.setDesired(true);
    await host.startEntered.future;
    final pause = lifecycle.setDesired(false);
    final finalResume = lifecycle.setDesired(true);
    host.allowStart.complete();
    await Future.wait([firstResume, pause, finalResume]);

    expect(host.starts, 1);
    expect(host.stops, 0);
    expect(lifecycle.desired, isTrue);
    expect(lifecycle.hosting, isTrue);
  });

  test('dataset suspension restores the prior desired hosting state', () async {
    final host = _TestHost();
    final lifecycle = host.lifecycle();
    await lifecycle.markReady();
    await lifecycle.setDesired(true);

    await lifecycle.suspend();

    expect(lifecycle.desired, isTrue);
    expect(lifecycle.hosting, isFalse);
    expect(host.stops, 1);

    await lifecycle.resume();

    expect(lifecycle.desired, isTrue);
    expect(lifecycle.hosting, isTrue);
    expect(host.starts, 2);
  });

  test('dataset suspension preserves a paused hosting preference', () async {
    final host = _TestHost();
    final lifecycle = host.lifecycle();
    await lifecycle.markReady();

    await lifecycle.suspend();
    await lifecycle.resume();

    expect(lifecycle.desired, isFalse);
    expect(lifecycle.hosting, isFalse);
    expect(host.starts, 0);
  });

  test('dispose close during start stops and prevents later restart', () async {
    final host = _TestHost(blockStart: true);
    final lifecycle = host.lifecycle();
    await lifecycle.markReady();

    final resume = lifecycle.setDesired(true);
    await host.startEntered.future;
    final close = lifecycle.close();
    host.allowStart.complete();
    await Future.wait([resume, close]);

    expect(host.starts, 1);
    expect(host.stops, 1);
    expect(host.closes, 1);
    expect(lifecycle.hosting, isFalse);

    await lifecycle.setDesired(true);
    await lifecycle.markReady();

    expect(host.starts, 1);
    expect(host.closes, 1);
  });
}

class _TestHost {
  _TestHost({this.blockStart = false});

  final bool blockStart;
  final Completer<void> startEntered = Completer<void>();
  final Completer<void> allowStart = Completer<void>();
  int starts = 0;
  int stops = 0;
  int closes = 0;

  LanHostingLifecycle lifecycle() => LanHostingLifecycle(
    start: () async {
      starts++;
      if (!startEntered.isCompleted) startEntered.complete();
      if (blockStart) await allowStart.future;
    },
    stop: () async {
      stops++;
    },
    close: () async {
      closes++;
    },
  );
}
