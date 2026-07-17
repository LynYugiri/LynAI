import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../models/lan_peer.dart';
import 'lan_pairing_payload_codec.dart';

class LanMdnsService {
  static const serviceType = '_lynai._tcp';
  static const maxAddresses = 8;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final StreamController<List<LanDiscoveredPeer>> _controller =
      StreamController.broadcast();
  final Map<String, LanDiscoveredPeer> _peers = {};

  Stream<List<LanDiscoveredPeer>> get peers => _controller.stream;

  Future<void> advertise({
    required String displayName,
    required String deviceId,
    required int port,
    required int protocolVersion,
  }) async {
    if (!_validDeviceId(deviceId) ||
        !_validDisplayName(displayName) ||
        port < 1 ||
        port > 65535 ||
        protocolVersion != LanPairingPayloadCodec.protocolVersion) {
      throw const FormatException('invalid LAN advertisement');
    }
    await stopAdvertising();
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: displayName,
        type: serviceType,
        port: port,
        attributes: {'v': '$protocolVersion', 'id': deviceId},
      ),
      printLogs: false,
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> discover({String? localDeviceId}) async {
    await stopDiscovery();
    final discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
    await discovery.initialize();
    _subscription = discovery.eventStream!.listen((event) async {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent():
          await event.service.resolve(discovery.serviceResolver);
        case BonsoirDiscoveryServiceResolvedEvent():
          _upsert(event.service, localDeviceId);
        case BonsoirDiscoveryServiceUpdatedEvent():
          _upsert(event.service, localDeviceId);
        case BonsoirDiscoveryServiceLostEvent():
          final id = event.service.attributes['id'];
          if (id != null) {
            _peers.remove(id);
            _emit();
          }
        default:
          break;
      }
    });
    await discovery.start();
    _discovery = discovery;
  }

  void _upsert(BonsoirService service, String? localDeviceId) {
    final deviceId = service.attributes['id'];
    final version = int.tryParse(service.attributes['v'] ?? '');
    final addresses = validatedAddresses(service.hostAddresses);
    if (deviceId == null ||
        deviceId == localDeviceId ||
        !_validDeviceId(deviceId) ||
        !_validDisplayName(service.name) ||
        version == null ||
        version != LanPairingPayloadCodec.protocolVersion ||
        service.port <= 0 ||
        service.port > 65535 ||
        addresses.isEmpty) {
      return;
    }
    _peers[deviceId] = LanDiscoveredPeer(
      deviceId: deviceId,
      displayName: service.name,
      addresses: addresses,
      port: service.port,
      protocolVersion: version,
    );
    _emit();
  }

  void _emit() => _controller.add(List.unmodifiable(_peers.values));

  static List<String> validatedAddresses(Iterable<String> values) => values
      .where(LanPairingPayloadCodec.isAllowedLanAddress)
      .toSet()
      .take(maxAddresses)
      .toList(growable: false);

  static bool _validDeviceId(String value) =>
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value);

  static bool _validDisplayName(String value) =>
      value.trim().isNotEmpty && value.length <= 64 && !value.contains('\x00');

  Future<void> stopAdvertising() async {
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast != null && !broadcast.isStopped) await broadcast.stop();
  }

  Future<void> stopDiscovery() async {
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null && !discovery.isStopped) await discovery.stop();
    _peers.clear();
    _emit();
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    await _controller.close();
  }
}
