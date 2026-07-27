import 'dart:io';

Future<List<String>> resolveMcpHost(String host) async =>
    (await InternetAddress.lookup(
      host,
    )).map((address) => address.address).toList(growable: false);
