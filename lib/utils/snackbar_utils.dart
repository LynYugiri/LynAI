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
