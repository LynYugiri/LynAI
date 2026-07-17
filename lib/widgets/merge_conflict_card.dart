import 'package:flutter/material.dart';

import '../models/merge_models.dart';

class MergeConflictCard extends StatelessWidget {
  final MergeConflictView conflict;
  final List<MergeConflictChoice> choices;

  const MergeConflictCard({
    super.key,
    required this.conflict,
    required this.choices,
  });

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflict.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('本地：${conflict.localSummary}'),
            Text('传入：${conflict.incomingSummary}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: choices
                  .map(
                    (choice) => ChoiceChip(
                      label: Text(choice.label),
                      selected: choice.selected,
                      onSelected: choice.onSelected == null
                          ? null
                          : (_) => choice.onSelected!(),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class MergeConflictChoice {
  final String label;
  final bool selected;
  final VoidCallback? onSelected;

  const MergeConflictChoice({
    required this.label,
    this.selected = false,
    this.onSelected,
  });
}
