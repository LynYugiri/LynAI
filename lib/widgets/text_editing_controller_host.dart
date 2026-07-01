import 'package:flutter/material.dart';

typedef TextEditingControllerHostBuilder =
    Widget Function(
      BuildContext context,
      List<TextEditingController> controllers,
    );

class TextEditingControllerHost extends StatefulWidget {
  const TextEditingControllerHost({
    super.key,
    required this.initialTexts,
    required this.builder,
  });

  final List<String> initialTexts;
  final TextEditingControllerHostBuilder builder;

  @override
  State<TextEditingControllerHost> createState() =>
      _TextEditingControllerHostState();
}

class _TextEditingControllerHostState extends State<TextEditingControllerHost> {
  late final List<TextEditingController> _controllers = widget.initialTexts
      .map((text) => TextEditingController(text: text))
      .toList(growable: false);

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controllers);
  }
}
