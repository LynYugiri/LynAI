import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../services/backend_uri.dart';

enum PhysicalDatasetKind { local, account }

class PhysicalDatasetIdentity {
  const PhysicalDatasetIdentity._({
    required this.id,
    required this.kind,
    this.backendOrigin,
    this.userId,
  });

  static const localId = 'local';

  const PhysicalDatasetIdentity.local()
    : this._(id: localId, kind: PhysicalDatasetKind.local);

  factory PhysicalDatasetIdentity.account({
    required String backendUrl,
    required String userId,
  }) {
    final origin = normalizedBackendOrigin(backendUrl);
    if (origin.isEmpty) throw ArgumentError('Invalid backend origin');
    if (userId.isEmpty || userId.contains('\u0000')) {
      throw ArgumentError('Invalid opaque account user ID');
    }
    final digest = sha256
        .convert(utf8.encode('$origin\u0000$userId'))
        .toString();
    return PhysicalDatasetIdentity._(
      id: digest,
      kind: PhysicalDatasetKind.account,
      backendOrigin: origin,
      userId: userId,
    );
  }

  factory PhysicalDatasetIdentity.fromJson(Map<String, dynamic> json) {
    final kind = PhysicalDatasetKind.values.byName(json['kind'] as String);
    final identity = kind == PhysicalDatasetKind.local
        ? const PhysicalDatasetIdentity.local()
        : PhysicalDatasetIdentity.account(
            backendUrl: json['backendOrigin'] as String,
            userId: json['userId'] as String,
          );
    if (json['id'] != identity.id) {
      throw const FormatException('Dataset identity hash does not match');
    }
    return identity;
  }

  final String id;
  final PhysicalDatasetKind kind;
  final String? backendOrigin;
  final String? userId;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (backendOrigin != null) 'backendOrigin': backendOrigin,
    if (userId != null) 'userId': userId,
  };
}
