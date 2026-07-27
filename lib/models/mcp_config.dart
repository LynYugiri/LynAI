enum McpTransportKind { streamableHttp, stdio }

class McpServerConfig {
  final String id;
  final String displayName;
  final McpTransportKind transport;
  final Uri? endpoint;
  final String? command;
  final List<String> arguments;
  final String? workingDirectory;
  final bool allowHttp;
  final bool allowPrivateNetwork;
  final bool enableSseNotifications;
  final Duration requestTimeout;
  final int maxMessageBytes;
  final int maxResponseBytes;

  McpServerConfig.streamableHttp({
    required this.id,
    required this.displayName,
    required Uri endpoint,
    this.allowHttp = false,
    this.allowPrivateNetwork = false,
    this.enableSseNotifications = true,
    this.requestTimeout = const Duration(seconds: 30),
    this.maxMessageBytes = 1024 * 1024,
    this.maxResponseBytes = 4 * 1024 * 1024,
  }) : transport = McpTransportKind.streamableHttp,
       endpoint = endpoint,
       command = null,
       arguments = const [],
       workingDirectory = null {
    _validateCommon();
    if (endpoint.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'must not contain credentials',
      );
    }
    if (endpoint.scheme != 'https' &&
        !(allowHttp && endpoint.scheme == 'http')) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'must use HTTPS unless HTTP is explicitly allowed',
      );
    }
    if (!allowPrivateNetwork && _isPrivateHost(endpoint.host)) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'private network endpoints require explicit allowance',
      );
    }
  }

  McpServerConfig.stdio({
    required this.id,
    required this.displayName,
    required String command,
    this.arguments = const [],
    this.workingDirectory,
    this.requestTimeout = const Duration(seconds: 30),
    this.maxMessageBytes = 1024 * 1024,
    this.maxResponseBytes = 4 * 1024 * 1024,
  }) : transport = McpTransportKind.stdio,
       command = command,
       endpoint = null,
       allowHttp = false,
       allowPrivateNetwork = false,
       enableSseNotifications = false {
    _validateCommon();
    if (command.trim().isEmpty) {
      throw ArgumentError.value(command, 'command', 'must not be empty');
    }
  }

  void _validateCommon() {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (displayName.trim().isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'must not be empty',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(
        requestTimeout,
        'requestTimeout',
        'must be positive',
      );
    }
    if (maxMessageBytes < 1 || maxResponseBytes < maxMessageBytes) {
      throw ArgumentError(
        'MCP byte limits must be positive and response limit must cover one message',
      );
    }
  }
}

bool _isPrivateHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized == '::1' ||
      normalized.startsWith('fc') ||
      normalized.startsWith('fd') ||
      normalized.startsWith('fe8') ||
      normalized.startsWith('fe9') ||
      normalized.startsWith('fea') ||
      normalized.startsWith('feb') ||
      normalized.endsWith('.local')) {
    return true;
  }
  final parts = normalized.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      first == 127 ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168);
}
