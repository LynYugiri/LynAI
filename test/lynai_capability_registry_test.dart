import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/lynai_capability_registry.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

void main() {
  test('host capabilities map permissions correctly', () {
    final registry = LynAICapabilityRegistry(registerHost: true);

    expect(
      registry.lookup('notes.read')!.permission,
      LynAIPermissions.notesRead,
    );
    expect(
      registry.lookup('notes.save')!.permission,
      LynAIPermissions.notesWrite,
    );
    expect(
      registry.lookup('http.fetch')!.permission,
      LynAIPermissions.networkAccess,
    );
    expect(
      registry.lookup('http.fetchPublic')!.permission,
      LynAIPermissions.networkPublic,
    );
    expect(registry.lookup('plugin.storage.get')!.permission, isNull);
    expect(
      registry.lookup('plugin.file.write')!.permission,
      LynAIPermissions.filesWrite,
    );
    expect(
      registry.lookup('model.chat')!.permission,
      LynAIPermissions.modelChat,
    );
    expect(
      registry.lookup('device.screen.query')!.permission,
      LynAIPermissions.deviceScreenRead,
    );
    expect(registry.lookup('unknown.method'), isNull);
  });

  test('list filters by granted permissions', () {
    final registry = LynAICapabilityRegistry(registerHost: true);
    final granted = registry.list(granted: const [LynAIPermissions.notesRead]);
    final methods = granted.map((m) => m.method).toSet();
    expect(methods, contains('notes.read'));
    expect(methods, contains('plugin.storage.get'));
    expect(methods, isNot(contains('notes.save')));
  });

  test('plugin capabilities register and remove by plugin id', () {
    final registry = LynAICapabilityRegistry();
    registry.registerPlugin(
      'p1',
      'query',
      permission: LynAIPermissions.networkAccess,
    );
    expect(registry.lookup('plugin:p1:query')!.pluginId, 'p1');
    registry.removePlugin('p1');
    expect(registry.lookup('plugin:p1:query'), isNull);
  });
}
