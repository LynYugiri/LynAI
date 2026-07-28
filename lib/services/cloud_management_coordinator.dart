import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../models/cloud_data.dart';
import '../repositories/cloud_data_repository.dart';
import 'cloud_data_service.dart';

abstract class CloudManagementOperations {
  Future<List<CloudManagementOperation>> discover(
    String scope, {
    required bool remoteSupported,
  });

  Future<void> acknowledge(
    String scope,
    Iterable<CloudManagementOperation> operations, {
    required bool operationAckSupported,
    required Future<bool> Function(CloudManagementOperation operation)
    canAcknowledge,
  });

  Future<CloudCurrentProjection> currentProjection({
    required bool indexSupported,
  });
}

class CloudManagementCoordinator implements CloudManagementOperations {
  CloudManagementCoordinator({
    required CloudDataRepository repository,
    required CloudDataService service,
  }) : _repository = repository,
       _service = service;

  final CloudDataRepository _repository;
  final CloudDataService _service;

  @override
  Future<List<CloudManagementOperation>> discover(
    String scope, {
    required bool remoteSupported,
  }) async {
    if (remoteSupported) {
      final remote = await _service.getOperations();
      await _repository.reconcileOperations(scope, remote);
    }
    final operations = await _repository.loadOperations(scope);
    if (operations.isNotEmpty) {
      final generation = operations
          .map((operation) => operation.generation)
          .reduce((a, b) => a > b ? a : b);
      await _repository.requireFullReseed(scope, generation);
    }
    return operations;
  }

  @override
  Future<void> acknowledge(
    String scope,
    Iterable<CloudManagementOperation> operations, {
    required bool operationAckSupported,
    required Future<bool> Function(CloudManagementOperation operation)
    canAcknowledge,
  }) async {
    final pending = operations.toList(growable: false);
    if (pending.isEmpty || !operationAckSupported) return;
    final generation = pending
        .map((operation) => operation.generation)
        .reduce((a, b) => a > b ? a : b);
    final latest = pending.firstWhere(
      (operation) => operation.generation == generation,
    );
    if (!await canAcknowledge(latest)) {
      throw StateError('同步 scope 或 generation 已变化，未确认云端操作');
    }
    for (final operation in pending) {
      final requestId = requestIdForAck(scope, operation, generation);
      await _service.acknowledgeOperation(
        operation.id,
        generation,
        requestId,
        includeOperationId: true,
      );
      await _repository.removeOperation(scope, operation.id);
    }
  }

  @override
  Future<CloudCurrentProjection> currentProjection({
    required bool indexSupported,
  }) {
    if (!indexSupported) throw StateError('服务端不支持云端索引 reseed');
    return _service.getCurrentProjection();
  }

  static String requestIdForAck(
    String scope,
    CloudManagementOperation operation, [
    int? currentGeneration,
  ]) => base64UrlEncode(
    sha256
        .convert(
          utf8.encode(
            'cloud-operation-ack\n$scope\n${operation.id}\n${currentGeneration ?? operation.generation}',
          ),
        )
        .bytes
        .sublist(0, 24),
  ).replaceAll('=', '');
}
