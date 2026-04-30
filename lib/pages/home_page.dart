import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import 'history_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final int initialIndex;
  final String? conversationId;

  const HomePage({super.key, this.initialIndex = 1, this.conversationId});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _currentIndex;
  String? _targetConversationId;
  String? _cachedImagePath;
  bool _cachedImageExists = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetConversationId = widget.conversationId;
  }

  bool _checkImageExists(String path) {
    if (path == _cachedImagePath) return _cachedImageExists;
    _cachedImagePath = path;
    _cachedImageExists = File(path).existsSync();
    return _cachedImageExists;
  }

  void _navigateToChat(String conversationId) {
    setState(() {
      _currentIndex = 1;
      _targetConversationId = conversationId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;
    final hasImage = settings.backgroundImagePath != null &&
        _checkImageExists(settings.backgroundImagePath!);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final scaffold = Scaffold(
      backgroundColor: hasImage ? Colors.transparent : null,
      extendBodyBehindAppBar: hasImage,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HistoryPage(onConversationTap: _navigateToChat),
          ChatPage(
            conversationId: _targetConversationId,
            onConversationLoaded: () {
              _targetConversationId = null;
            },
          ),
          const SettingsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            _targetConversationId = null;
          });
        },
        selectedItemColor: settings.themeColor,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.history), label: '历史'),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline), label: '对话'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );

    if (!hasImage) return scaffold;

    final transparentScaffold = Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.transparent,
      ),
      child: scaffold,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(settings.backgroundImagePath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
        if (settings.blurEnabled)
          Positioned.fill(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: settings.blurAmount,
                sigmaY: settings.blurAmount,
              ),
              child: Container(
                color: (isDark ? Colors.black : Colors.white)
                    .withValues(alpha: 0.3),
              ),
            ),
          ),
        Positioned.fill(
          child: Container(
            color: (isDark ? Colors.black : Colors.white)
                .withValues(alpha: settings.blurEnabled ? 0.2 : 0.55),
          ),
        ),
        transparentScaffold,
      ],
    );
  }
}
