import 'package:http/http.dart' as http;

import 'outbound_http_client_factory_stub.dart'
    if (dart.library.io) 'outbound_http_client_factory_io.dart'
    as implementation;

http.Client createOutboundHttpClient(List<String> addresses) =>
    implementation.createOutboundHttpClient(addresses);
