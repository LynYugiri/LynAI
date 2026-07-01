part of '../feature_page.dart';

/// 情景演绎主页面。
///
/// 支持多角色 AI 共演：导演模型决定发言顺序，各角色按自定义模型生成对话，
/// 可插入附件、流式输出、导出 Markdown 或长图。
class _RoleplayPage extends StatefulWidget {
  final bool active;

  const _RoleplayPage({required this.active});

  @override
  State<_RoleplayPage> createState() => _RoleplayPageState();
}

class _RoleplayPageState extends State<_RoleplayPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _service = RoleplayService();
  final _attachmentStorage = const AttachmentStorageService();
  final _screenshotCtrl = ScreenshotController();
  final List<_RoleplayPendingAttachment> _pendingAttachments = [];
  final Map<String, bool> _attachmentExistsCache = {};
  StreamSubscription<StreamChunk>? _speechSub;
  String? _threadId;
  bool _showAttach = false;
  bool _exporting = false;
  int _runGen = 0;
  DateTime? _lastDraftUiUpdate;

  static const _draftUiUpdateInterval = Duration(milliseconds: 80);

  bool get _running =>
      context.read<RoleplayProvider>().activeThreadId == _threadId &&
      context.read<RoleplayProvider>().runState != RoleplayRunState.idle &&
      context.read<RoleplayProvider>().runState !=
          RoleplayRunState.waitingUser &&
      context.read<RoleplayProvider>().runState != RoleplayRunState.error;

  @override
  void dispose() {
    _clearRunningStateOnDispose();
    _speechSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _service.dispose();
    super.dispose();
  }

  void _clearRunningStateOnDispose() {
    final threadId = _threadId;
    if (threadId == null) return;
    final provider = context.read<RoleplayProvider>();
    if (provider.activeThreadId != threadId) return;
    if (provider.runState == RoleplayRunState.idle) return;
    provider.setRunState(RoleplayRunState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoleplayProvider>();
    final thread = _threadId == null ? null : provider.getThread(_threadId!);
    final title = thread?.title ?? '情景演绎';
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.history),
            tooltip: '演绎历史',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(title),
        actions: [
          if (thread != null)
            IconButton(
              icon: const Icon(Icons.groups_2_outlined),
              tooltip: '角色管理',
              onPressed: () => _openThreadRoles(thread),
            ),
          if (thread != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '情景设置',
              onPressed: () => _openThreadSettings(thread),
            ),
          if (thread != null)
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) {
                switch (value) {
                  case 'new':
                    _newThread(thread.scenarioId);
                  case 'rename':
                    _renameThread(thread);
                  case 'markdown':
                    _exportMarkdown(thread);
                  case 'image':
                    _exportImage(thread);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'new', child: Text('新开演绎')),
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'markdown', child: Text('导出 Markdown')),
                PopupMenuItem(value: 'image', child: Text('导出长图')),
              ],
            ),
        ],
      ),
      drawer: _RoleplayHistoryDrawer(
        currentThreadId: _threadId,
        onSelectThread: (id) {
          if (_running) _stopGeneration(saveDraft: true);
          setState(() {
            _threadId = id;
            _pendingAttachments.clear();
            _showAttach = false;
          });
          Navigator.pop(context);
          _scrollToBottom();
        },
        onNewScenario: _openScenarioEditor,
        onNewThread: (scenarioId) {
          Navigator.pop(context);
          _newThread(scenarioId);
        },
      ),
      body: thread == null
          ? _emptyState(provider)
          : _threadBody(provider, thread),
    );
  }

  Widget _emptyState(RoleplayProvider provider) {
    final hasScenarios = provider.scenarios.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.theater_comedy_outlined,
              size: 72,
              color: scheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              hasScenarios ? '选择一个情景开始演绎' : '还没有情景',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hasScenarios
                  ? '打开左侧历史，选择情景或新开一次演绎。'
                  : '创建可重复使用的情景，之后可以像对话一样多次开局。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openScenarioEditor,
              icon: const Icon(Icons.add),
              label: const Text('新建情景'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _threadBody(RoleplayProvider provider, RoleplayThread thread) {
    final isActive = provider.activeThreadId == thread.id;
    final running =
        isActive &&
        provider.runState != RoleplayRunState.idle &&
        provider.runState != RoleplayRunState.waitingUser &&
        provider.runState != RoleplayRunState.error;
    final pending = provider.pendingPlayerMessages(thread.id);
    return Column(
      children: [
        Expanded(
          child: SystemScrollCaptureTarget(
            controller: _scrollCtrl,
            enabled: widget.active,
            child: ListView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                if (thread.messages.isEmpty) _scenarioIntro(thread),
                for (final message in thread.messages) _messageBubble(message),
                if (isActive && provider.activeSpeakerName != null)
                  _draftBubble(provider),
                if (pending.isNotEmpty) _queuedBanner(pending.length),
                if (isActive &&
                    provider.runState == RoleplayRunState.error &&
                    provider.errorMessage != null)
                  _errorBanner(provider.errorMessage!),
              ],
            ),
          ),
        ),
        _inputArea(thread, running),
      ],
    );
  }

  Widget _scenarioIntro(RoleplayThread thread) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            thread.scenarioTitle,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            thread.scenario,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final participant in thread.participants)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    participant.isPlayer
                        ? '我：${participant.name}'
                        : participant.name,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(RoleplayMessage message) {
    final isPlayer = message.kind == RoleplayMessageKind.player;
    final isNarrator = message.kind == RoleplayMessageKind.narrator;
    final scheme = Theme.of(context).colorScheme;
    if (isNarrator) {
      return Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: MarkdownWithLatex(content: message.content),
        ),
      );
    }
    return Align(
      alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isPlayer
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.85,
            ),
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPlayer
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isPlayer ? 16 : 4),
                bottomRight: Radius.circular(isPlayer ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.speakerName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isPlayer ? scheme.primary : scheme.secondary,
                  ),
                ),
                if (message.content.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  MarkdownWithLatex(content: message.content),
                ],
                if (message.attachments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _attachmentGrid(message.attachments),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _draftBubble(RoleplayProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.secondaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.activeSpeakerName ?? '角色',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.secondary,
              ),
            ),
            const SizedBox(height: 4),
            provider.draftContent == null || provider.draftContent!.isEmpty
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : MarkdownWithLatex(content: provider.draftContent!),
          ],
        ),
      ),
    );
  }

  Widget _queuedBanner(int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        '$count 条用户消息将在当前输出后合并发送',
        textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Widget _errorBanner(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }

  Widget _inputArea(RoleplayThread thread, bool running) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingAttachments.isNotEmpty) _pendingAttachmentPreview(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _submit(thread, running: running);
                      return KeyEventResult.handled;
                    }
                    final isPaste =
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.keyV &&
                        (HardwareKeyboard.instance.isControlPressed ||
                            HardwareKeyboard.instance.isMetaPressed);
                    if (isPaste) {
                      unawaited(_pasteClipboardImage());
                      return KeyEventResult.ignored;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _focusNode,
                    style: const TextStyle(fontSize: 16),
                    decoration: const InputDecoration(
                      hintText: '输入消息...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 10,
                      ),
                    ),
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _inputActionButton(
                Icons.playlist_play,
                '继续',
                () => _advance(thread.id),
              ),
              const SizedBox(width: 4),
              _inputActionButton(
                Icons.groups_2_outlined,
                '角色',
                () => _openThreadRoles(thread),
              ),
              const Spacer(),
              _attachButton(),
              const SizedBox(width: 4),
              _sendButton(thread, running),
            ],
          ),
          if (_showAttach) _attachMenu(),
        ],
      ),
    );
  }

  Widget _inputActionButton(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _sendButton(RoleplayThread thread, bool running) {
    if (running) {
      return IconButton(
        onPressed: () => _stopGeneration(saveDraft: true),
        tooltip: '停止生成',
        icon: Icon(Icons.stop_circle, color: Colors.red[400], size: 24),
      );
    }
    return IconButton(
      onPressed: () => _submit(thread, running: false),
      icon: Icon(
        Icons.send_rounded,
        color: Theme.of(context).colorScheme.primary,
        size: 22,
      ),
    );
  }

  Widget _attachButton() {
    return IconButton(
      onPressed: () => setState(() => _showAttach = !_showAttach),
      icon: Icon(
        _showAttach ? Icons.close : Icons.add,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }

  Widget _attachMenu() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _attachOpt(Icons.attach_file, '文件', _pickFiles),
          const SizedBox(width: 8),
          _attachOpt(Icons.photo_library, '图片', _pickImages),
          if (!isDesktopPlatform) ...[
            const SizedBox(width: 8),
            _attachOpt(Icons.photo_camera, '拍照', _takePhoto),
          ],
        ],
      ),
    );
  }

  Widget _attachOpt(IconData icon, String label, VoidCallback action) {
    return InkWell(
      onTap: () {
        setState(() => _showAttach = false);
        action();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _submit(RoleplayThread thread, {required bool running}) {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    final attachments = _pendingAttachments
        .map((item) => item.toMessageImage())
        .toList();
    _inputCtrl.clear();
    setState(() => _pendingAttachments.clear());
    final provider = context.read<RoleplayProvider>();
    if (running) {
      provider.queuePlayerMessage(thread.id, text, attachments: attachments);
      return;
    }
    provider.appendPlayerMessage(thread.id, text, attachments: attachments);
    _advance(thread.id);
  }

  // 导演模型决定下一位发言人，可能继续 AI 轮播、切为用户等待或触发旁白。
  Future<void> _advance(String threadId) async {
    final provider = context.read<RoleplayProvider>();
    final models = context.read<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    var autoTurns = 0;
    final gen = ++_runGen;
    while (mounted && gen == _runGen) {
      var thread = provider.getThread(threadId);
      if (thread == null) return;
      final pending = provider.drainMergedPendingPlayerMessage(threadId);
      if (pending != null) {
        provider.appendPlayerMessage(
          threadId,
          pending.content,
          attachments: pending.attachments,
        );
        autoTurns = 0;
        _scrollToBottom();
        thread = provider.getThread(threadId);
        if (thread == null) return;
      }
      if (thread.maxAutoTurns > 0 && autoTurns >= thread.maxAutoTurns) {
        provider.setRunState(RoleplayRunState.waitingUser, threadId: threadId);
        return;
      }
      provider.setRunState(
        RoleplayRunState.directing,
        threadId: threadId,
        speakerName: '系统',
      );
      final directorModel = RoleplayService.resolveModel(
        thread.director.model,
        models,
      );
      if (directorModel == null) {
        provider.setRunState(
          RoleplayRunState.error,
          threadId: threadId,
          errorMessage: '没有可用聊天模型',
        );
        return;
      }
      try {
        final decision = await _service.decideNext(
          thread: thread,
          model: directorModel,
        );
        if (!mounted || gen != _runGen) return;
        if (decision.isNarrator) {
          provider.appendNarratorMessage(
            threadId,
            decision.content ?? decision.reason,
          );
          autoTurns++;
          _scrollToBottom();
          continue;
        }
        if (decision.waitsForUser || decision.speakerId == null) {
          provider.setRunState(
            RoleplayRunState.waitingUser,
            threadId: threadId,
          );
          return;
        }
        thread = provider.getThread(threadId);
        if (thread == null) return;
        var participant = thread.characters
            .where((role) => role.id == decision.speakerId)
            .firstOrNull;
        participant ??= thread.characters.isEmpty
            ? null
            : thread.characters.first;
        if (participant == null) {
          provider.setRunState(
            RoleplayRunState.waitingUser,
            threadId: threadId,
          );
          return;
        }
        final model = participant.model.isEmpty
            ? directorModel
            : RoleplayService.resolveModel(participant.model, models) ??
                  directorModel;
        provider.setRunState(
          RoleplayRunState.speaking,
          threadId: threadId,
          speakerName: participant.name,
          draftContent: '',
        );
        final content = await _streamParticipantSpeech(
          provider,
          thread,
          participant,
          model,
          gen,
        );
        if (!mounted || gen != _runGen) return;
        provider.appendCharacterMessage(
          threadId,
          participant,
          content.trim().isEmpty ? '（沉默）' : content.trim(),
        );
        autoTurns++;
        _scrollToBottom();
      } catch (e) {
        if (!mounted || gen != _runGen) return;
        provider.setRunState(
          RoleplayRunState.error,
          threadId: threadId,
          errorMessage: '$e',
        );
        showShortSnackBar(context, '演绎生成失败: $e');
        return;
      }
    }
  }

  Future<String> _streamParticipantSpeech(
    RoleplayProvider provider,
    RoleplayThread thread,
    RoleplayParticipant participant,
    ModelConfig model,
    int gen,
  ) async {
    final buffer = StringBuffer();
    final completer = Completer<void>();
    _speechSub?.cancel();
    _speechSub = _service
        .speakStream(thread: thread, participant: participant, model: model)
        .listen(
          (chunk) {
            if (!mounted || gen != _runGen) return;
            final content = chunk.content;
            if (content != null && content.isNotEmpty) {
              buffer.write(content);
              _updateDraft(provider, buffer.toString());
              _scrollToBottom();
            }
            if (chunk.isDone && !completer.isCompleted) completer.complete();
          },
          onError: (Object e) {
            if (!completer.isCompleted) completer.completeError(e);
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
        );
    await completer.future;
    await _speechSub?.cancel();
    _speechSub = null;
    _updateDraft(provider, buffer.toString(), force: true);
    return buffer.toString();
  }

  void _updateDraft(
    RoleplayProvider provider,
    String content, {
    bool force = false,
  }) {
    if (!force) {
      final now = DateTime.now();
      final last = _lastDraftUiUpdate;
      if (last != null && now.difference(last) < _draftUiUpdateInterval) {
        return;
      }
      _lastDraftUiUpdate = now;
    } else {
      _lastDraftUiUpdate = DateTime.now();
    }
    provider.updateDraft(content);
  }

  void _stopGeneration({required bool saveDraft}) {
    final provider = context.read<RoleplayProvider>();
    final thread = _threadId == null ? null : provider.getThread(_threadId!);
    final speaker = thread == null || provider.activeSpeakerName == null
        ? null
        : thread.characters
              .where((item) => item.name == provider.activeSpeakerName)
              .firstOrNull;
    _runGen++;
    _lastDraftUiUpdate = null;
    _speechSub?.cancel();
    _speechSub = null;
    if (saveDraft && thread != null && speaker != null) {
      provider.appendDraftAsCharacterMessage(thread.id, speaker);
    }
    provider.setRunState(RoleplayRunState.idle);
  }

  Future<void> _pickImages() async {
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (!mounted || picked.isEmpty) return;
      final files = <_RoleplayPendingAttachment>[];
      for (var i = 0; i < picked.length; i++) {
        final item = picked[i];
        files.add(
          await _storeAttachmentFile(
            File(item.path),
            item.name,
            mimeType:
                item.mimeType ??
                AttachmentStorageService.inferMimeType(item.path),
          ),
        );
      }
      if (mounted) setState(() => _pendingAttachments.addAll(files));
    } catch (e) {
      if (mounted) showShortSnackBar(context, '图片读取失败: $e');
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await pickMultipleFilePayloads();
      if (!mounted || result.isEmpty) return;
      final files = <_RoleplayPendingAttachment>[];
      for (final item in result) {
        files.add(await _storeAttachmentPayload(item));
      }
      if (mounted) setState(() => _pendingAttachments.addAll(files));
    } catch (e) {
      if (mounted) showShortSnackBar(context, '文件读取失败: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      if (!mounted || picked == null) return;
      final file = await _storeAttachmentFile(
        File(picked.path),
        picked.name,
        mimeType:
            picked.mimeType ??
            AttachmentStorageService.inferMimeType(picked.path),
      );
      if (mounted) setState(() => _pendingAttachments.add(file));
    } catch (e) {
      if (mounted) showShortSnackBar(context, '拍照失败: $e');
    }
  }

  Future<void> _pasteClipboardImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    try {
      final reader = await clipboard.read();
      final format = reader.canProvide(Formats.png)
          ? Formats.png
          : reader.canProvide(Formats.jpeg)
          ? Formats.jpeg
          : reader.canProvide(Formats.webp)
          ? Formats.webp
          : null;
      if (format == null) return;
      final completer = Completer<void>();
      reader.getFile(format, (file) async {
        final bytes = await file.readAll();
        final ext = format == Formats.jpeg
            ? '.jpg'
            : format == Formats.webp
            ? '.webp'
            : '.png';
        final stored = await _storeBytesAttachment(
          bytes,
          file.fileName ?? 'clipboard$ext',
          AttachmentStorageService.inferMimeType(ext),
        );
        if (mounted) setState(() => _pendingAttachments.add(stored));
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
    } catch (_) {}
  }

  Future<_RoleplayPendingAttachment> _storeAttachmentFile(
    File source,
    String name, {
    String? mimeType,
  }) async {
    return _roleplayAttachmentFromStored(
      await _attachmentStorage.storeFile(
        source,
        directoryName: 'roleplay_attachments',
        name: name,
        mimeType: mimeType,
      ),
    );
  }

  Future<_RoleplayPendingAttachment> _storeAttachmentPayload(
    PickedFilePayload source,
  ) async {
    return _roleplayAttachmentFromStored(
      await _attachmentStorage.storePayload(
        source,
        directoryName: 'roleplay_attachments',
      ),
    );
  }

  Future<_RoleplayPendingAttachment> _storeBytesAttachment(
    Uint8List bytes,
    String name,
    String mimeType,
  ) async {
    return _roleplayAttachmentFromStored(
      await _attachmentStorage.storeBytes(
        bytes,
        directoryName: 'roleplay_attachments',
        name: name,
        fallbackName: 'image',
        mimeType: mimeType,
      ),
    );
  }

  _RoleplayPendingAttachment _roleplayAttachmentFromStored(
    StoredAttachment stored,
  ) {
    return _RoleplayPendingAttachment(
      path: stored.path,
      name: stored.name,
      size: stored.size,
      mimeType: stored.mimeType,
    );
  }

  Widget _pendingAttachmentPreview() {
    return SizedBox(
      height: 86,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _pendingAttachments[index];
          return Stack(
            children: [
              _attachmentPreview(item.toMessageImage(), small: true),
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: () =>
                      setState(() => _pendingAttachments.removeAt(index)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _attachmentGrid(List<MessageImage> attachments) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: attachments.map(_attachmentPreview).toList(),
    );
  }

  Widget _attachmentPreview(MessageImage file, {bool small = false}) {
    final exists = _attachmentExists(file.path);
    if (file.isImage) {
      final size = small ? 76.0 : 120.0;
      return InkWell(
        onTap: exists ? () => _showImagePreview(file.path) : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: exists
              ? Image.file(
                  File(file.path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: size,
                  height: small ? 76 : 60,
                  alignment: Alignment.center,
                  color: Colors.black.withValues(alpha: 0.08),
                  child: const Text('文件已不存在', style: TextStyle(fontSize: 12)),
                ),
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: small ? 120 : 160,
      height: small ? 76 : null,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(_fileIcon(file.mimeType), color: scheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  exists ? _fmtSz(file.size) : '文件已不存在',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _attachmentExists(String path) => _attachmentExistsCache.putIfAbsent(
    path,
    () => path.isNotEmpty && File(path).existsSync(),
  );

  void _showImagePreview(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openScenarioEditor() async {
    final result = await showDialog<_RoleplayScenarioDraft>(
      context: context,
      builder: (_) => const _RoleplayScenarioDialog(),
    );
    if (!mounted || result == null) return;
    final provider = context.read<RoleplayProvider>();
    final scenarioId = provider.createScenario(
      title: result.title,
      description: result.description,
      scenario: result.scenario,
      director: result.director,
      defaultPlayer: result.player,
      defaultParticipants: result.participants,
      defaultGroups: result.groups,
      maxAutoTurns: result.maxAutoTurns,
    );
    _newThread(scenarioId);
  }

  Future<void> _editScenario(RoleplayScenario scenario) async {
    final result = await showDialog<_RoleplayScenarioDraft>(
      context: context,
      builder: (_) => _RoleplayScenarioDialog(initial: scenario),
    );
    if (!mounted || result == null) return;
    context.read<RoleplayProvider>().updateScenario(
      scenario.id,
      title: result.title,
      description: result.description,
      scenario: result.scenario,
      director: result.director,
      defaultPlayer: result.player,
      defaultParticipants: result.participants,
      defaultGroups: result.groups,
      maxAutoTurns: result.maxAutoTurns,
    );
  }

  void _newThread(String scenarioId) {
    final id = context.read<RoleplayProvider>().createThread(scenarioId);
    if (id.isEmpty) return;
    setState(() => _threadId = id);
    _scrollToBottom();
  }

  void _renameThread(RoleplayThread thread) {
    final ctrl = TextEditingController(text: thread.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名演绎'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<RoleplayProvider>().renameThread(
                thread.id,
                ctrl.text,
              );
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    });
  }

  Future<void> _openThreadSettings(RoleplayThread thread) async {
    final result = await showModalBottomSheet<_RoleplayThreadSettingsDraft>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _RoleplayThreadSettingsSheet(
        thread: thread,
        onRoles: () => _openThreadRoles(thread),
      ),
    );
    if (!mounted || result == null) return;
    context.read<RoleplayProvider>().updateThreadSettings(
      thread.id,
      scenario: result.scenario,
      director: result.director,
      maxAutoTurns: result.maxAutoTurns,
    );
  }

  Future<void> _openThreadRoles(RoleplayThread thread) async {
    final result = await showDialog<_RoleplayRolesDraft>(
      context: context,
      builder: (_) => _RoleplayRolesDialog(thread: thread),
    );
    if (!mounted || result == null) return;
    context.read<RoleplayProvider>().replaceThreadParticipants(
      thread.id,
      participants: result.participants,
      groups: result.groups,
      playerParticipantId: result.playerParticipantId,
    );
  }

  void _scrollToBottom() {
    if (SystemScrollCaptureService.instance.isCapturing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  String _fmtSz(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('text/') || mimeType == 'application/json') {
      return Icons.description_outlined;
    }
    if (mimeType.contains('zip') || mimeType.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Future<void> _exportMarkdown(RoleplayThread thread) async {
    final buffer = StringBuffer();
    buffer.writeln('# ${thread.title}');
    buffer.writeln();
    buffer.writeln('> ${thread.scenario}');
    buffer.writeln();
    for (final message in thread.messages) {
      if (message.kind == RoleplayMessageKind.narrator) {
        buffer.writeln('*${message.content}*');
      } else {
        buffer.writeln('**${message.speakerName}**：');
        buffer.writeln(message.content);
      }
      if (message.attachments.isNotEmpty) {
        buffer.writeln(
          message.attachments.map((item) => '[附件: ${item.name}]').join('\n'),
        );
      }
      buffer.writeln();
    }
    final baseName = safeExportFileName(thread.title, fallback: 'roleplay');
    await shareTextFile(
      fileName: '$baseName.md',
      content: buffer.toString(),
      text: thread.title,
    );
  }

  Future<void> _exportImage(RoleplayThread thread) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final pages = _splitImagePages(thread.messages, maxWeight: 3200);
      final images = <Uint8List>[];
      for (var i = 0; i < pages.length; i++) {
        final widget = RepaintBoundary(
          child: _RoleplayShareImage(
            thread: thread,
            messages: pages[i],
            seedColor: scheme.primary,
            isDark: isDark,
            pageNumber: pages.length > 1 ? i + 1 : null,
            pageCount: pages.length > 1 ? pages.length : null,
          ),
        );
        images.add(await _captureSharePageImage(widget));
      }
      if (!mounted) return;
      if (images.isEmpty) {
        showShortSnackBar(context, '生成长图失败，请重试');
        return;
      }
      final prefix = safeExportFileName(thread.title, fallback: 'roleplay');
      await shareOrSavePngImages(
        images: images,
        filePrefix: prefix.length > 40 ? prefix.substring(0, 40) : prefix,
        nativeTools: const MethodChannel('lynai/native_tools'),
        clipboardMessage: '长图已复制到剪贴板',
        galleryMessage: '长图已保存到图库',
      );
    } catch (e) {
      if (mounted) showShortSnackBar(context, '导出失败: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<Uint8List> _captureSharePageImage(Widget shareWidget) async {
    try {
      return await _screenshotCtrl.captureFromLongWidget(
        shareWidget,
        pixelRatio: 2.5,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
    } catch (_) {
      return _screenshotCtrl.captureFromWidget(
        shareWidget,
        pixelRatio: 2.5,
        context: context,
      );
    }
  }

  // 将消息按内容和附件总长度拆分为多个导出页，避免单页过长。
  List<List<RoleplayMessage>> _splitImagePages(
    List<RoleplayMessage> messages, {
    required int maxWeight,
  }) {
    final pages = <List<RoleplayMessage>>[];
    var current = <RoleplayMessage>[];
    var currentWeight = 0;
    for (final message in messages) {
      final chunks = _splitLongMessage(message);
      for (final chunk in chunks) {
        final weight = chunk.content.length + 300;
        if (current.isNotEmpty && currentWeight + weight > maxWeight) {
          pages.add(current);
          current = [];
          currentWeight = 0;
        }
        current.add(chunk);
        currentWeight += weight;
      }
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  // 将超长消息拆分为多个片段，保持附件仅出现在首片段。
  List<RoleplayMessage> _splitLongMessage(RoleplayMessage message) {
    final content = message.content.trim();
    if (content.length <= 2800) return [message];
    final chunks = splitTextForExport(content, maxLength: 2800);
    final result = <RoleplayMessage>[];
    for (var i = 0; i < chunks.length; i++) {
      result.add(
        RoleplayMessage(
          id: i == 0 ? message.id : '${message.id}_chunk_$i',
          speakerId: message.speakerId,
          speakerName: message.speakerName,
          content: chunks[i],
          kind: message.kind,
          attachments: i == 0 ? message.attachments : const [],
          timestamp: message.timestamp,
        ),
      );
    }
    return result;
  }
}

/// 待提交附件的数据模型，存储本地路径及元信息。
class _RoleplayPendingAttachment {
  final String path;
  final String name;
  final int size;
  final String mimeType;

  const _RoleplayPendingAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  MessageImage toMessageImage() =>
      MessageImage(path: path, name: name, size: size, mimeType: mimeType);
}

/// 为 [Iterable] 提供安全的首元素访问。
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

/// 情景演绎左侧历史抽屉。
///
/// 支持按情景分组展示演绎记录，搜索标题和消息内容，新建/删除情景和演绎。
class _RoleplayHistoryDrawer extends StatefulWidget {
  final String? currentThreadId;
  final ValueChanged<String> onSelectThread;
  final VoidCallback onNewScenario;
  final ValueChanged<String> onNewThread;

  const _RoleplayHistoryDrawer({
    required this.currentThreadId,
    required this.onSelectThread,
    required this.onNewScenario,
    required this.onNewThread,
  });

  @override
  State<_RoleplayHistoryDrawer> createState() => _RoleplayHistoryDrawerState();
}

class _RoleplayHistoryDrawerState extends State<_RoleplayHistoryDrawer> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoleplayProvider>();
    final scenarios = provider.scenarios;
    final query = _query.trim().toLowerCase();
    final visibleScenarios = scenarios.where((scenario) {
      if (query.isEmpty) return true;
      if (scenario.title.toLowerCase().contains(query) ||
          scenario.scenario.toLowerCase().contains(query)) {
        return true;
      }
      return provider.threadsForScenario(scenario.id).any((thread) {
        return thread.title.toLowerCase().contains(query) ||
            thread.preview.toLowerCase().contains(query) ||
            thread.messages.any(
              (message) => message.content.toLowerCase().contains(query),
            );
      });
    }).toList();
    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              bottom: 12,
            ),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.theater_comedy_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '情景演绎',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onNewScenario,
                      icon: const Icon(Icons.add),
                      tooltip: '新建情景',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: '搜索情景或演绎...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: visibleScenarios.isEmpty
                ? Center(child: Text(query.isEmpty ? '暂无情景' : '无匹配结果'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    itemCount: visibleScenarios.length,
                    itemBuilder: (context, index) {
                      final scenario = visibleScenarios[index];
                      final threads = provider
                          .threadsForScenario(scenario.id)
                          .where((thread) {
                            if (query.isEmpty) return true;
                            return thread.title.toLowerCase().contains(query) ||
                                thread.preview.toLowerCase().contains(query) ||
                                thread.messages.any(
                                  (message) => message.content
                                      .toLowerCase()
                                      .contains(query),
                                );
                          })
                          .toList();
                      return _scenarioTile(provider, scenario, threads);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _scenarioTile(
    RoleplayProvider provider,
    RoleplayScenario scenario,
    List<RoleplayThread> threads,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: threads.any(
          (thread) => thread.id == widget.currentThreadId,
        ),
        leading: Icon(
          scenario.pinned ? Icons.push_pin : Icons.theater_comedy_outlined,
          color: scheme.primary,
        ),
        title: Text(
          scenario.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${threads.length} 次演绎',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'new':
                widget.onNewThread(scenario.id);
              case 'pin':
                provider.toggleScenarioPinned(scenario.id);
              case 'edit':
                final page = context
                    .findAncestorStateOfType<_RoleplayPageState>();
                page?._editScenario(scenario);
              case 'delete':
                _deleteScenario(provider, scenario);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'new', child: Text('新开演绎')),
            PopupMenuItem(
              value: 'pin',
              child: Text(scenario.pinned ? '取消置顶' : '置顶情景'),
            ),
            const PopupMenuItem(value: 'edit', child: Text('编辑情景')),
            const PopupMenuItem(value: 'delete', child: Text('删除情景')),
          ],
        ),
        children: [
          if (threads.isEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.add_comment_outlined),
              title: const Text('新开一次演绎'),
              onTap: () => widget.onNewThread(scenario.id),
            ),
          for (final thread in threads) _threadTile(provider, thread),
        ],
      ),
    );
  }

  Widget _threadTile(RoleplayProvider provider, RoleplayThread thread) {
    final active = thread.id == widget.currentThreadId;
    return ListTile(
      selected: active,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: const Icon(Icons.chat, size: 20),
      title: Text(
        thread.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        thread.preview.isEmpty ? '尚未开始' : thread.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => _deleteThread(provider, thread),
      ),
      onTap: () => widget.onSelectThread(thread.id),
      onLongPress: () => _renameThread(provider, thread),
    );
  }

  void _renameThread(RoleplayProvider provider, RoleplayThread thread) {
    final ctrl = TextEditingController(text: thread.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名演绎'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.renameThread(thread.id, ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    });
  }

  void _deleteThread(RoleplayProvider provider, RoleplayThread thread) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除演绎'),
        content: Text('确定删除“${thread.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await provider.deleteThread(thread.id);
                if (!ctx.mounted) return;
                if (thread.id == widget.currentThreadId) {
                  widget.onSelectThread('');
                }
                Navigator.pop(ctx);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }

  void _deleteScenario(RoleplayProvider provider, RoleplayScenario scenario) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除情景'),
        content: Text('确定删除“${scenario.title}”及其所有演绎历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await provider.deleteScenario(scenario.id);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }
}

class _RoleplayScenarioDraft {
  final String title;
  final String description;
  final String scenario;
  final RoleplayDirector director;
  final RoleplayParticipant player;
  final List<RoleplayParticipant> participants;
  final List<RoleplayParticipantGroup> groups;
  final int maxAutoTurns;

  const _RoleplayScenarioDraft({
    required this.title,
    required this.description,
    required this.scenario,
    required this.director,
    required this.player,
    required this.participants,
    required this.groups,
    required this.maxAutoTurns,
  });
}

class _RoleplayScenarioDialog extends StatefulWidget {
  final RoleplayScenario? initial;

  const _RoleplayScenarioDialog({this.initial});

  @override
  State<_RoleplayScenarioDialog> createState() =>
      _RoleplayScenarioDialogState();
}

class _RoleplayScenarioDialogState extends State<_RoleplayScenarioDialog> {
  late final _titleCtrl = TextEditingController(
    text: widget.initial?.title ?? '',
  );
  late final _descCtrl = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final _scenarioCtrl = TextEditingController(
    text: widget.initial?.scenario ?? '',
  );
  late final _playerNameCtrl = TextEditingController(
    text: widget.initial?.defaultPlayer.name ?? '我',
  );
  late final _playerDescCtrl = TextEditingController(
    text: widget.initial?.defaultPlayer.description ?? '',
  );
  late final _maxAutoCtrl = TextEditingController(
    text: '${widget.initial?.maxAutoTurns ?? 3}',
  );
  late RoleplayModelSelection _directorModel =
      widget.initial?.director.model ?? const RoleplayModelSelection();
  late String? _playerSourceRoleId = widget.initial?.defaultPlayer.sourceRoleId;
  final Set<String> _selectedRoleIds = {};

  @override
  void initState() {
    super.initState();
    _selectedRoleIds.addAll(
      widget.initial?.defaultParticipants
              .map((item) => item.sourceRoleId)
              .whereType<String>() ??
          const [],
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _scenarioCtrl.dispose();
    _playerNameCtrl.dispose();
    _playerDescCtrl.dispose();
    _maxAutoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    return AlertDialog(
      title: Text(widget.initial == null ? '新建情景' : '编辑情景'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '简介',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _scenarioCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '场景',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _playerNameCtrl,
                      decoration: const InputDecoration(
                        labelText: '我的角色名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _maxAutoCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'AI轮数(0不限)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _playerDescCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '我的设定',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              _playerRoleSelector(settings),
              const SizedBox(height: 10),
              _RoleplayModelSelector(
                value: _directorModel,
                onChanged: (value) => setState(() => _directorModel = value),
                boxLabel: '导演模型',
              ),
              const SizedBox(height: 12),
              _roleSelector(settings),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: () => _save(settings), child: const Text('保存')),
      ],
    );
  }

  Widget _playerRoleSelector(AppSettings settings) {
    final roles = settings.roles
        .where((role) => role.id != ChatRole.defaultId)
        .toList(growable: false);
    final hasSelected = roles.any((role) => role.id == _playerSourceRoleId);
    return DropdownButtonFormField<String?>(
      initialValue: hasSelected ? _playerSourceRoleId : null,
      decoration: const InputDecoration(
        labelText: '我的角色来源',
        border: OutlineInputBorder(),
        helperText: '默认自定义；选择全局角色会带入名称和描述',
      ),
      isExpanded: true,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('自定义')),
        ...roles.map(
          (role) =>
              DropdownMenuItem<String?>(value: role.id, child: Text(role.name)),
        ),
      ],
      onChanged: (id) {
        final role = roles.where((role) => role.id == id).firstOrNull;
        setState(() {
          _playerSourceRoleId = id;
          if (id != null) _selectedRoleIds.remove(id);
          if (role != null) {
            _playerNameCtrl.text = role.name;
            _playerDescCtrl.text = role.description;
          }
        });
      },
    );
  }

  Widget _roleSelector(AppSettings settings) {
    final roles = settings.roles
        .where((role) => role.id != ChatRole.defaultId)
        .toList(growable: false);
    final roleById = {for (final role in roles) role.id: role};
    final groupedIds = settings.roleGroups
        .expand((group) => group.roleIds)
        .toSet();
    final ungrouped = roles
        .where((role) => !groupedIds.contains(role.id))
        .toList(growable: false);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text('默认 AI 角色 · ${_selectedRoleIds.length}'),
            subtitle: const Text('新开演绎时复制为当前演绎角色'),
            trailing: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RoleManagementPage()),
              ),
              child: const Text('管理'),
            ),
          ),
          const Divider(height: 1),
          if (roles.isEmpty)
            const ListTile(dense: true, title: Text('暂无全局角色'))
          else ...[
            _chatRoleGroupTile('未分组', ungrouped),
            for (final group in settings.roleGroups)
              _chatRoleGroupTile(
                group.name,
                group.roleIds
                    .map((id) => roleById[id])
                    .whereType<ChatRole>()
                    .toList(growable: false),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chatRoleGroupTile(String title, List<ChatRole> roles) {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: roles.any(
        (role) => _selectedRoleIds.contains(role.id),
      ),
      title: Text('$title · ${roles.length}'),
      children: roles.isEmpty
          ? [const ListTile(dense: true, title: Text('暂无角色'))]
          : roles.map(_chatRoleCheckbox).toList(),
    );
  }

  Widget _chatRoleCheckbox(ChatRole role) {
    final selectedAsPlayer = role.id == _playerSourceRoleId;
    return CheckboxListTile(
      dense: true,
      value: selectedAsPlayer || _selectedRoleIds.contains(role.id),
      enabled: !selectedAsPlayer,
      title: Text(role.name),
      subtitle: Text(
        selectedAsPlayer
            ? '已选为“我”'
            : role.description.isNotEmpty
            ? role.description
            : role.systemPrompt,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (selected) {
        setState(() {
          if (selected == true) {
            _selectedRoleIds.add(role.id);
          } else {
            _selectedRoleIds.remove(role.id);
          }
        });
      },
    );
  }

  void _save(AppSettings settings) {
    final scenario = _scenarioCtrl.text.trim();
    if (scenario.isEmpty) return;
    final provider = context.read<RoleplayProvider>();
    final roles = settings.roles.where(
      (role) => _selectedRoleIds.contains(role.id),
    );
    final playerRole = settings.roles
        .where((role) => role.id == _playerSourceRoleId)
        .firstOrNull;
    final playerDescription = _playerDescCtrl.text.trim();
    final player = playerRole == null
        ? provider.customParticipant(
            name: _playerNameCtrl.text,
            description: playerDescription,
            isPlayer: true,
          )
        : provider
              .participantFromChatRole(playerRole, isPlayer: true)
              .copyWith(
                name: _playerNameCtrl.text.trim().isEmpty
                    ? playerRole.name
                    : _playerNameCtrl.text.trim(),
                description: playerDescription,
              );
    final participants = roles
        .where((role) => role.id != _playerSourceRoleId)
        .map((role) => provider.participantFromChatRole(role))
        .toList();
    Navigator.pop(
      context,
      _RoleplayScenarioDraft(
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        scenario: scenario,
        director: RoleplayDirector(model: _directorModel),
        player: player,
        participants: participants,
        groups: const [],
        maxAutoTurns: int.tryParse(_maxAutoCtrl.text.trim()) ?? 3,
      ),
    );
  }
}

class _RoleplayThreadSettingsDraft {
  final String scenario;
  final RoleplayDirector director;
  final int maxAutoTurns;

  const _RoleplayThreadSettingsDraft(
    this.scenario,
    this.director,
    this.maxAutoTurns,
  );
}

class _RoleplayThreadSettingsSheet extends StatefulWidget {
  final RoleplayThread thread;
  final VoidCallback onRoles;

  const _RoleplayThreadSettingsSheet({
    required this.thread,
    required this.onRoles,
  });

  @override
  State<_RoleplayThreadSettingsSheet> createState() =>
      _RoleplayThreadSettingsSheetState();
}

class _RoleplayThreadSettingsSheetState
    extends State<_RoleplayThreadSettingsSheet> {
  late final _scenarioCtrl = TextEditingController(
    text: widget.thread.scenario,
  );
  late final _maxAutoCtrl = TextEditingController(
    text: '${widget.thread.maxAutoTurns}',
  );
  late RoleplayModelSelection _directorModel = widget.thread.director.model;

  @override
  void dispose() {
    _scenarioCtrl.dispose();
    _maxAutoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.tune),
                const SizedBox(width: 8),
                Text('情景设置', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _scenarioCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '当前演绎场景',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maxAutoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'AI连续消息数（0 不限制）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _RoleplayModelSelector(
              value: _directorModel,
              onChanged: (value) => setState(() => _directorModel = value),
              boxLabel: '导演模型',
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.groups_2_outlined),
              title: const Text('当前演绎角色管理'),
              subtitle: const Text('修改只影响这一次演绎'),
              onTap: widget.onRoles,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _RoleplayThreadSettingsDraft(
                    _scenarioCtrl.text.trim(),
                    widget.thread.director.copyWith(model: _directorModel),
                    int.tryParse(_maxAutoCtrl.text.trim()) ?? 3,
                  ),
                ),
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleplayRolesDraft {
  final List<RoleplayParticipant> participants;
  final List<RoleplayParticipantGroup> groups;
  final String playerParticipantId;

  const _RoleplayRolesDraft(
    this.participants,
    this.groups,
    this.playerParticipantId,
  );
}

class _RoleplayRolesDialog extends StatefulWidget {
  final RoleplayThread thread;

  const _RoleplayRolesDialog({required this.thread});

  @override
  State<_RoleplayRolesDialog> createState() => _RoleplayRolesDialogState();
}

class _RoleplayRolesDialogState extends State<_RoleplayRolesDialog> {
  late List<RoleplayParticipant> _participants = List<RoleplayParticipant>.from(
    widget.thread.participants,
  );
  late final List<RoleplayParticipantGroup> _groups =
      List<RoleplayParticipantGroup>.from(widget.thread.groups);
  late String _playerId = widget.thread.playerParticipantId;
  String? _selectedRoleId;

  @override
  Widget build(BuildContext context) {
    final selected = _participants
        .where((item) => item.id == _selectedRoleId)
        .firstOrNull;
    return AlertDialog(
      title: const Text('当前演绎角色管理'),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Row(
          children: [
            SizedBox(width: 310, child: _roleList()),
            const VerticalDivider(),
            Expanded(
              child: selected == null
                  ? const Center(child: Text('选择一个角色'))
                  : _roleDetail(selected),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _RoleplayRolesDraft(_participants, _groups, _playerId),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  Widget _roleList() {
    final grouped = _groups
        .expand(
          (group) => _participants
              .where((role) => role.groupIds.contains(group.id))
              .map((role) => role.id),
        )
        .toSet();
    final ungrouped = _participants
        .where((role) => !grouped.contains(role.id))
        .toList();
    return Stack(
      children: [
        ListView(
          children: [
            _groupTile('未分组', ungrouped),
            for (final group in _groups)
              _groupTile(
                group.name,
                _participants
                    .where((role) => role.groupIds.contains(group.id))
                    .toList(),
                groupId: group.id,
              ),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.small(
            onPressed: _showAddMenu,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  Widget _groupTile(
    String title,
    List<RoleplayParticipant> roles, {
    String? groupId,
  }) {
    return ExpansionTile(
      initiallyExpanded:
          groupId == null || roles.any((role) => role.id == _selectedRoleId),
      title: Text('$title · ${roles.length}'),
      trailing: groupId == null
          ? null
          : IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteGroup(groupId),
            ),
      children: roles.isEmpty
          ? [const ListTile(dense: true, title: Text('暂无角色'))]
          : roles.map((role) {
              return ListTile(
                dense: true,
                selected: role.id == _selectedRoleId,
                leading: Icon(
                  role.isPlayer ? Icons.person : Icons.face_retouching_natural,
                ),
                title: Text(role.isPlayer ? '我：${role.name}' : role.name),
                onTap: () => setState(() => _selectedRoleId = role.id),
              );
            }).toList(),
    );
  }

  Widget _roleDetail(RoleplayParticipant role) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  role.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (!role.isPlayer)
                TextButton.icon(
                  onPressed: () => _setPlayer(role),
                  icon: const Icon(Icons.person),
                  label: const Text('设为我'),
                ),
              if (role.sourceRoleId != null)
                TextButton.icon(
                  onPressed: () => _refreshFromGlobalRole(role),
                  icon: const Icon(Icons.sync, size: 18),
                  label: const Text('刷新'),
                ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _editRole(role),
              ),
              if (!role.isPlayer)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteRole(role.id),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(role.description.isEmpty ? '暂无描述' : role.description),
          const SizedBox(height: 12),
          Text('系统提示词', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(role.systemPrompt.isEmpty ? '暂无' : role.systemPrompt),
          const SizedBox(height: 12),
          Text('分组', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final group in _groups)
                FilterChip(
                  label: Text(group.name),
                  selected: role.groupIds.contains(group.id),
                  onSelected: (selected) =>
                      _toggleRoleGroup(role, group.id, selected),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddMenu() async {
    final value = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 24, 24),
      items: const [
        PopupMenuItem(value: 'role', child: Text('添加角色')),
        PopupMenuItem(value: 'global', child: Text('从全局角色导入')),
        PopupMenuItem(value: 'group', child: Text('添加分组')),
      ],
    );
    if (!mounted) return;
    if (value == 'role') _addRole();
    if (value == 'global') _importGlobalRoles();
    if (value == 'group') _addGroup();
  }

  Future<void> _addRole() async {
    final role = await showDialog<RoleplayParticipant>(
      context: context,
      builder: (_) => const _RoleplayParticipantDialog(),
    );
    if (role == null) return;
    if (!mounted) return;
    setState(() {
      _participants.add(role);
      _selectedRoleId = role.id;
    });
  }

  Future<void> _importGlobalRoles() async {
    final settings = context.read<SettingsProvider>().settings;
    final importedSourceIds = _participants
        .map((role) => role.sourceRoleId)
        .whereType<String>()
        .toSet();
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _RoleplayGlobalRolePickerDialog(
        settings: settings,
        disabledRoleIds: importedSourceIds,
      ),
    );
    if (selected == null || selected.isEmpty) return;
    if (!mounted) return;
    final provider = context.read<RoleplayProvider>();
    final roles = settings.roles.where((role) => selected.contains(role.id));
    setState(() {
      for (final role in roles) {
        _participants.add(provider.participantFromChatRole(role));
      }
      _selectedRoleId = _participants.lastOrNull?.id;
    });
  }

  Future<void> _editRole(RoleplayParticipant role) async {
    final next = await showDialog<RoleplayParticipant>(
      context: context,
      builder: (_) =>
          _RoleplayParticipantDialog(initial: role, groups: _groups),
    );
    if (next == null) return;
    if (!mounted) return;
    setState(() {
      final index = _participants.indexWhere((item) => item.id == role.id);
      if (index != -1) _participants[index] = next;
      if (role.id == _playerId && !next.isPlayer) _playerId = next.id;
    });
  }

  Future<void> _addGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分组名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (name == null || name.isEmpty) return;
    if (!mounted) return;
    setState(
      () =>
          _groups.add(context.read<RoleplayProvider>().createLocalGroup(name)),
    );
  }

  void _deleteGroup(String groupId) {
    setState(() {
      _groups.removeWhere((group) => group.id == groupId);
      _participants = _participants
          .map(
            (role) => role.copyWith(
              groupIds: role.groupIds.where((id) => id != groupId).toList(),
            ),
          )
          .toList();
    });
  }

  void _deleteRole(String roleId) {
    setState(() {
      _participants.removeWhere((role) => role.id == roleId);
      if (_selectedRoleId == roleId) _selectedRoleId = null;
    });
  }

  void _setPlayer(RoleplayParticipant role) {
    setState(() {
      _playerId = role.id;
      _participants = _participants
          .map((item) => item.copyWith(isPlayer: item.id == role.id))
          .toList();
    });
  }

  void _toggleRoleGroup(
    RoleplayParticipant role,
    String groupId,
    bool selected,
  ) {
    final ids = role.groupIds.toSet();
    if (selected) {
      ids.add(groupId);
    } else {
      ids.remove(groupId);
    }
    setState(() {
      final index = _participants.indexWhere((item) => item.id == role.id);
      if (index != -1) {
        _participants[index] = role.copyWith(groupIds: ids.toList());
      }
    });
  }

  void _refreshFromGlobalRole(RoleplayParticipant role) {
    final sourceId = role.sourceRoleId;
    if (sourceId == null) return;
    final settings = context.read<SettingsProvider>().settings;
    final source = settings.roles
        .where((item) => item.id == sourceId)
        .firstOrNull;
    if (source == null) return;
    setState(() {
      final index = _participants.indexWhere((item) => item.id == role.id);
      if (index == -1) return;
      _participants[index] = role.copyWith(
        name: source.name,
        description: source.description,
        systemPrompt: source.systemPrompt,
        model: RoleplayModelSelection(
          modelId: source.modelId,
          modelName: source.modelName,
        ),
        themeColor: source.themeColor?.toARGB32(),
      );
    });
  }
}

class _RoleplayGlobalRolePickerDialog extends StatefulWidget {
  final AppSettings settings;
  final Set<String> disabledRoleIds;

  const _RoleplayGlobalRolePickerDialog({
    required this.settings,
    required this.disabledRoleIds,
  });

  @override
  State<_RoleplayGlobalRolePickerDialog> createState() =>
      _RoleplayGlobalRolePickerDialogState();
}

class _RoleplayGlobalRolePickerDialogState
    extends State<_RoleplayGlobalRolePickerDialog> {
  final Set<String> _selectedIds = {};

  @override
  Widget build(BuildContext context) {
    final roles = widget.settings.roles
        .where((role) => role.id != ChatRole.defaultId)
        .toList(growable: false);
    final roleById = {for (final role in roles) role.id: role};
    final groupedIds = widget.settings.roleGroups
        .expand((group) => group.roleIds)
        .toSet();
    final ungrouped = roles
        .where((role) => !groupedIds.contains(role.id))
        .toList(growable: false);
    return AlertDialog(
      title: const Text('从全局角色导入'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: roles.isEmpty
            ? const Center(child: Text('暂无全局角色'))
            : ListView(
                children: [
                  _groupTile('未分组', ungrouped),
                  for (final group in widget.settings.roleGroups)
                    _groupTile(
                      group.name,
                      group.roleIds
                          .map((id) => roleById[id])
                          .whereType<ChatRole>()
                          .toList(growable: false),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.pop(context, Set<String>.from(_selectedIds)),
          child: const Text('导入'),
        ),
      ],
    );
  }

  Widget _groupTile(String title, List<ChatRole> roles) {
    return ExpansionTile(
      dense: true,
      initiallyExpanded: roles.any((role) => _selectedIds.contains(role.id)),
      title: Text('$title · ${roles.length}'),
      children: roles.isEmpty
          ? [const ListTile(dense: true, title: Text('暂无角色'))]
          : roles.map(_roleTile).toList(),
    );
  }

  Widget _roleTile(ChatRole role) {
    final disabled = widget.disabledRoleIds.contains(role.id);
    return CheckboxListTile(
      dense: true,
      value: disabled ? true : _selectedIds.contains(role.id),
      enabled: !disabled,
      title: Text(role.name),
      subtitle: Text(
        disabled
            ? '已在当前演绎中'
            : role.description.isNotEmpty
            ? role.description
            : role.systemPrompt,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onChanged: (selected) {
        setState(() {
          if (selected == true) {
            _selectedIds.add(role.id);
          } else {
            _selectedIds.remove(role.id);
          }
        });
      },
    );
  }
}

class _RoleplayParticipantDialog extends StatefulWidget {
  final RoleplayParticipant? initial;
  final List<RoleplayParticipantGroup> groups;

  const _RoleplayParticipantDialog({this.initial, this.groups = const []});

  @override
  State<_RoleplayParticipantDialog> createState() =>
      _RoleplayParticipantDialogState();
}

class _RoleplayParticipantDialogState
    extends State<_RoleplayParticipantDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _descCtrl = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late final _promptCtrl = TextEditingController(
    text: widget.initial?.systemPrompt ?? '',
  );
  late RoleplayModelSelection _model =
      widget.initial?.model ?? const RoleplayModelSelection();
  late final Set<String> _groupIds =
      widget.initial?.groupIds.toSet() ?? <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? '添加角色' : '编辑角色'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '描述',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promptCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '系统提示词',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              _RoleplayModelSelector(
                value: _model,
                onChanged: (value) => setState(() => _model = value),
                showNoneOption: true,
                noneLabel: '跟随导演',
                boxLabel: '角色模型',
              ),
              if (widget.groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final group in widget.groups)
                      FilterChip(
                        label: Text(group.name),
                        selected: _groupIds.contains(group.id),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _groupIds.add(group.id);
                            } else {
                              _groupIds.remove(group.id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final initial = widget.initial;
    Navigator.pop(
      context,
      RoleplayParticipant(
        id: initial?.id ?? const Uuid().v4(),
        sourceRoleId: initial?.sourceRoleId,
        name: name,
        description: _descCtrl.text.trim(),
        systemPrompt: _promptCtrl.text.trim(),
        model: _model,
        themeColor: initial?.themeColor,
        isPlayer: initial?.isPlayer ?? false,
        groupIds: _groupIds.toList(),
      ),
    );
  }
}

class _RoleplayModelSelector extends StatefulWidget {
  final RoleplayModelSelection value;
  final ValueChanged<RoleplayModelSelection> onChanged;
  final bool showNoneOption;
  final String noneLabel;
  final String boxLabel;

  const _RoleplayModelSelector({
    required this.value,
    required this.onChanged,
    this.showNoneOption = false,
    this.noneLabel = '跟随导演',
    this.boxLabel = '模型',
  });

  @override
  State<_RoleplayModelSelector> createState() => _RoleplayModelSelectorState();
}

class _RoleplayModelSelectorState extends State<_RoleplayModelSelector> {
  @override
  Widget build(BuildContext context) {
    return ModelConfigPicker(
      title: widget.boxLabel,
      category: ModelConfig.categoryChat,
      value: _pickerValue,
      allowClear: widget.showNoneOption,
      emptyLabel: widget.showNoneOption ? widget.noneLabel : '无可用模型',
      onChanged: (value) => widget.onChanged(_roleplayValue(value)),
    );
  }

  ModelSelectionValue? get _pickerValue {
    final modelId = widget.value.modelId;
    if (modelId == null || modelId.isEmpty) return null;
    return ModelSelectionValue(
      modelId: modelId,
      modelName: widget.value.modelName,
      category: ModelConfig.categoryChat,
    );
  }

  RoleplayModelSelection _roleplayValue(ModelSelectionValue? value) {
    if (value == null) return const RoleplayModelSelection();
    return RoleplayModelSelection(
      modelId: value.modelId,
      modelName: value.modelName,
    );
  }
}

class _RoleplayShareImage extends StatelessWidget {
  final RoleplayThread thread;
  final List<RoleplayMessage> messages;
  final Color seedColor;
  final bool isDark;
  final int? pageNumber;
  final int? pageCount;

  const _RoleplayShareImage({
    required this.thread,
    required this.messages,
    required this.seedColor,
    required this.isDark,
    this.pageNumber,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.06 : 0.025,
    )!;
    final cardBg = scheme.surface;
    final shadowColor = isDark ? Colors.black : scheme.shadow;
    final player = thread.participants.firstWhere(
      (item) => item.isPlayer,
      orElse: () => thread.participants.first,
    );
    final characters = thread.participants
        .where((item) => !item.isPlayer)
        .toList(growable: false);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: bgColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ExportHeader(
              title: thread.title,
              scenario: thread.scenario,
              playerName: player.name,
              characters: characters,
              scheme: scheme,
              mutedColor: mutedColor,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: isDark ? 0.18 : 0.06),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < messages.length; i++) ...[
                    _ExportBubble(messages[i], scheme, isDark, mutedColor),
                    if (i != messages.length - 1) const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Shared from LynAI'
                  : 'Shared from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 14,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportHeader extends StatelessWidget {
  final String title;
  final String scenario;
  final String playerName;
  final List<RoleplayParticipant> characters;
  final ColorScheme scheme;
  final Color mutedColor;

  const _ExportHeader({
    required this.title,
    required this.scenario,
    required this.playerName,
    required this.characters,
    required this.scheme,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.theater_comedy_outlined,
                color: scheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isNotEmpty ? title : '情景演绎',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    scenario,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: mutedColor,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _exportChip('我：$playerName', scheme.primary, scheme),
            for (final role in characters)
              _exportChip(role.name, scheme.secondary, scheme),
          ],
        ),
      ],
    );
  }

  Widget _exportChip(String text, Color color, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ExportBubble extends StatelessWidget {
  final RoleplayMessage message;
  final ColorScheme scheme;
  final bool isDark;
  final Color mutedColor;

  const _ExportBubble(this.message, this.scheme, this.isDark, this.mutedColor);

  @override
  Widget build(BuildContext context) {
    final isPlayer = message.kind == RoleplayMessageKind.player;
    final isNarrator = message.kind == RoleplayMessageKind.narrator;

    if (isNarrator) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: mutedColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: MarkdownWithLatex(
          content: message.content,
          selectable: false,
          wrapCodeBlocks: true,
          textStyle: TextStyle(
            fontStyle: FontStyle.italic,
            color: mutedColor,
            fontSize: 16,
            height: 1.5,
          ),
        ),
      );
    }

    final bubbleColor = isPlayer
        ? scheme.primaryContainer.withValues(alpha: 0.55)
        : scheme.surfaceContainerHighest;
    final textColor = isPlayer ? scheme.onPrimaryContainer : scheme.onSurface;
    final speakerColor = isPlayer ? scheme.primary : scheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.speakerName,
          style: TextStyle(
            color: speakerColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 580),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.content.trim().isNotEmpty)
                MarkdownWithLatex(
                  content: message.content.trim(),
                  selectable: false,
                  wrapCodeBlocks: true,
                  textStyle: TextStyle(
                    fontSize: 17,
                    height: 1.5,
                    color: textColor,
                  ),
                ),
              if (message.attachments.isNotEmpty &&
                  message.content.trim().isNotEmpty)
                const SizedBox(height: 10),
              if (message.attachments.isNotEmpty)
                _ExportAttachmentStrip(attachments: message.attachments),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportAttachmentStrip extends StatelessWidget {
  final List<MessageImage> attachments;

  const _ExportAttachmentStrip({required this.attachments});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map((attachment) {
        final file = File(attachment.path);
        if (!file.existsSync()) return const SizedBox.shrink();
        if (!attachment.isImage) {
          return Container(
            width: 220,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(file, width: 140, height: 140, fit: BoxFit.cover),
        );
      }).toList(),
    );
  }
}
