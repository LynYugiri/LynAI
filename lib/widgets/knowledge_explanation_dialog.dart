import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/knowledge_category.dart';
import '../providers/knowledge_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/knowledge_explanation_service.dart';
import 'latex_renderer.dart';

/// Opens the shared knowledge explanation dialog used by annotated text and
/// ordinary text selections.
Future<void> showKnowledgeExplanationDialog({
  required BuildContext context,
  required ApiService api,
  required String text,
  String? categoryId,
  String sourceContext = '',
  String sourceTitle = '',
  String sourceUrl = '',
  bool saveAutomatically = true,
  KnowledgeProvider? knowledge,
  ModelConfigProvider? modelConfigs,
  SettingsProvider? settings,
}) async {
  final knowledgeProvider = knowledge ?? context.read<KnowledgeProvider>();
  final service = KnowledgeExplanationService(
    api: api,
    modelConfigs: modelConfigs ?? context.read<ModelConfigProvider>(),
    settings: settings ?? context.read<SettingsProvider>(),
    knowledge: knowledgeProvider,
  );
  final requestedCategory = categoryId == null
      ? null
      : knowledgeProvider.categoryById(categoryId);
  final initialCategoryId =
      (requestedCategory != null &&
          knowledgeProvider.isExplanationCategoryEnabled(requestedCategory))
      ? requestedCategory.id
      : knowledgeProvider.defaultExplanationCategory?.id;
  final saved = initialCategoryId == null
      ? null
      : service.findSaved(categoryId: initialCategoryId, text: text);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => KnowledgeExplanationDialog(
      service: service,
      knowledge: knowledgeProvider,
      text: text,
      initialCategoryId: initialCategoryId,
      sourceContext: sourceContext,
      sourceTitle: sourceTitle,
      sourceUrl: sourceUrl,
      saveAutomatically: saveAutomatically,
      initialRecord: saved,
    ),
  );
}

class KnowledgeExplanationDialog extends StatefulWidget {
  const KnowledgeExplanationDialog({
    super.key,
    required this.service,
    required this.knowledge,
    required this.text,
    required this.initialCategoryId,
    required this.sourceContext,
    required this.sourceTitle,
    required this.sourceUrl,
    required this.saveAutomatically,
    this.initialRecord,
  });

  final KnowledgeExplanationService service;
  final KnowledgeProvider knowledge;
  final String text;
  final String? initialCategoryId;
  final String sourceContext;
  final String sourceTitle;
  final String sourceUrl;
  final bool saveAutomatically;
  final KnowledgeExplanationRecord? initialRecord;

  @override
  State<KnowledgeExplanationDialog> createState() =>
      _KnowledgeExplanationDialogState();
}

class _KnowledgeExplanationDialogState
    extends State<KnowledgeExplanationDialog> {
  String? _categoryId;
  String? _content;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _saved = false;
  bool _active = true;
  int _requestGeneration = 0;

  List<KnowledgeCategory> get _categories =>
      widget.knowledge.explanationCategories;

  @override
  void initState() {
    super.initState();
    widget.knowledge.addListener(_handleKnowledgeChanged);
    _categoryId = widget.initialCategoryId;
    final initial = widget.initialRecord;
    if (initial != null) {
      _content = initial.explanation.content;
      _saved = true;
    } else {
      unawaited(_loadCategory(_categoryId));
    }
  }

  @override
  void dispose() {
    _active = false;
    _requestGeneration++;
    widget.knowledge.removeListener(_handleKnowledgeChanged);
    super.dispose();
  }

  void _handleKnowledgeChanged() {
    if (!_active) return;
    final current = _categoryId == null
        ? null
        : widget.knowledge.categoryById(_categoryId!);
    if (current != null &&
        widget.knowledge.isExplanationCategoryEnabled(current)) {
      setState(() {});
      return;
    }
    final next = widget.knowledge.defaultExplanationCategory?.id;
    _requestGeneration++;
    _categoryId = next;
    _content = null;
    _error = null;
    _loading = false;
    _saving = false;
    _saved = false;
    setState(() {});
    if (next != null) unawaited(_loadCategory(next));
  }

  Future<void> _loadCategory(String? categoryId) async {
    final generation = ++_requestGeneration;
    setState(() {
      _categoryId = categoryId;
      _content = null;
      _saved = false;
      _loading = true;
      _error = null;
    });
    if (categoryId == null) {
      setState(() {
        _loading = false;
        _error = '没有可用的知识类别';
      });
      return;
    }
    final saved = widget.service.findSaved(
      categoryId: categoryId,
      text: widget.text,
    );
    if (saved != null) {
      if (!_active || generation != _requestGeneration) return;
      setState(() {
        _content = saved.explanation.content;
        _loading = false;
        _saved = true;
      });
      return;
    }
    await _generate(categoryId: categoryId, generation: generation);
  }

  Future<void> _generate({String? categoryId, int? generation}) async {
    final selectedCategory = categoryId ?? _categoryId;
    final request = generation ?? ++_requestGeneration;
    if (selectedCategory == null) return;
    if (generation == null) {
      setState(() {
        _content = null;
        _saved = false;
        _loading = true;
        _error = null;
      });
    }
    try {
      final content = await widget.service.generate(
        text: widget.text,
        categoryId: selectedCategory,
        context: widget.sourceContext,
        sourceTitle: widget.sourceTitle,
        sourceUrl: widget.sourceUrl,
      );
      if (!_active ||
          request != _requestGeneration ||
          selectedCategory != _categoryId) {
        return;
      }
      setState(() {
        _content = content;
        _loading = false;
      });
      if (widget.saveAutomatically) {
        await _save(generation: request, categoryId: selectedCategory);
      }
    } catch (error) {
      if (!_active || request != _requestGeneration) return;
      setState(() {
        _loading = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _save({int? generation, String? categoryId}) async {
    final selectedCategory = categoryId ?? _categoryId;
    final content = _content;
    if (selectedCategory == null ||
        content == null ||
        _saving ||
        _saved ||
        !_active ||
        generation != null && generation != _requestGeneration) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.save(
        categoryId: selectedCategory,
        text: widget.text,
        explanation: content,
        context: widget.sourceContext,
        sourceTitle: widget.sourceTitle,
        sourceUrl: widget.sourceUrl,
      );
      if (!_active ||
          selectedCategory != _categoryId ||
          generation != null && generation != _requestGeneration) {
        return;
      }
      setState(() {
        _saving = false;
        _saved = true;
      });
    } catch (error) {
      if (!_active || generation != null && generation != _requestGeneration) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _message(error);
      });
    }
  }

  String _message(Object error) {
    final value = error.toString();
    return value
        .replaceFirst(
          RegExp(r'^(Exception|StateError|Invalid argument):\s*'),
          '',
        )
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final validCategoryIds = categories.map((item) => item.id).toSet();
    final selectedCategory = validCategoryIds.contains(_categoryId)
        ? _categoryId
        : null;
    return AlertDialog(
      title: const Text('AI 释义'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 620),
        child: SizedBox(
          width: 680,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.text.trim(),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!widget.saveAutomatically) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedCategory),
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: '知识类别',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _saving
                      ? null
                      : (value) => unawaited(_loadCategory(value)),
                ),
              ],
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(child: _buildBody(context)),
              ),
              if (_saved) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    const Text('已保存到知识库'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        if (!widget.saveAutomatically && !_saved && _content != null)
          FilledButton(
            onPressed: selectedCategory == null || _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = _error;
    if (error != null) {
      return Column(
        children: [
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => unawaited(_loadCategory(_categoryId)),
            child: const Text('重试'),
          ),
        ],
      );
    }
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    return MarkdownWithLatex(
      content: content,
      onTapKnowledgeAnnotation: null,
      onExplainSelection: null,
    );
  }
}
