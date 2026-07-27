import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/mcp_config.dart';
import 'mcp_process.dart';
import 'mcp_protocol.dart';
import 'mcp_transport.dart';
import 'mcp_transport_secrets.dart';

McpTransport createMcpStdioTransport({
  required McpServerConfig config,
  required McpStdioEnvironment environment,
  McpProcessStarter? processStarter,
}) {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return _UnsupportedIoMcpStdioTransport();
  }
  return _McpStdioTransport(
    config: config,
    environment: environment,
    processStarter: processStarter ?? const _IoMcpProcessStarter(),
  );
}

class _UnsupportedIoMcpStdioTransport implements McpTransport {
  static const _error = McpTransportException(
    'MCP stdio is only supported on Linux, macOS, and Windows',
  );

  @override
  Stream<Map<String, dynamic>> get messages => const Stream.empty();

  @override
  Stream<McpTransportStatus> get statuses => const Stream.empty();

  @override
  McpTransportStatus get status => const McpTransportStatus(
    McpTransportState.failed,
    'Unsupported platform',
  );

  @override
  Future<void> start() => Future.error(_error);

  @override
  Future<void> send(Map<String, dynamic> message) => Future.error(_error);

  @override
  Future<void> dispose() async {}
}

class _McpStdioTransport implements McpTransport {
  final McpServerConfig config;
  final McpStdioEnvironment environment;
  final McpProcessStarter processStarter;
  final StreamController<Map<String, dynamic>> _messages =
      StreamController.broadcast();
  final StreamController<McpTransportStatus> _statuses =
      StreamController.broadcast();
  McpTransportStatus _status = const McpTransportStatus(McpTransportState.idle);
  McpProcess? _process;
  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<List<int>>? _stderrSubscription;
  final BytesBuilder _stdoutBuffer = BytesBuilder(copy: false);
  final BytesBuilder _stderrBuffer = BytesBuilder(copy: false);
  bool _disposed = false;

  _McpStdioTransport({
    required this.config,
    required this.environment,
    required this.processStarter,
  }) {
    if (config.transport != McpTransportKind.stdio) {
      throw ArgumentError('stdio transport requires a stdio config');
    }
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  @override
  Stream<McpTransportStatus> get statuses => _statuses.stream;

  @override
  McpTransportStatus get status => _status;

  @override
  Future<void> start() async {
    if (_status.state != McpTransportState.idle) return;
    _setStatus(McpTransportState.connecting);
    try {
      final process = await processStarter.start(
        config.command!,
        config.arguments,
        workingDirectory: config.workingDirectory,
        environment: environment.variables,
      );
      _process = process;
      _stdoutSubscription = process.stdout.listen(
        _handleStdout,
        onError: _handleStreamError,
        onDone: _flushStdout,
      );
      _stderrSubscription = process.stderr.listen(
        _handleStderr,
        onError: _handleStreamError,
      );
      unawaited(
        process.exitCode.then(_handleExit, onError: _handleStreamError),
      );
      _setStatus(McpTransportState.connected);
    } catch (error) {
      _setStatus(McpTransportState.failed, error.toString());
      rethrow;
    }
  }

  @override
  Future<void> send(Map<String, dynamic> message) async {
    if (_disposed || _process == null) {
      throw const McpTransportException('MCP stdio process is not running');
    }
    _process!.write([...encodeMcpMessage(message, config.maxMessageBytes), 10]);
  }

  void _handleStdout(List<int> chunk) {
    _stdoutBuffer.add(chunk);
    var bytes = _stdoutBuffer.takeBytes();
    var newline = bytes.indexOf(10);
    while (newline >= 0) {
      var line = Uint8List.sublistView(bytes, 0, newline);
      if (line.isNotEmpty && line.last == 13) {
        line = Uint8List.sublistView(line, 0, line.length - 1);
      }
      if (line.isNotEmpty) {
        _messages.add(decodeMcpMessage(line, config.maxMessageBytes));
      }
      bytes = Uint8List.sublistView(bytes, newline + 1);
      newline = bytes.indexOf(10);
    }
    if (bytes.length > config.maxMessageBytes) {
      _handleStreamError(
        McpTransportException(
          'MCP stdout message exceeds ${config.maxMessageBytes} bytes',
        ),
      );
      _process?.kill();
      return;
    }
    _stdoutBuffer.add(bytes);
  }

  void _flushStdout() {
    final bytes = _stdoutBuffer.takeBytes();
    if (bytes.isNotEmpty) {
      try {
        _messages.add(decodeMcpMessage(bytes, config.maxMessageBytes));
      } catch (error, stackTrace) {
        _messages.addError(error, stackTrace);
      }
    }
  }

  void _handleStderr(List<int> chunk) {
    final retained = _stderrBuffer.length;
    if (retained >= config.maxResponseBytes) return;
    final remaining = config.maxResponseBytes - retained;
    _stderrBuffer.add(
      chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
    );
  }

  void _handleStreamError(Object error, [StackTrace? stackTrace]) {
    if (_disposed) return;
    _setStatus(McpTransportState.failed, error.toString());
    _messages.addError(error, stackTrace ?? StackTrace.current);
  }

  void _handleExit(int exitCode) {
    if (_disposed) return;
    final stderr = utf8
        .decode(_stderrBuffer.takeBytes(), allowMalformed: true)
        .trim();
    final detail =
        'MCP stdio process exited with code $exitCode${stderr.isEmpty ? '' : ': $stderr'}';
    _setStatus(
      exitCode == 0 ? McpTransportState.degraded : McpTransportState.failed,
      detail,
    );
    _messages.addError(McpTransportException(detail));
  }

  void _setStatus(McpTransportState state, [String? detail]) {
    _status = McpTransportStatus(state, detail);
    _statuses.add(_status);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final process = _process;
    if (process != null) {
      await process.closeStdin();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill();
      }
    }
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _setStatus(McpTransportState.disposed);
    await _messages.close();
    await _statuses.close();
  }
}

class _IoMcpProcessStarter implements McpProcessStarter {
  const _IoMcpProcessStarter();

  @override
  Future<McpProcess> start(
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String> environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    return _IoMcpProcess(process);
  }
}

class _IoMcpProcess implements McpProcess {
  final Process process;

  const _IoMcpProcess(this.process);

  @override
  Stream<List<int>> get stdout => process.stdout;

  @override
  Stream<List<int>> get stderr => process.stderr;

  @override
  Future<int> get exitCode => process.exitCode;

  @override
  void write(List<int> bytes) => process.stdin.add(bytes);

  @override
  Future<void> closeStdin() => process.stdin.close();

  @override
  bool kill() => process.kill();
}
