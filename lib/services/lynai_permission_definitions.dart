enum LynAIPermissionRisk { normal, elevated }

final class AgentPermissionSnapshot {
  static const currentVersion = 1;

  AgentPermissionSnapshot({
    this.version = currentVersion,
    required Iterable<String> permissions,
  }) : permissions = List.unmodifiable(permissions);

  factory AgentPermissionSnapshot.fromJson(Map<String, dynamic> json) {
    return AgentPermissionSnapshot(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      permissions: (json['permissions'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty),
    );
  }

  final int version;
  final List<String> permissions;

  bool contains(String permission) => permissions.contains(permission);

  Map<String, dynamic> toJson() => {
    'version': version,
    'permissions': permissions,
  };
}

class LynAIPermissions {
  static const luaExecute = 'lua.execute';
  static const pluginCallFunction = 'plugins.callFunction';
  static const notesRead = 'notes:read';
  static const notesWrite = 'notes:write';
  static const notesPropose = 'notes:propose';
  static const todosRead = 'todos:read';
  static const todosWrite = 'todos:write';
  static const schedulesRead = 'schedules:read';
  static const schedulesWrite = 'schedules:write';
  static const filesWrite = 'files:write';
  static const pluginSkillFilesWrite = 'plugins.skills.files:write';
  static const pluginsFilesRead = 'plugins.files:read';
  static const pluginsFilesWrite = 'plugins.files:write';
  static const storageRead = 'storage:read';
  static const storageWrite = 'storage:write';
  static const memoryCardsRead = 'memoryCards:read';
  static const memoryCardsWrite = 'memoryCards:write';
  static const recycleBinRead = 'recycleBin:read';
  static const recycleBinWrite = 'recycleBin:write';
  static const recycleBinRestore = 'recycleBin:restore';
  static const networkAccess = 'network:access';
  static const networkPublic = 'network:public';
  static const modelChat = 'model:chat';
  static const modelOcr = 'model:ocr';
  static const modelRecognizeFile = 'model:recognizeFile';
  static const modelGenerateImage = 'model:generateImage';
  static const webviewBridge = 'webview:bridge';
  static const deviceScreenRead = 'device:screen:read';
  static const deviceControl = 'device:control';
  static const deviceOverlay = 'device:overlay';

  static const defaultAgent = [
    luaExecute,
    pluginCallFunction,
    notesRead,
    notesWrite,
    notesPropose,
    todosRead,
    todosWrite,
    schedulesRead,
    schedulesWrite,
    pluginSkillFilesWrite,
    storageRead,
    memoryCardsRead,
    memoryCardsWrite,
    networkAccess,
    modelChat,
    modelOcr,
    modelRecognizeFile,
    modelGenerateImage,
    deviceScreenRead,
    deviceControl,
    deviceOverlay,
  ];

  static const agentAssignable = [
    ...defaultAgent,
    pluginsFilesRead,
    pluginsFilesWrite,
  ];
}

class LynAIPermissionDefinition {
  final String id;
  final String title;
  final String description;
  final LynAIPermissionRisk risk;

  /// 插件免授权：声明后自动授予，无需在授权清单中逐项确认。
  final bool pluginAutoGrant;

  const LynAIPermissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.risk = LynAIPermissionRisk.normal,
    this.pluginAutoGrant = false,
  });
}

const lynaiPermissionDefinitions = <LynAIPermissionDefinition>[
  LynAIPermissionDefinition(
    id: LynAIPermissions.luaExecute,
    title: '执行 Lua 脚本',
    description: '允许 Agent 运行受限 Lua，用于编排读取、写入和插件函数。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.pluginCallFunction,
    title: '调用插件函数',
    description: '允许 Agent 或 Agent Lua 调用已安装插件暴露的函数。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.notesRead,
    title: '读取笔记',
    description: '允许读取笔记、分页和文件夹。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.notesWrite,
    title: '修改笔记',
    description: '允许创建和修改笔记内容、分页和文件夹；删除暂不开放给 Agent。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.notesPropose,
    title: '提议笔记修改',
    description: '允许生成需要用户确认的逐行笔记修改建议。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.todosRead,
    title: '读取待办',
    description: '允许读取待办清单和待办项。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.todosWrite,
    title: '修改待办',
    description: '允许创建和修改待办；删除暂不开放给 Agent。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.schedulesRead,
    title: '读取日程',
    description: '允许读取日程和任务。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.schedulesWrite,
    title: '修改日程',
    description: '允许创建和修改日程；删除暂不开放给 Agent。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.pluginSkillFilesWrite,
    title: '修改插件 Skill 文件',
    description: '允许 Agent 写入插件清单中声明为可编辑的 Skill Markdown 文件。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.pluginsFilesRead,
    title: '读取插件文件',
    description: '允许 Agent 查看插件 manifest 和插件目录中的可读文件。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.pluginsFilesWrite,
    title: '修改插件文件',
    description: '允许 Agent 修改草稿/测试中插件或已声明 overlay 的文件内容。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.storageRead,
    title: '读取对话附件',
    description: '允许 Agent 通过稳定资源 ID 读取当前设备上的对话附件和资源元数据。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.memoryCardsRead,
    title: '读取记忆卡片',
    description: '允许读取牌组、记忆卡片和复习记录。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.memoryCardsWrite,
    title: '修改记忆卡片',
    description: '允许创建和修改记忆卡片并执行复习评分；删除暂不开放给 Agent。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.networkAccess,
    title: '访问网络',
    description: '允许调用 http.fetch 访问外部资源。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.networkPublic,
    title: '访问公开网络',
    description: '允许插件通过 GET/HEAD 访问公开只读 HTTPS 资源，不携带自定义请求头或正文。',
    pluginAutoGrant: true,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.recycleBinRead,
    title: '读取回收站',
    description: '允许插件读取自己放入回收站的项目。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.memoryCardsRead,
    title: '读取记忆卡片',
    description: '允许读取牌组、记忆卡片和复习记录。',
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.memoryCardsWrite,
    title: '修改记忆卡片',
    description: '允许创建和修改记忆卡片并执行复习评分；删除暂不开放给 Agent。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.recycleBinWrite,
    title: '写入回收站',
    description: '允许插件把自己的数据或可编辑文件移入回收站。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.recycleBinRestore,
    title: '恢复回收站项目',
    description: '允许插件恢复或永久删除自己放入回收站的项目。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.modelChat,
    title: '调用模型',
    description: '允许通过 model.chat 调用已配置模型。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.modelOcr,
    title: '调用 OCR 模型',
    description: '允许通过 model.ocr 调用已配置 OCR 模型识别图片文字。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.modelRecognizeFile,
    title: '调用文件识别模型',
    description: '允许通过 model.recognizeFile 调用视觉模型识别图片或文件。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.modelGenerateImage,
    title: '调用图片生成模型',
    description: '允许通过 model.generateImage 调用已配置图片生成模型并保存结果。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.deviceScreenRead,
    title: '读取屏幕内容',
    description: '允许 Agent 通过无障碍读取当前屏幕结构化内容。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.deviceControl,
    title: '操控屏幕',
    description: '允许 Agent 通过 Lua 执行点击、滑动、输入、返回和节点操作。',
    risk: LynAIPermissionRisk.elevated,
  ),
  LynAIPermissionDefinition(
    id: LynAIPermissions.deviceOverlay,
    title: '显示任务悬浮层',
    description: '允许 Agent 操控屏幕且 LynAI 退到后台时显示计划和控制按钮。',
    risk: LynAIPermissionRisk.elevated,
  ),
];

final lynaiPermissionDefinitionById = {
  for (final item in lynaiPermissionDefinitions) item.id: item,
};

final agentAssignablePermissionDefinitions = LynAIPermissions.agentAssignable
    .map((permission) => lynaiPermissionDefinitionById[permission])
    .whereType<LynAIPermissionDefinition>()
    .toList(growable: false);

/// 返回声明权限中应自动授予插件的免授权权限集合。
Set<String> autoGrantedPluginPermissions(Iterable<String> declared) =>
    declared.where(isAutoGrantedPluginPermission).toSet();

/// 判断单个权限是否为插件免授权权限。
bool isAutoGrantedPluginPermission(String permission) =>
    lynaiPermissionDefinitionById[permission]?.pluginAutoGrant == true;
