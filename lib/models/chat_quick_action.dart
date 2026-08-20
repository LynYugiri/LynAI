/// 底部对话按钮长按快捷盘的动作定义。
class ChatQuickAction {
  static const typeFeaturePage = 'feature_page';
  static const typeNewConversation = 'new_conversation';
  static const typeSettings = 'settings';

  final String type;
  final String? featureId;

  const ChatQuickAction({required this.type, this.featureId});

  static const featurePages = <String, String>{
    'dashboard': '功能总览',
    'history': '对话历史',
    'schedule': '日程表',
    'notes': '笔记',
    'todos': '待办清单',
    'roleplay': '情景演绎',
    'knowledge': '知识库',
    'cards': '记忆卡',
    'jottings': '随记',
  };

  static const featurePageIds = [
    'dashboard',
    'history',
    'schedule',
    'notes',
    'todos',
    'roleplay',
    'knowledge',
    'cards',
    'jottings',
  ];

  factory ChatQuickAction.featurePage(String featureId) {
    return ChatQuickAction(
      type: typeFeaturePage,
      featureId: featurePageIds.contains(featureId) ? featureId : 'dashboard',
    );
  }

  factory ChatQuickAction.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? typeFeaturePage;
    final featureId = json['featureId'] as String?;
    if (type == typeFeaturePage &&
        (featureId == null || !featurePageIds.contains(featureId))) {
      return ChatQuickAction.featurePage('dashboard');
    }
    return ChatQuickAction(type: type, featureId: featureId);
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    if (featureId != null) 'featureId': featureId,
  };

  String get displayTitle {
    if (type == typeNewConversation) return '新建对话';
    if (type == typeSettings) return '设置';
    return featurePages[featureId] ?? '功能总览';
  }
}

/// 三个方向的快捷动作配置。
class ChatQuickActions {
  final ChatQuickAction left;
  final ChatQuickAction up;
  final ChatQuickAction right;

  const ChatQuickActions({
    required this.left,
    required this.up,
    required this.right,
  });

  factory ChatQuickActions.defaults() => const ChatQuickActions(
    left: ChatQuickAction(
      featureId: 'schedule',
      type: ChatQuickAction.typeFeaturePage,
    ),
    up: ChatQuickAction(
      featureId: 'notes',
      type: ChatQuickAction.typeFeaturePage,
    ),
    right: ChatQuickAction(
      featureId: 'todos',
      type: ChatQuickAction.typeFeaturePage,
    ),
  );

  factory ChatQuickActions.fromJson(Object? raw) {
    if (raw is! Map) return ChatQuickActions.defaults();
    final json = Map<String, dynamic>.from(raw);
    return ChatQuickActions(
      left: json['left'] is Map
          ? ChatQuickAction.fromJson(Map<String, dynamic>.from(json['left']))
          : ChatQuickActions.defaults().left,
      up: json['up'] is Map
          ? ChatQuickAction.fromJson(Map<String, dynamic>.from(json['up']))
          : ChatQuickActions.defaults().up,
      right: json['right'] is Map
          ? ChatQuickAction.fromJson(Map<String, dynamic>.from(json['right']))
          : ChatQuickActions.defaults().right,
    );
  }

  Map<String, dynamic> toJson() => {
    'left': left.toJson(),
    'up': up.toJson(),
    'right': right.toJson(),
  };

  ChatQuickAction forDirection(String direction) {
    switch (direction) {
      case 'left':
        return left;
      case 'up':
        return up;
      case 'right':
        return right;
      default:
        return left;
    }
  }

  ChatQuickActions copyWith({
    ChatQuickAction? left,
    ChatQuickAction? up,
    ChatQuickAction? right,
  }) {
    return ChatQuickActions(
      left: left ?? this.left,
      up: up ?? this.up,
      right: right ?? this.right,
    );
  }
}
