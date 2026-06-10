import '../models/conversation.dart';
import 'lynai_call_identity.dart';

class LynAICapabilities {
  static const luaExecute = 'lua.execute';
  static const pluginCallFunction = 'plugins.callFunction';
}

class LynAIPermissionService {
  const LynAIPermissionService();

  bool canUseCapability({
    required LynAICallIdentity identity,
    required String capability,
    required ConversationSettings settings,
  }) {
    return settings.agentGrantedPermissions.contains(capability);
  }
}
