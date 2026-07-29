import 'dart:async';

import 'package:flutter/material.dart';

typedef AiExplainSelectionCallback = FutureOr<void> Function(String text);

/// A selectable region that optionally appends an AI explanation action to the
/// platform text-selection menu.
class AiExplainSelectionArea extends StatefulWidget {
  final Widget child;
  final AiExplainSelectionCallback? onExplain;
  final String explainLabel;

  const AiExplainSelectionArea({
    super.key,
    required this.child,
    this.onExplain,
    this.explainLabel = 'AI 释义',
  });

  @override
  State<AiExplainSelectionArea> createState() => _AiExplainSelectionAreaState();
}

class _AiExplainSelectionAreaState extends State<AiExplainSelectionArea> {
  String _selectedText = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) {
        _selectedText = content?.plainText.trim() ?? '';
      },
      contextMenuBuilder: (context, state) {
        final onExplain = widget.onExplain;
        if (onExplain == null) {
          return AdaptiveTextSelectionToolbar.selectableRegion(
            selectableRegionState: state,
          );
        }
        return buildAiExplainSelectionContextMenu(
          state: state,
          selectedText: _selectedText,
          onExplain: onExplain,
          explainLabel: widget.explainLabel,
        );
      },
      child: widget.child,
    );
  }
}

/// Builds the platform-adaptive selection menu with an additional AI action.
Widget buildAiExplainSelectionContextMenu({
  required SelectableRegionState state,
  required String selectedText,
  required AiExplainSelectionCallback onExplain,
  String explainLabel = 'AI 释义',
}) {
  final text = selectedText.trim();
  final items = <ContextMenuButtonItem>[
    ...state.contextMenuButtonItems,
    if (text.isNotEmpty)
      ContextMenuButtonItem(
        label: explainLabel,
        onPressed: () {
          state.hideToolbar();
          unawaited(Future.sync(() => onExplain(text)));
        },
      ),
  ];
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: items,
  );
}
