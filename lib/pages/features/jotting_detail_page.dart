import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/jotting.dart';
import '../../services/storage_v2_service.dart';
import '../../widgets/latex_renderer.dart';

/// Read-only detail view for a local jotting.
///
/// Editing is opened as a dedicated full-screen route by the parent timeline,
/// keeping the timeline mounted and preserving its scroll position.
class JottingDetail extends StatelessWidget {
  const JottingDetail({
    super.key,
    required this.jotting,
    required this.onEdit,
    this.onReferenceTap,
  });

  final Jotting jotting;
  final VoidCallback onEdit;
  final ValueChanged<JottingReference>? onReferenceTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('随记'),
        actions: [
          IconButton(
            tooltip: '编辑随记',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '创建于 ${_formatTime(jotting.createdAt)} · '
                '更新于 ${_formatTime(jotting.updatedAt)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (jotting.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in jotting.tags)
                      Chip(
                        label: Text('#$tag'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (jotting.references.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final reference in jotting.references)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReferenceCard(
                      reference: reference,
                      onTap: onReferenceTap == null
                          ? null
                          : () => onReferenceTap!(reference),
                    ),
                  ),
              ],
              if (jotting.attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final attachment in jotting.attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _AttachmentCard(attachment: attachment),
                  ),
              ],
              const Divider(height: 28),
              MarkdownWithLatex(content: jotting.content),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }
}

class _ReferenceCard extends StatelessWidget {
  const _ReferenceCard({required this.reference, this.onTap});

  final JottingReference reference;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (reference.type) {
      JottingReferenceType.note => (Icons.sticky_note_2_outlined, Colors.blue),
      JottingReferenceType.task => (Icons.checklist, Colors.green),
      JottingReferenceType.knowledgeEntry => (
        Icons.local_library_outlined,
        Colors.orange,
      ),
    };
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reference.title.isEmpty ? '未命名引用' : reference.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (reference.snippet.isNotEmpty)
                      Text(
                        reference.snippet,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentCard extends StatefulWidget {
  const _AttachmentCard({required this.attachment});

  final JottingAttachment attachment;

  @override
  State<_AttachmentCard> createState() => _AttachmentCardState();
}

class _AttachmentCardState extends State<_AttachmentCard> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  Future<void> _resolvePath() async {
    try {
      final storage = context.read<StorageV2Service>();
      final resource = await storage.findResourceById(
        widget.attachment.resourceId,
      );
      final path = resource == null ? null : await storage.resourcePath(resource);
      if (!mounted) return;
      setState(() => _path = path);
    } catch (_) {
      if (!mounted) return;
      setState(() => _path = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.attachment.isImage && _path != null
            ? () => _openImage(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if (widget.attachment.isImage)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _path == null
                      ? const SizedBox.square(
                          dimension: 44,
                          child: Icon(Icons.image_outlined),
                        )
                      : Image.file(
                          File(_path!),
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.square(
                            dimension: 44,
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                )
              else
                const Icon(Icons.insert_drive_file_outlined, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.attachment.originalName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                child: Image.file(File(_path!), fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
