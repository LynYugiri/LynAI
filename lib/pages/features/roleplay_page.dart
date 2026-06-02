part of '../feature_page.dart';

class _RoleplayPage extends StatefulWidget {
  const _RoleplayPage();

  @override
  State<_RoleplayPage> createState() => _RoleplayPageState();
}

class _RoleplayPageState extends State<_RoleplayPage> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _service = RoleplayService();
  final _screenshotCtrl = ScreenshotController();
  String? _selectedSessionId;
  bool _exporting = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RoleplayProvider>();
    final selectedId = _selectedSessionId;
    final session = selectedId == null ? null : provider.getSession(selectedId);
    if (session != null) return _detail(provider, session);
    return _sessionList(provider);
  }

  Widget _sessionList(RoleplayProvider provider) {
    final sessions = provider.sessions;
    return Scaffold(
      body: sessions.isEmpty
          ? _emptyState()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.theater_comedy_outlined),
                    ),
                    title: Text(session.title),
                    subtitle: Text(
                      '${session.characters.length} 个角色 · ${session.scenario}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmDelete(provider, session),
                    ),
                    onTap: () =>
                        setState(() => _selectedSessionId = session.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createSession,
        icon: const Icon(Icons.add),
        label: const Text('新建演绎'),
      ),
    );
  }

  Widget _emptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.theater_comedy_outlined,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            Text('还没有情景演绎', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '创建场景，加入角色分组或单个角色，让系统导演调度多角色对话。',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _createSession,
              icon: const Icon(Icons.add),
              label: const Text('新建演绎'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    RoleplayProvider provider,
    RoleplaySession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除演绎'),
        content: Text('确定删除"${session.title}"吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      provider.deleteSession(session.id);
      setState(() => _selectedSessionId = null);
    }
  }

  Widget _detail(RoleplayProvider provider, RoleplaySession session) {
    final running =
        provider.activeSessionId == session.id &&
        provider.runState != RoleplayRunState.idle &&
        provider.runState != RoleplayRunState.waitingUser &&
        provider.runState != RoleplayRunState.error;
    final pendingMessages = provider.pendingPlayerMessages(session.id);
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: '演绎列表',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () =>
                          setState(() => _selectedSessionId = null),
                    ),
                    Expanded(
                      child: Text(
                        session.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: running ? null : () => _advance(session.id),
                      child: const Text('继续演绎'),
                    ),
                    if (session.messages.isNotEmpty && !running)
                      PopupMenuButton<String>(
                        tooltip: '导出',
                        icon: const Icon(Icons.ios_share),
                        onSelected: (value) {
                          switch (value) {
                            case 'markdown':
                              _exportMarkdown(session);
                            case 'image':
                              _exportImage(session);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'markdown',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.description_outlined),
                              title: Text('导出 Markdown'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'image',
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.image_outlined),
                              title: Text('导出长图'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Text(
                  session.scenario,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final role in session.participants)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          role.isPlayer ? '我：${role.name}' : role.name,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              for (final message in session.messages) _messageBubble(message),
              if (provider.activeSessionId == session.id &&
                  provider.activeSpeakerName != null)
                _draftBubble(provider),
              if (pendingMessages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${pendingMessages.length} 条抢话已排队，将在当前输出后插入',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              if (provider.activeSessionId == session.id &&
                  provider.runState == RoleplayRunState.error &&
                  provider.errorMessage != null)
                _errorBanner(provider.errorMessage!),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputCtrl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: running
                          ? '抢话，会在当前输出后插入'
                          : '以 ${session.player?.name ?? '我'} 发言',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _submitPlayer(session.id, running),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _submitPlayer(session.id, running),
                  child: Text(running ? '抢话' : '发送'),
                ),
              ],
            ),
          ),
        ),
      ],
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
          constraints: const BoxConstraints(maxWidth: 540),
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            message.content,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Align(
      alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isPlayer
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
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
            const SizedBox(height: 4),
            Text(message.content),
          ],
        ),
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
            Text(
              provider.draftContent == null || provider.draftContent!.isEmpty
                  ? '正在思考...'
                  : provider.draftContent!,
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }

  Future<void> _createSession() async {
    final models = context.read<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    if (models.isEmpty) {
      showShortSnackBar(context, '请先在设置中配置聊天模型');
      return;
    }
    final result = await showDialog<_RoleplayDraft>(
      context: context,
      builder: (_) => const _RoleplayCreateDialog(),
    );
    if (!mounted || result == null) return;
    final id = context.read<RoleplayProvider>().createSession(
      title: result.title,
      scenario: result.scenario,
      director: RoleplayDirector(modelId: result.directorModelId),
      participants: result.participants,
      playerParticipantId: result.playerId,
      maxAutoTurns: result.maxAutoTurns,
    );
    setState(() => _selectedSessionId = id);
    await _advance(id);
  }

  void _submitPlayer(String sessionId, bool running) {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    final provider = context.read<RoleplayProvider>();
    if (running) {
      provider.queuePlayerMessage(sessionId, text);
      return;
    }
    provider.appendPlayerMessage(sessionId, text);
    _advance(sessionId);
  }

  Future<void> _advance(String sessionId) async {
    final provider = context.read<RoleplayProvider>();
    if (!provider.tryStartRun(sessionId)) return;
    final modelProvider = context.read<ModelConfigProvider>();
    var autoTurns = 0;
    while (mounted) {
      var session = provider.getSession(sessionId);
      if (session == null) return;
      for (final message in provider.drainPendingPlayerMessages(sessionId)) {
        provider.appendPlayerMessage(sessionId, message);
      }
      session = provider.getSession(sessionId);
      if (session == null) return;
      if (autoTurns >= session.maxAutoTurns) {
        provider.setRunState(
          RoleplayRunState.waitingUser,
          sessionId: sessionId,
        );
        return;
      }
      provider.setRunState(
        RoleplayRunState.directing,
        sessionId: sessionId,
        speakerName: '系统',
      );
      final directorModel = _modelFor(session.director.modelId, modelProvider);
      if (directorModel == null) {
        provider.setRunState(
          RoleplayRunState.error,
          sessionId: sessionId,
          errorMessage: '没有可用聊天模型',
        );
        return;
      }
      try {
        final decision = await _service.decideNext(
          session: session,
          model: directorModel,
        );
        if (!mounted) return;
        for (final message in provider.drainPendingPlayerMessages(sessionId)) {
          provider.appendPlayerMessage(sessionId, message);
        }
        session = provider.getSession(sessionId);
        if (session == null) return;
        if (decision.isNarrator) {
          provider.setRunState(RoleplayRunState.idle, sessionId: sessionId);
          provider.appendNarratorMessage(
            sessionId,
            decision.content ?? decision.reason,
          );
          autoTurns++;
          _scrollToBottom();
          continue;
        }
        if (decision.waitsForUser || decision.speakerId == null) {
          provider.setRunState(
            RoleplayRunState.waitingUser,
            sessionId: sessionId,
          );
          return;
        }
        RoleplayParticipant? participant;
        for (final role in session.characters) {
          if (role.id == decision.speakerId) participant = role;
        }
        participant ??= session.characters.isEmpty
            ? null
            : session.characters.first;
        if (participant == null) {
          provider.setRunState(
            RoleplayRunState.waitingUser,
            sessionId: sessionId,
          );
          return;
        }
        final model =
            _modelFor(participant.modelId, modelProvider) ?? directorModel;
        provider.setRunState(
          RoleplayRunState.speaking,
          sessionId: sessionId,
          speakerName: participant.name,
          draftContent: '',
        );
        final content = await _streamParticipantSpeech(
          provider,
          session,
          participant,
          model,
        );
        if (!mounted) return;
        provider.appendCharacterMessage(
          sessionId,
          participant,
          content.isEmpty ? '（沉默）' : content,
        );
        autoTurns++;
        _scrollToBottom();
      } catch (e) {
        provider.setRunState(
          RoleplayRunState.error,
          sessionId: sessionId,
          errorMessage: '$e',
        );
        showShortSnackBar(context, '演绎生成失败: $e');
        return;
      }
    }
  }

  Future<String> _streamParticipantSpeech(
    RoleplayProvider provider,
    RoleplaySession session,
    RoleplayParticipant participant,
    ModelConfig model,
  ) async {
    final buffer = StringBuffer();
    await for (final chunk in _service.speakStream(
      session: session,
      participant: participant,
      model: model,
    )) {
      if (!mounted) break;
      final content = chunk.content;
      if (content != null && content.isNotEmpty) {
        buffer.write(content);
        provider.updateDraft(buffer.toString());
        _scrollToBottom();
      }
      if (chunk.isDone) break;
    }
    return buffer.toString().trim();
  }

  ModelConfig? _modelFor(String? modelId, ModelConfigProvider provider) {
    final models = provider.modelsByCategory(ModelConfig.categoryChat);
    if (models.isEmpty) return null;
    if (modelId != null && modelId.isNotEmpty) {
      for (final model in models) {
        if (model.id == modelId) return model;
      }
    }
    return models.first;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _exportMarkdown(RoleplaySession session) async {
    final buffer = StringBuffer();
    buffer.writeln('# ${session.title}');
    buffer.writeln();
    buffer.writeln('> ${session.scenario}');
    buffer.writeln();
    final participants = session.participants
        .map((role) => role.isPlayer ? '我：${role.name}' : role.name)
        .join('、');
    buffer.writeln('**参演角色**：$participants');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    for (final message in session.messages) {
      switch (message.kind) {
        case RoleplayMessageKind.narrator:
          buffer.writeln('*${message.content}*');
          buffer.writeln();
        default:
          buffer.writeln('**${message.speakerName}**：');
          buffer.writeln(message.content);
          buffer.writeln();
      }
    }
    final baseName = safeExportFileName(session.title, fallback: 'roleplay');
    final fileName = baseName.length > 64
        ? '${baseName.substring(0, 64)}.md'
        : '$baseName.md';
    await shareTextFile(
      fileName: fileName,
      content: buffer.toString(),
      text: session.title,
    );
  }

  Future<void> _exportImage(RoleplaySession session) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    try {
      final messages = session.messages;
      final pages = _messageImagePages(messages);
      final images = <Uint8List>[];
      for (var i = 0; i < pages.length; i++) {
        final shareWidget = _RoleplayShareImage(
          title: session.title,
          scenario: session.scenario,
          messages: pages[i],
          seedColor: scheme.primary,
          isDark: isDark,
          pageNumber: pages.length > 1 ? i + 1 : null,
          pageCount: pages.length > 1 ? pages.length : null,
        );
        images.add(await _captureShareWidget(shareWidget));
      }
      if (!mounted) return;
      if (images.isEmpty) {
        showShortSnackBar(context, '生成长图失败，请重试');
        return;
      }
      final exportPrefix = safeExportFileName(
        session.title,
        fallback: 'roleplay_export',
      );
      await shareOrSavePngImages(
        images: images,
        filePrefix: exportPrefix.length > 40
            ? exportPrefix.substring(0, 40)
            : exportPrefix,
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

  Future<Uint8List> _captureShareWidget(Widget widget) async {
    return await _screenshotCtrl.captureFromLongWidget(widget, pixelRatio: 2.5);
  }

  List<List<RoleplayMessage>> _messageImagePages(
    List<RoleplayMessage> messages,
  ) {
    const maxWeight = 2800;
    final pages = <List<RoleplayMessage>>[];
    var current = <RoleplayMessage>[];
    var currentWeight = 0;
    for (final message in messages) {
      final weight = message.content.length;
      if (current.isNotEmpty && currentWeight + weight > maxWeight) {
        pages.add(current);
        current = [];
        currentWeight = 0;
      }
      current.add(message);
      currentWeight += weight;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }
}

class _RoleplayShareImage extends StatelessWidget {
  final String title;
  final String scenario;
  final List<RoleplayMessage> messages;
  final Color seedColor;
  final bool isDark;
  final int? pageNumber;
  final int? pageCount;

  const _RoleplayShareImage({
    required this.title,
    required this.scenario,
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
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
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
            Text(
              title.isNotEmpty ? title : '情景演绎',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(scenario, style: TextStyle(color: mutedColor, fontSize: 16)),
            const SizedBox(height: 22),
            for (var i = 0; i < messages.length; i++) ...[
              _ShareRoleplayBubble(
                message: messages[i],
                scheme: scheme,
                isDark: isDark,
              ),
              if (i != messages.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 18),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Shared from LynAI'
                  : 'Shared from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRoleplayBubble extends StatelessWidget {
  final RoleplayMessage message;
  final ColorScheme scheme;
  final bool isDark;

  const _ShareRoleplayBubble({
    required this.message,
    required this.scheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isPlayer = message.kind == RoleplayMessageKind.player;
    final isNarrator = message.kind == RoleplayMessageKind.narrator;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    if (isNarrator) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.content,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: mutedColor,
            fontSize: 18,
            height: 1.45,
          ),
        ),
      );
    }

    final bubbleColor = isPlayer
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isPlayer ? scheme.onPrimaryContainer : scheme.onSurface;
    return Column(
      crossAxisAlignment: isPlayer
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.speakerName,
          style: TextStyle(
            color: mutedColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: Radius.circular(isPlayer ? 22 : 6),
              bottomRight: Radius.circular(isPlayer ? 6 : 22),
            ),
          ),
          child: Text(
            message.content,
            style: TextStyle(fontSize: 20, height: 1.45, color: textColor),
          ),
        ),
      ],
    );
  }
}

class _RoleplayDraft {
  final String title;
  final String scenario;
  final String playerId;
  final String? directorModelId;
  final int maxAutoTurns;
  final List<RoleplayParticipant> participants;

  const _RoleplayDraft({
    required this.title,
    required this.scenario,
    required this.playerId,
    required this.directorModelId,
    required this.maxAutoTurns,
    required this.participants,
  });
}

class _RoleplayCreateDialog extends StatefulWidget {
  const _RoleplayCreateDialog();

  @override
  State<_RoleplayCreateDialog> createState() => _RoleplayCreateDialogState();
}

class _RoleplayCreateDialogState extends State<_RoleplayCreateDialog> {
  final _titleCtrl = TextEditingController();
  final _scenarioCtrl = TextEditingController();
  final _playerNameCtrl = TextEditingController(text: '我');
  final _playerDescCtrl = TextEditingController();
  final Set<String> _selectedRoleIds = {};
  int _maxAutoTurns = 3;
  String? _directorModelId;
  bool _directorModelInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_directorModelInitialized) return;
    final models = context.read<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    _directorModelId = models.isEmpty ? null : models.first.id;
    _directorModelInitialized = true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _scenarioCtrl.dispose();
    _playerNameCtrl.dispose();
    _playerDescCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final models = context.watch<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    if (_directorModelId != null &&
        !models.any((model) => model.id == _directorModelId)) {
      _directorModelId = models.isEmpty ? null : models.first.id;
    }
    return AlertDialog(
      title: const Text('新建情景演绎'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(
                  labelText: '标题（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _scenarioCtrl,
                minLines: 3,
                maxLines: 6,
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
                    width: 120,
                    child: DropdownButtonFormField<int>(
                      initialValue: _maxAutoTurns,
                      decoration: const InputDecoration(
                        labelText: '自动轮数',
                        border: OutlineInputBorder(),
                      ),
                      items: const [1, 2, 3, 4, 5]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _maxAutoTurns = value ?? 3),
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
              DropdownButtonFormField<String>(
                initialValue: _directorModelId,
                decoration: const InputDecoration(
                  labelText: '系统/导演模型',
                  border: OutlineInputBorder(),
                ),
                items: models
                    .map(
                      (model) => DropdownMenuItem(
                        value: model.id,
                        child: Text('${model.name} / ${model.modelName}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _directorModelId = value),
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
        FilledButton(onPressed: () => _save(settings), child: const Text('开始')),
      ],
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
        .toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: Text('参演角色 · ${_selectedRoleIds.length}'),
            subtitle: const Text('可展开分组，或一键加入整组'),
          ),
          const Divider(height: 1),
          _selectGroup(
            '未分组',
            ungrouped,
            defaultExpanded: _selectedRoleIds.isEmpty,
          ),
          for (final group in settings.roleGroups)
            _selectGroup(
              group.name,
              group.roleIds
                  .map((id) => roleById[id])
                  .whereType<ChatRole>()
                  .toList(),
              defaultExpanded: group.roleIds.any(_selectedRoleIds.contains),
            ),
        ],
      ),
    );
  }

  Widget _selectGroup(
    String title,
    List<ChatRole> roles, {
    required bool defaultExpanded,
  }) {
    return ExpansionTile(
      key: ValueKey('roleplay-create-$title'),
      initiallyExpanded: defaultExpanded,
      title: Text('$title · ${roles.length}'),
      trailing: TextButton(
        onPressed: roles.isEmpty
            ? null
            : () => setState(() {
                for (final role in roles) {
                  _selectedRoleIds.add(role.id);
                }
              }),
        child: const Text('加入整组'),
      ),
      children: roles.isEmpty
          ? [const ListTile(dense: true, title: Text('暂无角色'))]
          : roles.map((role) {
              return CheckboxListTile(
                dense: true,
                value: _selectedRoleIds.contains(role.id),
                title: Text(role.name),
                subtitle: Text(
                  role.description.isNotEmpty
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
            }).toList(),
    );
  }

  void _save(AppSettings settings) {
    final scenario = _scenarioCtrl.text.trim();
    final playerName = _playerNameCtrl.text.trim();
    if (scenario.isEmpty || playerName.isEmpty || _selectedRoleIds.isEmpty) {
      return;
    }
    const uuid = Uuid();
    final playerId = uuid.v4();
    final roles = settings.roles.where(
      (role) => _selectedRoleIds.contains(role.id),
    );
    final participants = <RoleplayParticipant>[
      RoleplayParticipant(
        id: playerId,
        name: playerName,
        description: _playerDescCtrl.text.trim(),
        systemPrompt: _playerDescCtrl.text.trim(),
        isPlayer: true,
      ),
      for (final role in roles)
        RoleplayParticipant(
          id: uuid.v4(),
          sourceRoleId: role.id,
          name: role.name,
          description: role.description,
          systemPrompt: role.systemPrompt,
          modelId: role.modelId,
          themeColor: role.themeColor?.toARGB32(),
        ),
    ];
    Navigator.pop(
      context,
      _RoleplayDraft(
        title: _titleCtrl.text.trim(),
        scenario: scenario,
        playerId: playerId,
        directorModelId: _directorModelId,
        maxAutoTurns: _maxAutoTurns,
        participants: participants,
      ),
    );
  }
}
