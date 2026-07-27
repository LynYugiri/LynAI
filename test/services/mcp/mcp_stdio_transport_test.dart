import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/mcp_config.dart';
import 'package:lynai/services/mcp/mcp_process.dart';
import 'package:lynai/services/mcp/mcp_stdio_transport.dart';
import 'package:lynai/services/mcp/mcp_transport_secrets.dart';

void main() {
  test(
    'stdio uses explicit environment, exchanges line-delimited messages, and disposes',
    () async {
      final process = _FakeProcess();
      final starter = _FakeStarter(process);
      final transport = createMcpStdioTransport(
        config: McpServerConfig.stdio(
          id: 'local',
          displayName: 'Local',
          command: 'server',
          arguments: const ['--mcp'],
        ),
        environment: McpStdioEnvironment(variables: {'TOKEN': 'secret'}),
        processStarter: starter,
      );
      await transport.start();
      final received = expectLater(
        transport.messages,
        emits(predicate<Map<String, dynamic>>((message) => message['id'] == 1)),
      );
      process.stdoutController.add(
        utf8.encode('{"jsonrpc":"2.0","id":1,"result":{}}\n'),
      );
      await received;
      await transport.send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      expect(utf8.decode(process.writes.single), endsWith('\n'));
      expect(starter.environment, {'TOKEN': 'secret'});
      await transport.dispose();
      expect(process.stdinClosed, isTrue);
    },
  );
}

class _FakeStarter implements McpProcessStarter {
  final _FakeProcess process;
  Map<String, String>? environment;

  _FakeStarter(this.process);

  @override
  Future<McpProcess> start(
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String> environment,
  }) async {
    this.environment = environment;
    return process;
  }
}

class _FakeProcess implements McpProcess {
  final stdoutController = StreamController<List<int>>();
  final stderrController = StreamController<List<int>>();
  final exitCompleter = Completer<int>();
  final List<List<int>> writes = [];
  bool stdinClosed = false;

  @override
  Stream<List<int>> get stdout => stdoutController.stream;

  @override
  Stream<List<int>> get stderr => stderrController.stream;

  @override
  Future<int> get exitCode => exitCompleter.future;

  @override
  void write(List<int> bytes) => writes.add(bytes);

  @override
  Future<void> closeStdin() async {
    stdinClosed = true;
    if (!exitCompleter.isCompleted) exitCompleter.complete(0);
    await stdoutController.close();
    await stderrController.close();
  }

  @override
  bool kill() {
    if (!exitCompleter.isCompleted) exitCompleter.complete(-1);
    return true;
  }
}
