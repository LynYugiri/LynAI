import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../widgets/latex_renderer.dart';

class ChatPage extends StatefulWidget {
  final String? conversationId;
  final VoidCallback? onConversationLoaded;
  const ChatPage({super.key, this.conversationId, this.onConversationLoaded});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _screenshotCtrl = ScreenshotController();
  final _api = ApiService();

  String? _convId;
  bool _thinking = true;
  bool _streaming = false;
  bool _showAttach = false;
  bool _showModelMenu = false;
  bool _showSubModels = false;
  bool _recording = false;
  String? _thinkingTxt;
  bool _thinkExpanded = false;
  final Map<String, String?> _thinkMap = {};

  late stt.SpeechToText _speech;
  StreamSubscription<StreamChunk>? _sub;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    if (widget.conversationId != null) {
      _convId = widget.conversationId;
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void didUpdateWidget(ChatPage old) {
    super.didUpdateWidget(old);
    if (widget.conversationId != null && widget.conversationId != _convId) {
      setState(() {
        _convId = widget.conversationId;
        _thinkingTxt = _thinkMap[_convId];
        _thinkExpanded = false;
      });
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose(); _scrollCtrl.dispose(); _focusNode.dispose(); _sub?.cancel();
    super.dispose();
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  ModelConfig? _getModel(ModelConfigProvider mp) {
    if (mp.models.isEmpty) return null;
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(_convId!);
      if (conv != null) {
        try { return mp.models.firstWhere((m) => m.id == conv.modelId); } catch (_) {}
      }
    }
    return mp.models.first;
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    if (mp.models.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在设置中添加 AI 模型')));
      return;
    }
    final model = _getModel(mp);
    if (model == null) return;
    if (_convId == null) _convId = cp.createConversation(model.id);
    cp.addMessage(_convId!, 'user', text);
    _msgCtrl.clear();
    _scrollEnd();
    cp.addMessage(_convId!, 'assistant', '');
    setState(() { _streaming = true; _thinkingTxt = null; });
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final msgs = conv.messages
        .where((m) => m.role != 'assistant' || m.content.isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content}).toList();
    if (msgs.isNotEmpty && msgs.last['role'] == 'assistant') msgs.removeLast();
    _doStream(model, msgs);
  }

  void _doStream(ModelConfig model, List<Map<String, String>> msgs) {
    final cp = context.read<ConversationProvider>();
    final cid = _convId!;
    final stream = _api.sendStreamRequest(model, msgs, thinking: _thinking);
    String buf = '', thinkBuf = '';
    _sub?.cancel();
    _sub = stream.listen((chunk) {
      if (!mounted) return;
      if (chunk.content != null) buf += chunk.content!;
      if (chunk.reasoningContent != null) thinkBuf += chunk.reasoningContent!;
      if (chunk.isDone) {
        setState(() { _streaming = false; if (thinkBuf.isNotEmpty) { _thinkingTxt = thinkBuf; _thinkMap[cid] = thinkBuf; } });
        cp.updateLastMessage(cid, buf);
      } else {
        cp.updateLastMessage(cid, buf);
        if (thinkBuf.isNotEmpty) setState(() => _thinkingTxt = thinkBuf);
      }
      _scrollEnd();
    }, onError: (e) {
      if (!mounted) return;
      setState(() => _streaming = false);
      cp.updateLastMessage(cid, '请求失败: $e');
    }, onDone: () {
      if (!mounted) return;
      setState(() => _streaming = false);
    });
  }

  void _switchModel(ModelConfig model) {
    if (_convId != null) context.read<ConversationProvider>().updateConversationTitle(_convId!, model.name);
    setState(() {});
  }

  void _setSubModel(ModelConfig config, String modelName) {
    final mp = context.read<ModelConfigProvider>();
    mp.updateModel(config.copyWith(modelName: modelName));
    _switchModel(config);
    setState(() => _showSubModels = false);
  }

  void _retry() {
    if (_convId == null || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    if (conv.messages.isNotEmpty && conv.messages.last.role == 'assistant') {
      cp.deleteMessage(_convId!, conv.messages.last.id);
    }
    final um = conv.messages.where((m) => m.role == 'user').toList();
    if (um.isNotEmpty) { _msgCtrl.text = um.last.content; _send(); }
  }

  void _copy(String c) {
    Clipboard.setData(ClipboardData(text: c));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
  }

  Future<void> _shareImg() async {
    try {
      final bytes = await _screenshotCtrl.capture(pixelRatio: 2.0);
      if (bytes == null) return;
      final f = File('${Directory.systemTemp.path}/lynai_${DateTime.now().millisecondsSinceEpoch}.png');
      await f.writeAsBytes(bytes);
      if (mounted) await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'LynAI 对话'));
    } catch (_) {}
  }

  Future<void> _pickImg() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    if (mp.models.isEmpty) return;
    final model = _getModel(mp);
    if (model == null) return;
    final set = context.read<SettingsProvider>().settings;
    if (_convId == null) _convId = cp.createConversation(model.id);
    final f = File(picked.path);
    final sz = await f.length();
    cp.addMessage(_convId!, 'user', '[图片: ${picked.name} (${_fmtSz(sz)})]');
    _scrollEnd();
    if (set.imageModelId != null && set.imageModelId!.isNotEmpty) {
      try {
        final imgModel = mp.models.firstWhere((m) => m.id == set.imageModelId);
        cp.addMessage(_convId!, 'assistant', '');
        setState(() => _streaming = true);
        final resp = await _api.sendChatRequest(imgModel, [{'role': 'user', 'content': set.imagePrompt}], thinking: false);
        cp.updateLastMessage(_convId!, '[图片转述] ${resp.content}');
        setState(() => _streaming = false);
        cp.addMessage(_convId!, 'assistant', '');
        final cmsgs = cp.getConversation(_convId!)!.messages
            .where((m) => m.role != 'assistant' || m.content.isNotEmpty)
            .map((m) => {'role': m.role, 'content': m.content}).toList();
        if (cmsgs.isNotEmpty && cmsgs.last['role'] == 'assistant') cmsgs.removeLast();
        _doStream(model, cmsgs);
      } catch (e) {
        setState(() => _streaming = false);
        cp.updateLastMessage(_convId!, '图片转述失败: $e');
      }
    }
  }

  Future<void> _voice() async {
    final set = context.read<SettingsProvider>().settings;
    if (set.speechModelId == null || set.speechModelId!.isEmpty) { _send(); return; }
    final ok = await _speech.initialize(
      onStatus: (s) { if (s == 'done' || s == 'notListening') setState(() => _recording = false); },
      onError: (_) => setState(() => _recording = false),
    );
    if (ok) {
      setState(() => _recording = true);
      _speech.listen(onResult: (r) {
        _msgCtrl.text = r.recognizedWords;
        if (r.finalResult) { setState(() => _recording = false); _processSpeech(r.recognizedWords); }
      }, localeId: 'zh_CN');
    }
  }

  Future<void> _processSpeech(String txt) async {
    if (txt.trim().isEmpty) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final model = _getModel(mp);
    if (model == null) return;
    if (_convId == null) _convId = cp.createConversation(model.id);
    cp.addMessage(_convId!, 'user', txt);
    _msgCtrl.clear();
    _scrollEnd();
    cp.addMessage(_convId!, 'assistant', '');
    setState(() => _streaming = true);
    try {
      final sm = mp.models.firstWhere((m) => m.id == context.read<SettingsProvider>().settings.speechModelId);
      final resp = await _api.sendChatRequest(sm, [
        {'role': 'user', 'content': '请整理修正以下语音识别结果，直接输出修正后的文字:\n$txt'}
      ], thinking: false);
      cp.updateLastMessage(_convId!, resp.content.trim());
      cp.addMessage(_convId!, 'assistant', '');
      final cmsgs = cp.getConversation(_convId!)!.messages
          .where((m) => m.role != 'assistant' || m.content.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.content}).toList();
      if (cmsgs.isNotEmpty && cmsgs.last['role'] == 'assistant') cmsgs.removeLast();
      _doStream(model, cmsgs);
    } catch (e) {
      setState(() => _streaming = false);
      cp.updateLastMessage(_convId!, '语音处理失败: $e');
    }
  }

  void _stopVoice() { _speech.stop(); setState(() => _recording = false); }

  void _selectHistory(String cid) {
    setState(() { _convId = cid; _thinkingTxt = _thinkMap[cid]; _thinkExpanded = false; });
    Navigator.pop(context);
  }

  String _fmtSz(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  void _showDialogSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _DialogSettingsContent(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ConversationProvider>();
    final mp = context.watch<ModelConfigProvider>();
    final model = _getModel(mp);
    final conv = cp.getConversation(_convId ?? '');
    return Scaffold(
      appBar: AppBar(
        leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.history), tooltip: '历史记录', onPressed: () => Scaffold.of(ctx).openDrawer())),
        title: Text(conv?.title ?? '新对话'), centerTitle: true,
        actions: [
          if (_convId != null)
            IconButton(icon: const Icon(Icons.add_comment_outlined), tooltip: '新建对话',
                onPressed: () => setState(() { _convId = null; _thinkingTxt = null; })),
        ],
      ),
      drawer: _drawer(context),
      body: Screenshot(controller: _screenshotCtrl, child: _body(conv, model, mp)),
    );
  }

  Widget _drawer(BuildContext ctx) => Drawer(
    child: _HistoryDrawer(onSelect: _selectHistory, currentConvId: _convId),
  );

  Widget _body(dynamic conv, ModelConfig? model, ModelConfigProvider mp) {
    final msgs = conv?.messages ?? <dynamic>[];
    return Column(children: [
      Expanded(child: msgs.isEmpty ? _empty() : ListView.builder(
        controller: _scrollCtrl, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: msgs.length,
        itemBuilder: (_, i) => _bubble(msgs[i], i == msgs.length - 1),
      )),
      _inputArea(model, mp),
    ]);
  }

  Widget _empty() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]), const SizedBox(height: 16),
    Text('开始新对话', style: TextStyle(fontSize: 20, color: Colors.grey[500], fontWeight: FontWeight.w300)),
    const SizedBox(height: 8), Text('在下方输入你的问题', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
  ]));

  Widget _bubble(dynamic msg, bool isLastAi) {
    final u = msg.role == 'user';
    if (u) {
      return Align(alignment: Alignment.centerRight, child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16))),
        child: SelectableText(msg.content, style: const TextStyle(fontSize: 15)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_thinkingTxt != null && _thinkingTxt!.isNotEmpty && isLastAi) _thinkSection(),
      Container(
        margin: const EdgeInsets.symmetric(vertical: 4), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomRight: Radius.circular(16))),
        child: msg.content.isEmpty && _streaming
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : MarkdownWithLatex(content: msg.content),
      ),
      if (!_streaming && msg.content.isNotEmpty) _actions(msg.content),
    ]);
  }

  Widget _thinkSection() => Container(
    margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
    decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3), width: 2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _thinkExpanded = !_thinkExpanded),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_thinkExpanded ? Icons.expand_less : Icons.expand_more, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4), Text('思考过程', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
        ])),
      ),
      if (_thinkExpanded)
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), child: Text(_thinkingTxt!,
            style: TextStyle(fontSize: 11, color: Colors.grey[400], fontStyle: FontStyle.italic))),
    ]),
  );

  Widget _actions(String c) => Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
    _actBtn(Icons.copy, () => _copy(c)), const SizedBox(width: 4),
    _actBtn(Icons.share, _shareImg), const SizedBox(width: 4),
    _actBtn(Icons.refresh, _retry),
  ]));

  Widget _actBtn(IconData i, VoidCallback t) => InkWell(onTap: t, borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(i, size: 16, color: Colors.grey[400])));

  Widget _inputArea(ModelConfig? model, ModelConfigProvider mp) {
    final set = context.read<SettingsProvider>().settings;
    final hasSpeech = set.speechModelId != null && set.speechModelId!.isNotEmpty;
    return Container(
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, -2))]),
      padding: EdgeInsets.only(left: 8, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_showModelMenu) _modelList(mp),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          _modelSel(model, mp), const SizedBox(width: 4),
          Expanded(child: _recording ? _recOverlay() : TextField(
            controller: _msgCtrl, focusNode: _focusNode,
            style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
            decoration: const InputDecoration(hintText: '输入消息...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
            maxLines: 5, minLines: 1, textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(), onChanged: (_) => setState(() {}),
          )),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _dialogSetBtn(), const SizedBox(width: 4),
          _thinkBtn(), const Spacer(),
          _attachBtn(), const SizedBox(width: 4),
          _voiceOrSendBtn(hasSpeech),
        ]),
        if (_showAttach) _attachMenu(),
      ]),
    );
  }

  Widget _modelList(ModelConfigProvider mp) {
    final cur = _getModel(mp);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: ListView.builder(
        shrinkWrap: true, itemCount: mp.models.length,
        itemBuilder: (_, i) {
          final m = mp.models[i];
          final sel = cur != null && m.id == cur.id;
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              dense: true, leading: Icon(sel ? Icons.check_circle : Icons.circle_outlined, size: 18,
                  color: sel ? Theme.of(context).colorScheme.primary : Colors.grey),
              title: Text(m.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(m.hasMultipleModels ? '${m.enabledModelNames.length} 个模型' : m.modelName, style: const TextStyle(fontSize: 11)),
              trailing: m.hasMultipleModels ? const Icon(Icons.chevron_right, size: 16) : null,
              onTap: () {
                if (m.hasMultipleModels) {
                  _showSubModels = true;
                  // will expand sub-models
                  _switchModel(m);
                } else {
                  _switchModel(m);
                  setState(() => _showModelMenu = false);
                }
              },
            ),
            // Show enabled sub-models when this provider is selected and has multiple
            if (sel && m.hasMultipleModels)
              ...m.models.where((e) => e.enabled).map((e) => ListTile(
                dense: true, contentPadding: const EdgeInsets.only(left: 56),
                leading: Icon(e.name == m.modelName ? Icons.radio_button_checked : Icons.radio_button_off, size: 14,
                    color: e.name == m.modelName ? Theme.of(context).colorScheme.primary : Colors.grey),
                title: Text(e.name, style: TextStyle(fontSize: 13, fontFamily: 'monospace')),
                onTap: () { _setSubModel(m, e.name); setState(() => _showModelMenu = false); },
              )),
          ]);
        },
      ),
    );
  }

  Widget _modelSel(ModelConfig? cur, ModelConfigProvider mp) {
    if (cur == null) return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
      child: Icon(Icons.smart_toy, size: 18, color: Colors.grey[400]),
    );
    if (_showModelMenu) {
      return InkWell(onTap: () => setState(() => _showModelMenu = false), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
        child: Icon(Icons.arrow_drop_up, size: 22, color: Theme.of(context).colorScheme.primary),
      ));
    }
    return InkWell(onTap: () => setState(() => _showModelMenu = true), child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.smart_toy, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 2),
        Text(cur.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 2),
        const Icon(Icons.arrow_drop_down, size: 18),
      ]),
    ));
  }

  Widget _dialogSetBtn() => InkWell(onTap: _showDialogSettings, borderRadius: BorderRadius.circular(8), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.tune, size: 14, color: Colors.grey[500]),
      const SizedBox(width: 3),
      Text('对话设置', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  ));

  Widget _thinkBtn() => InkWell(onTap: () => setState(() => _thinking = !_thinking), borderRadius: BorderRadius.circular(8), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _thinking ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.3)),
        color: _thinking ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.psychology, size: 16, color: _thinking ? Theme.of(context).colorScheme.primary : Colors.grey[400]),
      const SizedBox(width: 3),
      Text('思考', style: TextStyle(fontSize: 12, color: _thinking ? Theme.of(context).colorScheme.primary : Colors.grey[500])),
    ]),
  ));

  Widget _attachBtn() => InkWell(onTap: () => setState(() => _showAttach = !_showAttach), borderRadius: BorderRadius.circular(12), child: Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        color: _showAttach ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : null),
    child: Icon(Icons.add, size: 22, color: _showAttach ? Theme.of(context).colorScheme.primary : Colors.grey[500]),
  ));

  Widget _attachMenu() => Padding(padding: const EdgeInsets.only(top: 8), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
    _attachOpt(Icons.photo_library, '图片', () { setState(() => _showAttach = false); _pickImg(); }),
    const SizedBox(width: 12),
    _attachOpt(Icons.attach_file, '文件', () { setState(() => _showAttach = false); _pickImg(); }),
  ]));

  Widget _attachOpt(IconData i, String l, VoidCallback t) => InkWell(onTap: t, borderRadius: BorderRadius.circular(8), child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Theme.of(context).colorScheme.surfaceContainerHighest),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 16, color: Colors.grey[600]), const SizedBox(width: 4),
      Text(l, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]),
  ));

  Widget _voiceOrSendBtn(bool hasSpeech) {
    final hasText = _msgCtrl.text.isNotEmpty;
    if (_recording) {
      return GestureDetector(
        onLongPressEnd: (_) => _stopVoice(),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop, size: 16, color: Colors.white), SizedBox(width: 4),
              Text('松开发送', style: TextStyle(fontSize: 12, color: Colors.white)),
            ])),
      );
    }
    if (hasText) {
      return IconButton(onPressed: _send, icon: Icon(Icons.send_rounded, color: Theme.of(context).colorScheme.primary, size: 22),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36));
    }
    return IconButton(
      onPressed: hasSpeech ? _voice : _send,
      icon: Icon(hasSpeech ? Icons.mic_none : Icons.send_rounded, size: 22, color: hasSpeech ? Colors.grey[500] : Colors.grey[400]),
      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _recOverlay() => GestureDetector(
    onLongPressEnd: (_) => _stopVoice(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(Icons.mic, size: 20, color: Colors.red[400]), const SizedBox(width: 8),
        Text(_speech.isListening ? '正在聆听...' : '长按录制语音', style: TextStyle(color: Colors.red[400], fontSize: 14)),
      ]),
    ),
  );
}

class _DialogSettingsContent extends StatefulWidget {
  @override
  State<_DialogSettingsContent> createState() => _DialogSettingsContentState();
}

class _DialogSettingsContentState extends State<_DialogSettingsContent> {
  @override
  Widget build(BuildContext context) {
    final set = context.watch<SettingsProvider>().settings;
    final mp = context.watch<ModelConfigProvider>();
    final speechModel = set.speechModelId != null ? mp.models.cast<ModelConfig?>().firstWhere((m) => m!.id == set.speechModelId, orElse: () => null) : null;
    final imageModel = set.imageModelId != null ? mp.models.cast<ModelConfig?>().firstWhere((m) => m!.id == set.imageModelId, orElse: () => null) : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.55, minChildSize: 0.35, maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.tune, size: 22), const SizedBox(width: 8),
              Text('对话设置', style: Theme.of(context).textTheme.titleLarge),
            ]),
            const SizedBox(height: 20),
            // 语音转文字模型
            Text('语音转文字模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 8),
            _modelPicker(
              current: speechModel,
              mp: mp,
              hint: '未设置（语音按钮为发送按钮）',
              onSelect: (id) { context.read<SettingsProvider>().setSpeechModelId(id); setState(() {}); },
              onClear: () { context.read<SettingsProvider>().setSpeechModelId(null); setState(() {}); },
            ),
            const SizedBox(height: 20),
            // 图片文件转述模型
            Text('图片文件转述模型', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 8),
            _modelPicker(
              current: imageModel,
              mp: mp,
              hint: '未设置（图片直接发送）',
              onSelect: (id) { context.read<SettingsProvider>().setImageModelId(id); setState(() {}); },
              onClear: () { context.read<SettingsProvider>().setImageModelId(null); setState(() {}); },
            ),
            const SizedBox(height: 16),
            // 图片转述提示词
            Text('图片转述提示词', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[700])),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showPromptDialog(context, set.imagePrompt),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
                child: Text(set.imagePrompt, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('完成'),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _modelPicker({required dynamic current, required ModelConfigProvider mp, required String hint,
    required void Function(String) onSelect, required VoidCallback onClear}) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.withValues(alpha: 0.3)), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          dense: true,
          title: Text(current != null ? '${current.name} (${current.modelName})' : hint,
              style: TextStyle(fontSize: 13, color: current != null ? null : Colors.grey[500])),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (current != null)
              IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onClear, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'custom') {
                  Navigator.pop(context);
                  // Navigate to API settings page
                  Future.delayed(const Duration(milliseconds: 200), () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const _ApiSettingsBridge()));
                  });
                } else {
                  onSelect(v);
                }
              },
              itemBuilder: (ctx) => [
                ...mp.models.map((m) => PopupMenuItem(value: m.id, child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
                  children: [Text(m.name), Text(m.modelName, style: TextStyle(fontSize: 11, color: Colors.grey[500]))],
                ))),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'custom', child: Text('自定义模型提供商')),
              ],
              icon: const Icon(Icons.more_vert, size: 18),
            ),
          ]),
        ),
      ]),
    );
  }

  void _showPromptDialog(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('自定义提示词'),
      content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Describe this file in Chinese')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        TextButton(onPressed: () { context.read<SettingsProvider>().setImagePrompt(ctrl.text.trim()); Navigator.pop(ctx); }, child: const Text('保存')),
      ],
    ));
  }
}

class _ApiSettingsBridge extends StatelessWidget {
  const _ApiSettingsBridge();
  @override
  Widget build(BuildContext context) {
    // Import at usage site to avoid circular dependency
    return Scaffold(
      appBar: AppBar(title: const Text('添加模型提供商')),
      body: Center(child: Text('请在 设置 → API 中添加模型', style: TextStyle(color: Colors.grey[500]))),
    );
  }
}

class _HistoryDrawer extends StatefulWidget {
  final void Function(String) onSelect;
  final String? currentConvId;
  const _HistoryDrawer({required this.onSelect, this.currentConvId});

  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ConversationProvider>();
    final results = p.searchConversations(_q);
    return Column(children: [
      Container(
        width: double.infinity,
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 16, left: 16, right: 16, bottom: 12),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.history), const SizedBox(width: 8), Text('历史对话', style: Theme.of(context).textTheme.titleLarge)]),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '搜索历史...', prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _q.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () { _searchCtrl.clear(); setState(() => _q = ''); }) : null,
              filled: true, fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ]),
      ),
      Expanded(child: results.isEmpty
          ? Center(child: Text(_q.isEmpty ? '暂无历史对话' : '无匹配结果', style: TextStyle(color: Colors.grey[500])))
          : ListView.builder(
              itemCount: results.length,
              itemBuilder: (_, i) {
                final c = results[i]['conversation'];
                final active = c.id == widget.currentConvId;
                return ListTile(
                  selected: active,
                  selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                  leading: const Icon(Icons.chat, size: 20),
                  title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal)),
                  subtitle: Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () {
                      context.read<ConversationProvider>().deleteConversation(c.id);
                      if (c.id == widget.currentConvId) widget.onSelect('');
                    },
                  ),
                  onLongPress: () {
                    context.read<ConversationProvider>().deleteConversation(c.id);
                    if (c.id == widget.currentConvId) widget.onSelect('');
                  },
                  onTap: () => widget.onSelect(c.id),
                );
              },
            )),
    ]);
  }
}
