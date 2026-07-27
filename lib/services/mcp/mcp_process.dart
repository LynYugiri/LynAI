abstract interface class McpProcess {
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;

  void write(List<int> bytes);
  Future<void> closeStdin();
  bool kill();
}

abstract interface class McpProcessStarter {
  Future<McpProcess> start(
    String executable,
    List<String> arguments, {
    required String? workingDirectory,
    required Map<String, String> environment,
  });
}
