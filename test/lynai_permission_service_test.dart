import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/lynai_permission_service.dart';

void main() {
  test('Agent permission checks prefer the immutable run snapshot', () {
    const service = LynAIPermissionService();
    const identity = LynAICallIdentity(type: LynAICallerType.agent);
    final globals = AppSettings.defaults().copyWith(
      agentGrantedPermissions: const [LynAIPermissions.notesWrite],
    );
    final snapshot = AgentPermissionSnapshot(
      permissions: const [LynAIPermissions.notesRead],
    );

    expect(
      service.canUsePermission(
        identity: identity,
        permission: LynAIPermissions.notesRead,
        agentPermissionSnapshot: snapshot,
        appSettings: globals,
      ),
      isTrue,
    );
    expect(
      service.canUsePermission(
        identity: identity,
        permission: LynAIPermissions.notesWrite,
        agentPermissionSnapshot: snapshot,
        appSettings: globals,
      ),
      isFalse,
    );
  });

  test('assistantTool evaluates against the conversation snapshot', () {
    const service = LynAIPermissionService();
    final globals = AppSettings.defaults().copyWith(
      agentGrantedPermissions: const [LynAIPermissions.notesWrite],
    );
    final snapshot = AgentPermissionSnapshot(
      permissions: const [LynAIPermissions.notesRead],
    );

    expect(
      service.canUsePermission(
        identity: const LynAICallIdentity(type: LynAICallerType.assistantTool),
        permission: LynAIPermissions.notesRead,
        agentPermissionSnapshot: snapshot,
        appSettings: globals,
      ),
      isTrue,
    );
    expect(
      service.canUsePermission(
        identity: const LynAICallIdentity(type: LynAICallerType.assistantTool),
        permission: LynAIPermissions.notesWrite,
        agentPermissionSnapshot: snapshot,
        appSettings: globals,
      ),
      isFalse,
    );
    expect(
      service.canUsePermission(
        identity: const LynAICallIdentity(type: LynAICallerType.assistantTool),
        permission: LynAIPermissions.notesWrite,
        appSettings: globals,
      ),
      isTrue,
      reason: '无快照时回退全局默认',
    );
  });

  test('system trust must be explicit and assistant identity fails closed', () {
    const service = LynAIPermissionService();

    expect(
      service.canUsePermission(
        identity: const LynAICallIdentity(type: LynAICallerType.system),
        permission: LynAIPermissions.filesWrite,
      ),
      isTrue,
    );
    expect(
      service.canUsePermission(
        identity: const LynAICallIdentity(type: LynAICallerType.assistant),
        permission: LynAIPermissions.filesWrite,
      ),
      isFalse,
    );
  });

  test('plugin skill writes use a dedicated Agent permission', () {
    expect(
      LynAIPermissions.agentAssignable,
      contains(LynAIPermissions.pluginSkillFilesWrite),
    );
    expect(
      LynAIPermissions.pluginSkillFilesWrite,
      isNot(LynAIPermissions.filesWrite),
    );
  });

  test('Agent permission UI definitions match assignable permissions', () {
    expect(
      agentAssignablePermissionDefinitions.map((item) => item.id),
      LynAIPermissions.agentAssignable,
    );
    expect(
      lynaiPermissionDefinitions.map((item) => item.id).toSet().length,
      lynaiPermissionDefinitions.length,
    );
    expect(
      agentAssignablePermissionDefinitions.map((item) => item.id),
      isNot(contains(LynAIPermissions.recycleBinRead)),
    );
    expect(
      agentAssignablePermissionDefinitions.map((item) => item.id),
      isNot(contains(LynAIPermissions.recycleBinWrite)),
    );
    expect(
      agentAssignablePermissionDefinitions.map((item) => item.id),
      isNot(contains(LynAIPermissions.recycleBinRestore)),
    );
    expect(
      lynaiPermissionDefinitionById,
      contains(LynAIPermissions.recycleBinRead),
    );
  });
}
