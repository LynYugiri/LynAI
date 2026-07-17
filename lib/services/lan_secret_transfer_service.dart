import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../models/model_config.dart';
import 'secret_store.dart';

class LanSecretTransferRequest {
  const LanSecretTransferRequest({
    required this.peerDeviceId,
    required this.transferId,
    required this.direction,
    required this.expiresAt,
  });

  final String peerDeviceId;
  final String transferId;
  final String direction;
  final DateTime expiresAt;
}

class LanSecretTransferService {
  LanSecretTransferService(this._secretStore, {this.onImported});

  static const grantValidity = Duration(minutes: 2);

  final SecretStore _secretStore;
  final Future<void> Function()? onImported;
  final Map<String, DateTime> _grants = {};
  final Map<String, LanSecretTransferRequest> _requests = {};
  final StreamController<List<LanSecretTransferRequest>> _requestController =
      StreamController.broadcast();

  Stream<List<LanSecretTransferRequest>> get requests =>
      _requestController.stream;

  String createTransferId() {
    final random = Random.secure();
    return base64UrlEncode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    ).replaceAll('=', '');
  }

  void authorize({
    required String peerDeviceId,
    required String transferId,
    required String direction,
    Duration validity = grantValidity,
    DateTime? now,
  }) {
    _validateAuthorization(peerDeviceId, transferId, direction, validity);
    _grants[_key(peerDeviceId, transferId, direction)] = (now ?? DateTime.now())
        .toUtc()
        .add(validity);
    _requests.remove(_key(peerDeviceId, transferId, direction));
    _emitRequests(now);
  }

  void addRequest({
    required String peerDeviceId,
    required String transferId,
    required String direction,
    Duration validity = grantValidity,
    DateTime? now,
  }) {
    _validateAuthorization(peerDeviceId, transferId, direction, validity);
    final request = LanSecretTransferRequest(
      peerDeviceId: peerDeviceId,
      transferId: transferId,
      direction: direction,
      expiresAt: (now ?? DateTime.now()).toUtc().add(validity),
    );
    _requests[_key(peerDeviceId, transferId, direction)] = request;
    _emitRequests(now);
  }

  bool hasAuthorization({
    required String peerDeviceId,
    required String transferId,
    required String direction,
    DateTime? now,
  }) {
    final expiry = _grants[_key(peerDeviceId, transferId, direction)];
    return expiry != null && expiry.isAfter((now ?? DateTime.now()).toUtc());
  }

  bool consumeAuthorization({
    required String peerDeviceId,
    required String transferId,
    required String direction,
    DateTime? now,
  }) {
    final key = _key(peerDeviceId, transferId, direction);
    final expiry = _grants.remove(key);
    return expiry != null && expiry.isAfter((now ?? DateTime.now()).toUtc());
  }

  Future<Map<String, dynamic>> exportPayload(
    Iterable<ModelConfig> models,
  ) async => {
    'modelApiKeys': {
      for (final model in models)
        if (!model.managed && model.apiKey.isNotEmpty) model.id: model.apiKey,
    },
  };

  Future<void> importPayload(Map<String, dynamic> payload) async {
    validatePayload(payload);
    final apiKeys = Map<String, dynamic>.from(payload['modelApiKeys'] as Map);
    for (final entry in apiKeys.entries) {
      await _secretStore.write(
        ModelConfig.secretReferenceForId(entry.key),
        entry.value as String,
      );
    }
    await onImported?.call();
  }

  void validatePayload(Map<String, dynamic> payload) {
    if (payload.length != 1 || payload['modelApiKeys'] is! Map) {
      throw const FormatException('invalid LAN secret payload type');
    }
    final apiKeys = Map<String, dynamic>.from(payload['modelApiKeys'] as Map);
    if (apiKeys.length > 128) {
      throw const FormatException('too many LAN model secrets');
    }
    for (final entry in apiKeys.entries) {
      if (!_validId(entry.key) ||
          entry.value is! String ||
          (entry.value as String).isEmpty ||
          (entry.value as String).length > 16 * 1024) {
        throw const FormatException('invalid LAN model secret');
      }
    }
  }

  void reject(LanSecretTransferRequest request) {
    _requests.remove(
      _key(request.peerDeviceId, request.transferId, request.direction),
    );
    _emitRequests();
  }

  void _validateAuthorization(
    String peerDeviceId,
    String transferId,
    String direction,
    Duration validity,
  ) {
    if (!_validId(peerDeviceId) ||
        !_validId(transferId) ||
        !const {'send', 'receive'}.contains(direction) ||
        validity <= Duration.zero ||
        validity > const Duration(minutes: 5)) {
      throw const FormatException('invalid LAN secret-transfer authorization');
    }
  }

  String _key(String peerDeviceId, String transferId, String direction) =>
      '$peerDeviceId\x00$transferId\x00$direction';

  void _emitRequests([DateTime? now]) {
    final clock = (now ?? DateTime.now()).toUtc();
    _requests.removeWhere((_, request) => !request.expiresAt.isAfter(clock));
    _requestController.add(List.unmodifiable(_requests.values));
  }

  static bool _validId(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);
}
