import 'lynai_permission_definitions.dart';

/// 能力提供者类型：宿主内置或插件。
enum CapabilityProvider { host, plugin }

/// 单个互联能力方法的声明。
///
/// 只描述能力的权限要求与读/写性质，不绑定执行逻辑。执行仍由
/// [LynAIFunctionService] 或插件运行时承担。
class CapabilityMethod {
  final String method;
  final String? permission;
  final bool isRead;
  final CapabilityProvider provider;
  final String? pluginId;

  const CapabilityMethod({
    required this.method,
    required this.permission,
    this.isRead = false,
    this.provider = CapabilityProvider.host,
    this.pluginId,
  });
}

/// 互联能力注册表：宿主内置能力与插件对外函数的统一目录。
///
/// 宿主能力由 [registerHostCapabilities] 一次性注册；插件能力随插件启用/禁用
/// 动态注册与移除。授权判定统一通过 [lookup] 查询权限标识。
class LynAICapabilityRegistry {
  final Map<String, CapabilityMethod> _methods = {};

  LynAICapabilityRegistry({bool registerHost = false}) {
    if (registerHost) registerHostCapabilities(this);
  }

  /// 注册宿主内置能力。
  void registerHost(
    String method, {
    String? permission,
    bool isRead = false,
  }) {
    _methods[method] = CapabilityMethod(
      method: method,
      permission: permission,
      isRead: isRead,
    );
  }

  /// 注册插件对外函数，method 为插件内函数名。
  void registerPlugin(
    String pluginId,
    String method, {
    String? permission,
    bool isRead = false,
  }) {
    _methods['plugin:$pluginId:$method'] = CapabilityMethod(
      method: method,
      permission: permission,
      isRead: isRead,
      provider: CapabilityProvider.plugin,
      pluginId: pluginId,
    );
  }

  /// 移除插件持有的全部能力注册。
  void removePlugin(String pluginId) {
    final prefix = 'plugin:$pluginId:';
    _methods.removeWhere((key, _) => key.startsWith(prefix));
  }

  CapabilityMethod? lookup(String method) => _methods[method];

  /// 返回按权限过滤后的能力列表；免授权能力始终可见。
  List<CapabilityMethod> list({required Iterable<String> granted}) {
    final set = granted.toSet();
    return _methods.values
        .where((m) => m.permission == null || set.contains(m.permission))
        .toList(growable: false);
  }
}

/// 注册宿主内置能力。只声明权限与读/写性质，不绑定执行逻辑。
void registerHostCapabilities(LynAICapabilityRegistry registry) {
  void host(String method, {String? permission, bool read = false}) =>
      registry.registerHost(method, permission: permission, isRead: read);

  // 回收站
  host('recycleBin.list', permission: LynAIPermissions.recycleBinRead, read: true);
  host('recycleBin.putData', permission: LynAIPermissions.recycleBinWrite);
  host('recycleBin.putFile', permission: LynAIPermissions.recycleBinWrite);
  host('recycleBin.restore', permission: LynAIPermissions.recycleBinRestore);
  host('recycleBin.deleteForever', permission: LynAIPermissions.recycleBinRestore);

  // 插件调用（跨插件调用入口，调用方需 plugins.callFunction）
  host('plugin.call', permission: LynAIPermissions.pluginCallFunction);

  // 插件文件与私有存储（文件读取与私有存储免授权，写需要 files:write）
  host('plugin.file.list', read: true);
  host('plugin.file.read', read: true);
  host('plugin.file.write', permission: LynAIPermissions.filesWrite);
  host('plugin.file.create', permission: LynAIPermissions.filesWrite);
  host('plugin.file.delete', permission: LynAIPermissions.filesWrite);
  host('plugin.file.rename', permission: LynAIPermissions.filesWrite);
  host('plugin.restore', permission: LynAIPermissions.filesWrite);
  host('plugin.storage.get', read: true);
  host('plugin.storage.set');
  host('plugin.storage.remove');

  // 网络
  host('http.fetch', permission: LynAIPermissions.networkAccess);
  host('http.fetchPublic', permission: LynAIPermissions.networkPublic);

  // 笔记
  host('notes.list', permission: LynAIPermissions.notesRead, read: true);
  host('notes.read', permission: LynAIPermissions.notesRead, read: true);
  host('notes.proposeEdit', permission: LynAIPermissions.notesPropose);
  host('notes.save', permission: LynAIPermissions.notesWrite);
  host('notes.edit', permission: LynAIPermissions.notesWrite);
  host('notes.delete', permission: LynAIPermissions.notesWrite);
  host('notes.pages.list', permission: LynAIPermissions.notesRead, read: true);
  host('notes.pages.save', permission: LynAIPermissions.notesWrite);
  host('notes.folders.list', permission: LynAIPermissions.notesRead, read: true);
  host('notes.folders.save', permission: LynAIPermissions.notesWrite);

  // 待办 / 任务 / 任务清单
  host('todos.list', permission: LynAIPermissions.todosRead, read: true);
  host('todos.read', permission: LynAIPermissions.todosRead, read: true);
  host('todos.saveList', permission: LynAIPermissions.todosWrite);
  host('todos.saveItem', permission: LynAIPermissions.todosWrite);
  host('todos.deleteList', permission: LynAIPermissions.todosWrite);
  host('tasks.list', permission: LynAIPermissions.todosRead, read: true);
  host('tasks.read', permission: LynAIPermissions.todosRead, read: true);
  host('tasks.create', permission: LynAIPermissions.todosWrite);
  host('tasks.update', permission: LynAIPermissions.todosWrite);
  host('tasks.delete', permission: LynAIPermissions.todosWrite);
  host('taskLists.list', permission: LynAIPermissions.todosRead, read: true);
  host('taskLists.read', permission: LynAIPermissions.todosRead, read: true);
  host('taskLists.create', permission: LynAIPermissions.todosWrite);
  host('taskLists.update', permission: LynAIPermissions.todosWrite);
  host('taskLists.delete', permission: LynAIPermissions.todosWrite);

  // 日历 / 纪念日 / 日程
  host('calendar.list', permission: LynAIPermissions.schedulesRead, read: true);
  host('calendar.create', permission: LynAIPermissions.schedulesWrite);
  host('calendar.update', permission: LynAIPermissions.schedulesWrite);
  host('calendar.delete', permission: LynAIPermissions.schedulesWrite);
  host('anniversaries.list', permission: LynAIPermissions.schedulesRead, read: true);
  host('anniversaries.create', permission: LynAIPermissions.schedulesWrite);
  host('anniversaries.update', permission: LynAIPermissions.schedulesWrite);
  host('anniversaries.delete', permission: LynAIPermissions.schedulesWrite);
  host('schedules.list', permission: LynAIPermissions.schedulesRead, read: true);
  host('schedules.create', permission: LynAIPermissions.schedulesWrite);
  host('schedules.update', permission: LynAIPermissions.schedulesWrite);
  host('schedules.delete', permission: LynAIPermissions.schedulesWrite);

  // 模型
  host('model.chat', permission: LynAIPermissions.modelChat);
  host('model.ocr', permission: LynAIPermissions.modelOcr);
  host('model.recognizeFile', permission: LynAIPermissions.modelRecognizeFile);
  host('model.generateImage', permission: LynAIPermissions.modelGenerateImage);

  // 设备
  host('device.screen.snapshot', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.context', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.screenshot', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.query', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.waitText', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.readVisibleText', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.extractMessages', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.node.find', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.node.findAll', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.waitForNode', permission: LynAIPermissions.deviceScreenRead, read: true);
  host('device.screen.clickText', permission: LynAIPermissions.deviceControl);
  host('device.screen.waitAndClick', permission: LynAIPermissions.deviceControl);
  host('device.screen.inputText', permission: LynAIPermissions.deviceControl);
  host('device.screen.scrollUntil', permission: LynAIPermissions.deviceControl);
  host('device.service.status', permission: LynAIPermissions.deviceOverlay);
  host('device.service.openSettings', permission: LynAIPermissions.deviceOverlay);
  host('device.app.open', permission: LynAIPermissions.deviceControl);
  host('device.app.list', permission: LynAIPermissions.deviceControl, read: true);
}
