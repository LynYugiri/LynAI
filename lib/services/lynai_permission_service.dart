import '../models/app_settings.dart';
import '../models/plugin.dart';
import 'lynai_call_identity.dart';
import 'lynai_permission_definitions.dart';

class LynAICapabilities {
  static const luaExecute = LynAIPermissions.luaExecute;
  static const pluginCallFunction = LynAIPermissions.pluginCallFunction;
}

class LynAIPermissionService {
  const LynAIPermissionService();

  bool canUsePermission({
    required LynAICallIdentity identity,
    required String permission,
    AppSettings? appSettings,
    InstalledPlugin? plugin,
  }) {
    return switch (identity.type) {
      LynAICallerType.system => true,
      LynAICallerType.agent ||
      LynAICallerType.agentLua ||
      LynAICallerType.lua =>
        (appSettings ?? AppSettings.defaults()).agentGrantedPermissions
            .contains(permission),
      LynAICallerType.plugin || LynAICallerType.pluginWebview =>
        plugin?.grantedPermissions.contains(permission) == true,
      LynAICallerType.assistant => false,
    };
  }

  bool canUseCapability({
    required LynAICallIdentity identity,
    required String capability,
    AppSettings? appSettings,
    InstalledPlugin? plugin,
  }) {
    return canUsePermission(
      identity: identity,
      permission: capability,
      appSettings: appSettings,
      plugin: plugin,
    );
  }
}
