import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/community.dart';
import '../services/community_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/community_post_card.dart';

class CommunityPostEditorPage extends StatefulWidget {
  const CommunityPostEditorPage({super.key, required this.service, this.post});

  final CommunityService service;
  final CommunityPost? post;

  @override
  State<CommunityPostEditorPage> createState() =>
      _CommunityPostEditorPageState();
}

class _CommunityPostEditorPageState extends State<CommunityPostEditorPage> {
  static const maxImages = 9;
  static const maxImageBytes = 8 * 1024 * 1024;

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late List<CommunityMedia> _existingMedia;
  final List<XFile> _newImages = [];
  bool _preview = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.post?.title ?? '');
    _contentController = TextEditingController(
      text: widget.post?.content ?? '',
    );
    _existingMedia = [...?widget.post?.media];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post == null ? '发布动态' : '编辑动态'),
        actions: [
          IconButton(
            tooltip: _preview ? '编辑' : '预览',
            onPressed: () => setState(() => _preview = !_preview),
            icon: Icon(_preview ? Icons.edit_outlined : Icons.preview_outlined),
          ),
          TextButton(
            onPressed: _submitting ? null : _submit,
            child: Text(widget.post == null ? '发布' : '保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: '标题（可选）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            if (_preview)
              Container(
                constraints: const BoxConstraints(minHeight: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SafeCommunityMarkdown(data: _contentController.text),
              )
            else
              TextField(
                controller: _contentController,
                minLines: 10,
                maxLines: null,
                maxLength: 20000,
                decoration: const InputDecoration(
                  labelText: '正文（Markdown）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '图片 ${_existingMedia.length + _newImages.length}/$maxImages',
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('添加图片'),
                ),
              ],
            ),
            if (_existingMedia.isNotEmpty || _newImages.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _existingMedia.length; i++)
                    _ImageChip(
                      label: '已上传 ${i + 1}',
                      onDelete: () =>
                          setState(() => _existingMedia.removeAt(i)),
                    ),
                  for (var i = 0; i < _newImages.length; i++)
                    _ImageChip(
                      label: _newImages[i].name,
                      onDelete: () => setState(() => _newImages.removeAt(i)),
                    ),
                ],
              ),
            if (_submitting) ...[
              const SizedBox(height: 20),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('正在上传并保存…', textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    final remaining = maxImages - _existingMedia.length - _newImages.length;
    if (remaining <= 0) {
      showShortSnackBar(context, '最多添加 $maxImages 张图片');
      return;
    }
    final picked = await ImagePicker().pickMultiImage();
    if (!mounted) return;
    for (final image in picked.take(remaining)) {
      final length = await image.length();
      if (!mounted) return;
      if (length > maxImageBytes) {
        showErrorSnackBar(context, '${image.name} 超过 8 MiB');
        continue;
      }
      _newImages.add(image);
    }
    setState(() {});
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty &&
        content.isEmpty &&
        _existingMedia.isEmpty &&
        _newImages.isEmpty) {
      showShortSnackBar(context, '请输入正文或添加图片');
      return;
    }
    setState(() => _submitting = true);
    try {
      final mediaIds = _existingMedia.map((item) => item.id).toList();
      for (final image in _newImages) {
        final media = await widget.service.uploadMedia(
          bytes: await image.readAsBytes(),
          filename: image.name,
          contentType: image.mimeType,
        );
        mediaIds.add(media.id);
      }
      final post = widget.post == null
          ? await widget.service.createPost(
              title: title,
              content: content,
              mediaIds: mediaIds,
            )
          : await widget.service.updatePost(
              widget.post!.id,
              title: title,
              content: content,
              mediaIds: mediaIds,
            );
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, '保存失败', details: error.toString());
      setState(() => _submitting = false);
    }
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({required this.label, required this.onDelete});

  final String label;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: const Icon(Icons.image_outlined, size: 18),
      label: SizedBox(
        width: 120,
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      onDeleted: onDelete,
    );
  }
}
