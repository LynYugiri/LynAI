enum LynAIPermissionRisk { normal, elevated }

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
  static const storageRead = 'storage:read';
  static const storageWrite = 'storage:write';
  static const networkAccess = 'network:access';
  static const modelChat = 'model:chat';
  static const modelOcr = 'model:ocr';
  static const modelRecognizeFile = 'model:recognizeFile';
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
    networkAccess,
    modelChat,
    modelOcr,
    modelRecognizeFile,
    deviceScreenRead,
    deviceControl,
    deviceOverlay,
  ];

  static const agentAssignable = defaultAgent;
}

class LynAIPermissionDefinition {
  final String id;
  final String title;
  final String description;
  final LynAIPermissionRisk risk;

  const LynAIPermissionDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.risk = LynAIPermissionRisk.normal,
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
    id: LynAIPermissions.networkAccess,
    title: '访问网络',
    description: '允许调用 http.fetch 访问外部资源。',
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
