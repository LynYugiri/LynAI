import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/workspace.dart';

void main() {
  test('Workspace JSON roundtrip preserves fields', () {
    final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);
    final workspace = Workspace(
      id: 'ws-1',
      name: ' 项目A ',
      featureIds: ['notes', 'knowledge', 'unsupported'],
      pluginPolicyMode: WorkspacePluginPolicyMode.custom,
      enabledPluginIds: ['p1', 'p1'],
      devPluginIds: ['p2'],
      files: [
        const WorkspaceFileRef(
          resourceId: 'r1',
          originalName: 'README.md',
          mimeType: 'text/plain',
          size: 10,
        ),
      ],
      mountedFolderPath: '/tmp/project-a',
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    final restored = Workspace.fromJson(workspace.toJson());
    expect(restored.id, 'ws-1');
    expect(restored.name, '项目A');
    expect(restored.featureIds, ['notes', 'knowledge']);
    expect(restored.pluginPolicyMode, WorkspacePluginPolicyMode.custom);
    expect(restored.enabledPluginIds, ['p1']);
    expect(restored.devPluginIds, ['p2']);
    expect(restored.files.single.resourceId, 'r1');
    expect(restored.mountedFolderPath, '/tmp/project-a');
    expect(restored.createdAt, createdAt);
  });

  test('WorkspaceFileRef rejects missing identity', () {
    expect(
      () => WorkspaceFileRef.fromJson({'resourceId': ''}),
      throwsFormatException,
    );
  });

  test('normalizeFeatureIds keeps supported ids in order and deduplicates', () {
    expect(Workspace.normalizeFeatureIds(['notes', 'notes', 'x', 'schedule']), [
      'notes',
      'schedule',
    ]);
  });
}
