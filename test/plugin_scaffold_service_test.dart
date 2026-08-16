import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/plugin.dart';
import 'package:lynai/services/plugin_scaffold_service.dart';

void main() {
  test('all scaffold kinds produce a valid PluginManifest', () {
    for (final kind in PluginScaffoldKind.values) {
      final files = PluginScaffoldService.buildScaffold(
        id: 'scaffold-test',
        name: '脚手架测试',
        version: '0.1.0',
        author: 'LynAI',
        description: '测试模板',
        kind: kind,
      );

      final manifestJson = files['plugin.json'];
      expect(manifestJson, isNotNull, reason: '$kind 缺少 plugin.json');
      final manifest = PluginManifest.fromJson(
        Map<String, dynamic>.from(jsonDecode(manifestJson!) as Map),
      );
      expect(manifest.validate(), isNull, reason: '$kind manifest 不合法');
      expect(manifest.id, 'scaffold-test');
      expect(manifest.entry, 'main.lua');
      expect(files, contains('main.lua'), reason: '$kind 缺少 main.lua');
    }
  });

  test('lua tool scaffold exposes one tool with a handler', () {
    final files = PluginScaffoldService.buildScaffold(
      id: 'tool-demo',
      name: '工具示例',
      version: '1.0.0',
      author: 'LynAI',
      description: 'desc',
      kind: PluginScaffoldKind.luaTool,
    );
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(files['plugin.json']!) as Map),
    );
    expect(manifest.tools, hasLength(1));
    expect(manifest.tools.single.name, 'hello');
    expect(files['main.lua'], contains('function hello'));
  });

  test('skill scaffold generates editable skill and default template', () {
    final files = PluginScaffoldService.buildScaffold(
      id: 'skill-demo',
      name: '技能示例',
      version: '1.0.0',
      author: 'LynAI',
      description: 'desc',
      kind: PluginScaffoldKind.skill,
    );
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(files['plugin.json']!) as Map),
    );
    expect(manifest.skills, hasLength(1));
    expect(manifest.editableFiles, hasLength(1));
    expect(files, contains('skills/example_workflow.md'));
    expect(files, contains('defaults/skills/example_workflow.md'));
  });

  test('feature page scaffold declares a webview page', () {
    final files = PluginScaffoldService.buildScaffold(
      id: 'page-demo',
      name: '页面示例',
      version: '1.0.0',
      author: 'LynAI',
      description: 'desc',
      kind: PluginScaffoldKind.featurePage,
    );
    final manifest = PluginManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(files['plugin.json']!) as Map),
    );
    expect(manifest.featurePages, hasLength(1));
    expect(manifest.featurePages.single.entry, 'index.html');
    expect(manifest.permissions, contains('webview:bridge'));
    expect(files, contains('index.html'));
    expect(files, contains('index.css'));
    expect(files, contains('index.js'));
  });
}
