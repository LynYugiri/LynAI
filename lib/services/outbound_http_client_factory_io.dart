import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 每次地址连接尝试的最长耗时；单个地址失败后继续尝试下一地址。
const outboundConnectAttemptTimeout = Duration(seconds: 3);

/// 创建只连接 [addresses] 中已校验地址的 HTTP 客户端。
///
/// 连接按 IPv4 优先、IPv6 次之的顺序逐个尝试，全部失败时抛出最后一个
/// 连接错误；仍由 `HttpClient` 对原始 hostname 执行 HTTPS SNI 与证书校验，
/// 且显式绕过系统或环境代理。
http.Client createOutboundHttpClient(List<String> addresses) {
  final validated = addresses.map(InternetAddress.new).toList(growable: false);
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) =>
      _connectFirst(validated, uri.port);
  return IOClient(client);
}

Future<ConnectionTask<Socket>> _connectFirst(
  List<InternetAddress> addresses,
  int port,
) async {
  final ordered = [
    ...addresses.where((address) => address.type == InternetAddressType.IPv4),
    ...addresses.where((address) => address.type != InternetAddressType.IPv4),
  ];
  Object? lastError;
  for (final address in ordered) {
    ConnectionTask<Socket>? task;
    try {
      task = await Socket.startConnect(address, port);
      await task.socket.timeout(outboundConnectAttemptTimeout);
      return task;
    } catch (error) {
      task?.cancel();
      lastError = error;
    }
  }
  if (lastError != null) throw lastError;
  throw const SocketException('no resolved addresses to connect to');
}
