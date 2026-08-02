import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'outbound_http_client_factory.dart';
import 'outbound_network_policy.dart';

typedef OutboundHttpClientFactory = http.Client Function();

class OutboundHttpException implements Exception {
  const OutboundHttpException(this.message);

  final String message;

  @override
  String toString() => 'OutboundHttpException: $message';
}

class OutboundRequestCancelledException extends OutboundHttpException {
  const OutboundRequestCancelledException() : super('request cancelled');
}

class OutboundResponseTooLargeException extends OutboundHttpException {
  const OutboundResponseTooLargeException(this.maxBytes)
    : super('response exceeds $maxBytes bytes');

  final int maxBytes;
}

class BoundedOutboundResponse {
  const BoundedOutboundResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.uri,
  });

  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;
  final Uri uri;
}

/// Sends one bounded request with redirect revalidation and active cancellation.
class BoundedOutboundHttpClient {
  BoundedOutboundHttpClient({
    OutboundNetworkPolicy policy = const OutboundNetworkPolicy(),
    OutboundHttpClientFactory? clientFactory,
  }) : _policy = policy,
       _clientFactory = clientFactory;

  final OutboundNetworkPolicy _policy;
  final OutboundHttpClientFactory? _clientFactory;

  Future<BoundedOutboundResponse> send({
    required String method,
    required Uri uri,
    Map<String, String> headers = const {},
    List<int>? bodyBytes,
    int maxRequestBytes = 256 * 1024,
    int maxResponseBytes = 2 * 1024 * 1024,
    int maxRedirects = 3,
    Duration timeout = const Duration(seconds: 20),
    Future<void>? cancellation,
    Set<String> sensitiveHeaders = const {
      'authorization',
      'proxy-authorization',
      'x-api-key',
    },
  }) async {
    if (maxRequestBytes < 0 || maxResponseBytes < 0 || maxRedirects < 0) {
      throw ArgumentError('Outbound request limits must not be negative');
    }
    if ((bodyBytes?.length ?? 0) > maxRequestBytes) {
      throw OutboundHttpException('request exceeds $maxRequestBytes bytes');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }

    http.Client? activeClient;
    var cancelled = false;
    final cancellationFuture = cancellation?.then<Never>((_) {
      cancelled = true;
      activeClient?.close();
      throw const OutboundRequestCancelledException();
    });
    try {
      var currentUri = uri;
      var currentMethod = method.toUpperCase();
      var currentBody = bodyBytes;
      var currentHeaders = Map<String, String>.from(headers);
      for (var redirect = 0; ; redirect++) {
        final target = await _race(
          _policy.resolve(currentUri),
          cancellationFuture,
        );
        if (cancelled) throw const OutboundRequestCancelledException();
        final client =
            _clientFactory?.call() ?? createOutboundHttpClient(target.addresses);
        activeClient = client;
        final request = http.Request(currentMethod, currentUri)
          ..followRedirects = false
          ..headers.addAll(currentHeaders);
        if (currentBody != null) request.bodyBytes = currentBody;
        late final http.StreamedResponse response;
        try {
          response = await _race(
            client.send(request).timeout(timeout),
            cancellationFuture,
          );
        } catch (_) {
          client.close();
          if (identical(activeClient, client)) activeClient = null;
          rethrow;
        }
        if (!_isRedirect(response.statusCode)) {
          final contentLength = response.contentLength;
          if (contentLength != null && contentLength > maxResponseBytes) {
            await _race(response.stream.drain<void>(), cancellationFuture);
            throw OutboundResponseTooLargeException(maxResponseBytes);
          }
          final bytes = await _race(
            _readBounded(response, maxResponseBytes),
            cancellationFuture,
          );
          final result = BoundedOutboundResponse(
            statusCode: response.statusCode,
            headers: response.headers,
            bodyBytes: bytes,
            uri: currentUri,
          );
          client.close();
          if (identical(activeClient, client)) activeClient = null;
          return result;
        }
        final location = response.headers['location'];
        await _race(response.stream.drain<void>(), cancellationFuture);
        if (location == null || redirect >= maxRedirects) {
          throw const OutboundHttpException(
            'redirect is invalid or exceeds the limit',
          );
        }
        if (currentMethod != 'GET' && currentMethod != 'HEAD') {
          if (response.statusCode != 307 && response.statusCode != 308) {
            throw OutboundHttpException(
              '$currentMethod redirect must preserve the method',
            );
          }
        } else if (response.statusCode == 303) {
          currentMethod = 'GET';
          currentBody = null;
        }
        currentUri = currentUri.resolve(location);
        currentHeaders.removeWhere(
          (name, _) => sensitiveHeaders.contains(name.toLowerCase()),
        );
        client.close();
        if (identical(activeClient, client)) activeClient = null;
      }
    } finally {
      activeClient?.close();
    }
  }

  static Future<T> _race<T>(Future<T> operation, Future<Never>? cancellation) {
    if (cancellation == null) return operation;
    return Future.any<T>([operation, cancellation]);
  }

  static Future<Uint8List> _readBounded(
    http.StreamedResponse response,
    int maxBytes,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response.stream) {
      total += chunk.length;
      if (total > maxBytes) {
        throw OutboundResponseTooLargeException(maxBytes);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

bool _isRedirect(int status) =>
    status == 301 ||
    status == 302 ||
    status == 303 ||
    status == 307 ||
    status == 308;
