import 'dart:io';

import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart' as zxing;

import '../providers/lan_sync_provider.dart';
import '../services/lan_pairing_payload_codec.dart';

class LanSyncPage extends StatefulWidget {
  const LanSyncPage({super.key});

  @override
  State<LanSyncPage> createState() => _LanSyncPageState();
}

class _LanSyncPageState extends State<LanSyncPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final provider = context.read<LanSyncProvider>();
      provider.confirmPairing = _confirmPairing;
      provider.initialize();
      provider.startDiscovery();
    });
  }

  Future<bool> _confirmPairing(String displayName, String fingerprint) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('确认设备指纹'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('设备: $displayName'),
                const SizedBox(height: 12),
                SelectableText(
                  fingerprint,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                const Text('请在另一台设备上核对完全相同的指纹后再确认。'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('指纹一致'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LanSyncProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('局域网配对与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('点对点连接', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    '无需云账户。配对码由设备 Ed25519 身份签名，连接使用 TLS 1.3 和证书 SPKI 固定。双方必须确认设备指纹；配对成功后会自动激活局域网同步并执行首次双向同步。',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: provider.busy ? null : _showQr,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('显示配对码'),
                      ),
                      OutlinedButton.icon(
                        onPressed: provider.busy ? null : _scanOrImport,
                        icon: Icon(
                          Platform.isAndroid || Platform.isIOS
                              ? Icons.qr_code_scanner
                              : Icons.image_search,
                        ),
                        label: Text(
                          Platform.isAndroid || Platform.isIOS
                              ? '扫描配对码'
                              : '导入配对码图片',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: provider.busy
                            ? null
                            : provider.startDiscovery,
                        icon: const Icon(Icons.radar),
                        label: const Text('发现设备'),
                      ),
                    ],
                  ),
                  if (provider.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      provider.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (provider.notice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      provider.notice!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('已发现', style: Theme.of(context).textTheme.titleMedium),
          if (provider.discoveredPeers.isEmpty)
            const ListTile(
              leading: Icon(Icons.wifi_find),
              title: Text('暂未发现 LynAI 设备'),
              subtitle: Text('请确认设备位于同一局域网，并允许本地网络和防火墙访问。'),
            ),
          for (final peer in provider.discoveredPeers)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.devices),
                      title: Text(peer.displayName),
                      subtitle: Text(
                        '${peer.addresses.join(', ')}:${peer.port}',
                      ),
                      trailing: FilledButton(
                        onPressed: provider.busy
                            ? null
                            : () => provider.sync(peer),
                        child: const Text('同步普通数据'),
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: provider.busy
                              ? null
                              : () => provider.requestSecretTransfer(
                                  peer,
                                  direction: 'send',
                                ),
                          child: const Text('请求发送模型 API Key'),
                        ),
                        OutlinedButton(
                          onPressed: provider.busy
                              ? null
                              : () => provider.requestSecretTransfer(
                                  peer,
                                  direction: 'receive',
                                ),
                          child: const Text('请求接收模型 API Key'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (provider.secretRequests.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('待批准的密钥请求', style: Theme.of(context).textTheme.titleMedium),
            for (final request in provider.secretRequests)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    request.direction == 'receive'
                        ? '对方请求向本机发送模型 API Key'
                        : '对方请求从本机接收模型 API Key',
                  ),
                  subtitle: Text('请求将在 ${request.expiresAt.toLocal()} 失效'),
                  trailing: Wrap(
                    children: [
                      TextButton(
                        onPressed: () => provider.rejectSecretTransfer(request),
                        child: const Text('拒绝'),
                      ),
                      FilledButton(
                        onPressed: provider.busy
                            ? null
                            : () => provider.approveSecretTransfer(request),
                        child: const Text('批准一次'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 12),
          Text('可信设备', style: Theme.of(context).textTheme.titleMedium),
          if (provider.peers.isEmpty)
            const ListTile(
              leading: Icon(Icons.phonelink_lock),
              title: Text('尚未配对设备'),
            ),
          for (final peer in provider.peers)
            Card(
              child: ListTile(
                leading: Icon(
                  peer.revoked ? Icons.block : Icons.verified_user_outlined,
                ),
                title: Text(peer.displayName),
                subtitle: Text(
                  peer.revoked ? '已撤销\n${peer.fingerprint}' : peer.fingerprint,
                ),
                isThreeLine: peer.revoked,
                trailing: peer.revoked
                    ? null
                    : TextButton(
                        onPressed: provider.busy
                            ? null
                            : () => provider.revoke(peer.deviceId),
                        child: const Text('撤销'),
                      ),
              ),
            ),
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_outlined),
              title: Text('冲突与密钥'),
              subtitle: Text(
                '普通同步包含应用数据，以及与云同步相同的脱敏插件内容、设置和配置元数据；不包含插件私有存储或 API Key。模型 API Key 只能通过单独的一次性请求，在双方于短时限内批准后传输。设备身份、TLS 私钥、登录令牌和任意文件永不传输。',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showQr() async {
    final payload = await context.read<LanSyncProvider>().showPairingQr();
    if (!mounted || payload == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('一次性配对码'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(data: payload, size: 300),
              const SizedBox(height: 8),
              const Text('配对码约 3 分钟后失效，成功使用后立即作废。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanOrImport() async {
    final payload = Platform.isAndroid || Platform.isIOS
        ? await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const _QrScannerPage()),
          )
        : await _decodeQrImage();
    if (!mounted || payload == null) return;
    await context.read<LanSyncProvider>().pair(payload);
  }

  Future<String?> _decodeQrImage() async {
    final result = await file_picker.FilePicker.pickFiles(
      type: file_picker.FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    final file = File(path);
    if (await file.length() > 16 * 1024 * 1024) {
      throw StateError('配对码图片过大');
    }
    final decoded = image.decodeImage(await file.readAsBytes());
    if (decoded == null) throw StateError('无法读取配对码图片');
    final rgba = decoded.convert(numChannels: 4);
    final source = zxing.RGBLuminanceSource(
      rgba.width,
      rgba.height,
      rgba.getBytes(order: image.ChannelOrder.abgr).buffer.asInt32List(),
    );
    final value = zxing.QRCodeReader()
        .decode(zxing.BinaryBitmap(zxing.GlobalHistogramBinarizer(source)))
        .text;
    if (value.length > LanPairingPayloadCodec.maxEncodedBytes) {
      throw StateError('配对码内容过大');
    }
    return value;
  }
}

class _QrScannerPage extends StatelessWidget {
  const _QrScannerPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫描 LynAI 配对码')),
    body: MobileScanner(
      controller: MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      ),
      onDetect: (capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (value != null &&
            value.length <= LanPairingPayloadCodec.maxEncodedBytes &&
            value.startsWith('lynai://pair/')) {
          Navigator.pop(context, value);
        }
      },
    ),
  );
}
