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
import '../models/lan_peer.dart';
import '../models/sync_data_selection.dart';
import '../services/lan_sync_coordinator.dart';
import '../services/storage_v2_database.dart';
import '../widgets/merge_conflict_card.dart';

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
      provider.confirmPolicyProposal = _confirmPolicyProposal;
      provider.initialize();
      provider.startDiscovery();
    });
  }

  Future<LanPairingDecision> _confirmPairing(
    LanPairingConfirmationRequest request,
  ) async {
    if (!mounted) return const LanPairingDecision.rejected();
    final selection = await _showSelectionDialog(
      title: '确认设备指纹',
      selection: request.proposedSelection,
      available: request.proposedSelection,
      description: '设备: ${request.displayName}',
      fingerprint: request.fingerprint,
      confirmLabel: '指纹一致',
    );
    return selection == null
        ? const LanPairingDecision.rejected()
        : LanPairingDecision(approved: true, selection: selection);
  }

  Future<SyncDataSelection?> _confirmPolicyProposal(
    String displayName,
    SyncDataSelection proposed,
    SyncDataSelection current,
  ) async {
    if (!mounted) return null;
    return _showSelectionDialog(
      title: '确认新增同步类别',
      selection: current.intersect(proposed),
      available: proposed,
      requiredSelection: current.intersect(proposed),
      description: '$displayName 请求扩大双方的局域网同步范围。',
      confirmLabel: '接受所选类别',
    );
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.devices_outlined),
                    title: Text(
                      provider.deviceName.isEmpty
                          ? '正在读取本机名称'
                          : provider.deviceName,
                    ),
                    subtitle: Text(provider.hosting ? '前台托管中' : '托管未启动'),
                    trailing: IconButton(
                      onPressed: provider.busy ? null : _editDeviceName,
                      tooltip: '修改设备名称',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ),
                  const Text(
                    '无需云账户。配对码由设备 Ed25519 身份签名，连接使用 TLS 1.3 和证书 SPKI 固定。双方必须确认设备指纹和同步类别；配对成功后可选择立即同步或稍后手动同步。',
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
            Builder(
              builder: (context) {
                final trusted = provider.peers
                    .where((item) => item.deviceId == peer.deviceId)
                    .firstOrNull;
                final canUse = trusted != null && !trusted.revoked;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            canUse ? Icons.verified_outlined : Icons.devices,
                          ),
                          title: Text(
                            canUse ? trusted.displayName : peer.displayName,
                          ),
                          subtitle: Text(
                            '${peer.addresses.join(', ')}:${peer.port}\n'
                            '${canUse ? '已信任' : '未信任的发现信息'}',
                          ),
                          isThreeLine: true,
                          trailing: canUse
                              ? FilledButton(
                                  onPressed: provider.busy
                                      ? null
                                      : () => provider.sync(peer),
                                  child: const Text('同步'),
                                )
                              : null,
                        ),
                        if (canUse)
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
                                child: const Text('发送模型 API Key'),
                              ),
                              OutlinedButton(
                                onPressed: provider.busy
                                    ? null
                                    : () => provider.requestSecretTransfer(
                                        peer,
                                        direction: 'receive',
                                      ),
                                child: const Text('接收模型 API Key'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
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
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      peer.revoked ? Icons.block : Icons.verified_user_outlined,
                    ),
                    title: Text(peer.displayName),
                    subtitle: Text(
                      peer.revoked
                          ? '已撤销\n${peer.fingerprint}'
                          : '${peer.fingerprint}\n${_selectionSummary(peer.syncSelection)}',
                    ),
                    isThreeLine: true,
                  ),
                  if (!peer.revoked)
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: provider.busy
                              ? null
                              : () => _editSelection(peer),
                          icon: const Icon(Icons.tune),
                          label: const Text('同步范围'),
                        ),
                        TextButton(
                          onPressed: provider.busy
                              ? null
                              : () => provider.revoke(peer.deviceId),
                          child: const Text('撤销'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (provider.conflicts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '待处理同步冲突 (${provider.conflicts.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final conflict in provider.conflicts)
              MergeConflictCard(
                conflict: conflict.view,
                choices: [
                  MergeConflictChoice(
                    label: '保留本地',
                    onSelected: () => provider.resolveConflict(
                      conflict.seq,
                      SyncConflictResolution.keepLocal,
                    ),
                  ),
                  MergeConflictChoice(
                    label: '使用对方',
                    onSelected: () => provider.resolveConflict(
                      conflict.seq,
                      SyncConflictResolution.useRemote,
                    ),
                  ),
                ],
              ),
          ],
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

  Future<void> _editDeviceName() async {
    final provider = context.read<LanSyncProvider>();
    final controller = TextEditingController(text: provider.deviceName);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('设备名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 64,
            decoration: const InputDecoration(hintText: '用于局域网发现和配对确认'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (value != null && mounted) await provider.updateDeviceName(value);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _scanOrImport() async {
    final payload = Platform.isAndroid || Platform.isIOS
        ? await Navigator.push<String>(
            context,
            MaterialPageRoute(builder: (_) => const _QrScannerPage()),
          )
        : await _decodeQrImage();
    if (!mounted || payload == null) return;
    final proposedSelection = await _showSelectionDialog(
      title: '选择同步内容',
      selection: SyncDataSelection.defaults,
      available: SyncDataSelection.all,
      description: '先选择希望与该设备双向同步的数据。对方配对后可以接受其中的全部或部分。',
      confirmLabel: '继续配对',
    );
    if (!mounted || proposedSelection == null) return;
    final provider = context.read<LanSyncProvider>();
    final result = await provider.pair(
      payload,
      proposedSelection: proposedSelection,
    );
    if (!mounted || result == null) return;
    final syncNow = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('配对成功'),
        content: Text('已与 ${result.peer.displayName} 建立信任。是否立即执行双向同步？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('立即同步'),
          ),
        ],
      ),
    );
    if (syncNow == true && mounted) {
      await provider.sync(result.discoveredPeer);
    }
  }

  Future<void> _editSelection(LanPeer peer) async {
    final selection = await _showSelectionDialog(
      title: '同步范围',
      selection: peer.syncSelection,
      available: SyncDataSelection.all,
      description: '关闭类别会立即在本机生效；新增类别需要对方在线确认。',
      confirmLabel: '应用',
    );
    if (selection == null || !mounted) return;
    await context.read<LanSyncProvider>().updateSyncSelection(peer, selection);
  }

  Future<SyncDataSelection?> _showSelectionDialog({
    required String title,
    required SyncDataSelection selection,
    required SyncDataSelection available,
    required String description,
    required String confirmLabel,
    SyncDataSelection requiredSelection = const SyncDataSelection({}),
    String? fingerprint,
  }) => showDialog<SyncDataSelection>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      var selected = selection;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(description),
                  if (fingerprint != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      fingerprint,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 8),
                    const Text('请在另一台设备上核对完全相同的指纹。'),
                  ],
                  const SizedBox(height: 12),
                  for (final category in SyncDataCategory.values)
                    if (available.contains(category))
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selected.contains(category),
                        title: Text(_categoryLabel(category)),
                        onChanged: requiredSelection.contains(category)
                            ? null
                            : (enabled) => setState(
                                () => selected = selected.copyWithCategory(
                                  category,
                                  enabled: enabled ?? false,
                                ),
                              ),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );

  String _selectionSummary(SyncDataSelection selection) =>
      selection.categories.map(_categoryLabel).join('、');

  String _categoryLabel(SyncDataCategory category) => switch (category) {
    SyncDataCategory.conversations => '对话与附件元数据',
    SyncDataCategory.notes => '笔记',
    SyncDataCategory.tasks => '任务',
    SyncDataCategory.knowledge => '知识库',
    SyncDataCategory.calendar => '日历',
    SyncDataCategory.roleplay => '角色扮演',
    SyncDataCategory.settings => '设置',
    SyncDataCategory.models => '模型配置',
    SyncDataCategory.plugins => '插件',
    SyncDataCategory.staticResources => '静态资源与附件文件',
  };

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
