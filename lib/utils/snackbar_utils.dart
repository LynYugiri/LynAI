import 'package:flutter/material.dart';

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

void showShortSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(shortSnackBar(message));
}

SnackBar errorSnackBar(
  BuildContext context,
  String message, {
  String? details,
}) {
  final detailText = (details == null || details.trim().isEmpty)
      ? message
      : details.trim();
  final snippet = detailText.length > 120
      ? '${detailText.substring(0, 120)}…'
      : detailText;
  return SnackBar(
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (snippet != message)
          Text(
            snippet,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
      ],
    ),
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

void showErrorSnackBar(
  BuildContext context,
  String message, {
  String? details,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(errorSnackBar(context, message, details: details));
}

class ErrorDetailsPage extends StatelessWidget {
  const ErrorDetailsPage({
    super.key,
    required this.message,
    required this.details,
  });

  final String message;
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
