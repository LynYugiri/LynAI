import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workspace.dart';
import '../providers/workspace_provider.dart';
import '../widgets/code_file_editor.dart';

/// 工作区文件目标类型。
enum WorkspaceFileKind {
  /// 添加到工作区的 Resource 文件。
  added,

  /// 挂载本地文件夹中的真实文件。
  mounted,
}

/// 工作区文件编辑器页面。
///
/// 复用 [CodeFileEditorPage]；added 文件保存时替换工作区中的 Resource
/// 引用，mounted 文件保存时原子写回挂载目录。
class WorkspaceFileEditorPage extends StatelessWidget {
  const WorkspaceFileEditorPage({
    super.key,
    required this.workspace,
    required this.kind,
    required this.relativePath,
    required this.initialContent,
    this.fileRef,
  });

  final Workspace workspace;
  final WorkspaceFileKind kind;
  final String relativePath;
  final String initialContent;

  /// [kind] 为 [WorkspaceFileKind.added] 时的当前 Resource 引用。
  final WorkspaceFileRef? fileRef;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WorkspaceProvider>();
    return CodeFileEditorPage(
      path: relativePath,
      initialContent: initialContent,
      onSave: (content) async {
        switch (kind) {
          case WorkspaceFileKind.added:
            final ref = fileRef;
            if (ref == null) {
              throw Exception('工作区文件引用缺失，无法保存');
            }
            await provider.writeWorkspaceFile(workspace.id, ref, content);
          case WorkspaceFileKind.mounted:
            await provider.writeMountedFile(workspace, relativePath, content);
        }
      },
    );
  }
}
