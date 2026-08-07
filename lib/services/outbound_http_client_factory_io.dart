import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 每次地址连接尝试的最长耗时；单个地址失败后继续尝试下一地址。
const outboundConnectAttemptTimeout = Duration(seconds: 3);

/// 创建只连接 [addresses] 中已校验地址的 HTTP 客户端。
///
/// 连接按 IPv4 优先、IPv6 次之的顺序逐个尝试，TCP 连接与 HTTPS 握手各自
/// 受 [outboundConnectAttemptTimeout] 约束，全部失败时抛出最后一个连接
/// 错误。HTTPS 目标由连接工厂在直连 socket 上以原始 hostname 完成 TLS
/// 握手（SNI 与证书校验），并显式绕过系统或环境代理。[onBadCertificate]
/// 覆盖默认证书校验行为（默认拒绝），仅供测试或显式信任场景使用。
http.Client createOutboundHttpClient(
  List<String> addresses, {
  bool Function(X509Certificate certificate)? onBadCertificate,
}) {
  final validated = addresses.map(InternetAddress.new).toList(growable: false);
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) =>
      _connectFirst(validated, uri, onBadCertificate: onBadCertificate);
  return IOClient(client);
}

Future<ConnectionTask<Socket>> _connectFirst(
  List<InternetAddress> addresses,
  Uri uri, {
  bool Function(X509Certificate certificate)? onBadCertificate,
}) async {
  final ordered = [
    ...addresses.where((address) => address.type == InternetAddressType.IPv4),
    ...addresses.where((address) => address.type != InternetAddressType.IPv4),
  ];
  Object? lastError;
  for (final address in ordered) {
    ConnectionTask<Socket>? task;
    Socket? socket;
    try {
      task = await Socket.startConnect(address, uri.port);
      socket = await task.socket.timeout(outboundConnectAttemptTimeout);
      final Socket connected = uri.scheme == 'https'
          ? await SecureSocket.secure(
              socket,
              host: uri.host,
              onBadCertificate: onBadCertificate,
            ).timeout(outboundConnectAttemptTimeout)
          : socket;
      return ConnectionTask.fromSocket<Socket>(
        Future.value(connected),
        connected.destroy,
      );
    } catch (error) {
      task?.cancel();
      socket?.destroy();
      lastError = error;
    }
  }
  if (lastError != null) throw lastError;
  throw const SocketException('no resolved addresses to connect to');
}
