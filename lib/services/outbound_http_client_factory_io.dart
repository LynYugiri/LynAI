import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createOutboundHttpClient(String? address) {
  if (address == null) return http.Client();
  final validatedAddress = InternetAddress(address);
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionFactory = (uri, proxyHost, proxyPort) =>
      Socket.startConnect(validatedAddress, uri.port);
  return IOClient(client);
}
