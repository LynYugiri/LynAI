import 'package:flutter/material.dart';

/// 创建短时显示的 SnackBar，2 秒后自动消失，带关闭按钮。
///
/// 点击 SnackBar 内容区域可立即关闭。
SnackBar shortSnackBar(String message) {
  return SnackBar(
    content: Builder(
      builder: (context) {
        final messenger = ScaffoldMessenger.of(context);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        );
      },
    ),
    duration: const Duration(seconds: 2),
    showCloseIcon: true,
  );
}

/// 在当前 Scaffold 中显示短时消息提示。
///
/// 会自动关闭当前已显示的 SnackBar，避免排队积压。
void showShortSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(shortSnackBar(message));
}

/// 创建带"查看详细"操作按钮的错误 SnackBar。
///
/// 点击操作按钮会导航到 [ErrorDetailsPage]，展示错误的摘要和详细堆栈信息。
SnackBar errorSnackBar(
  BuildContext context,
  String message, {
  String? details,
}) {
  final detailText = (details == null || details.trim().isEmpty)
      ? message
      : details.trim();
  return SnackBar(
    content: Text(message),
    showCloseIcon: true,
    action: SnackBarAction(
      label: '查看详细',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ErrorDetailsPage(message: message, details: detailText),
        ),
      ),
    ),
  );
}

/// 在当前 Scaffold 中显示带详细信息的错误提示。
void showErrorSnackBar(
  BuildContext context,
  String message, {
  String? details,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(errorSnackBar(context, message, details: details));
}

/// 错误详情全屏页面。
///
/// 展示错误摘要和可复制的详细错误信息，使用等宽字体呈现细节。
class ErrorDetailsPage extends StatelessWidget {
  const ErrorDetailsPage({
    super.key,
    required this.message,
    required this.details,
  });

  /// 错误摘要文本。
  final String message;

  /// 详细错误信息文本。
  final String details;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('错误详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('摘要', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SelectableText(message),
          const SizedBox(height: 20),
          Text('详细信息', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                details,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
