import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/onboarding/onboarding_draft.dart';
import '../models/onboarding/onboarding_input.dart';
import '../providers/feature_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/memory_card_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../services/onboarding_service.dart';

/// 新手向导的内存状态控制器。
///
/// 保存用户输入、当前编辑草稿、生成/应用状态。向导页面只调用本控制器和
/// [OnboardingService]，不直接拼装设置。
class OnboardingWizardController extends ChangeNotifier {
  OnboardingInput _input = OnboardingInput.empty();
  OnboardingDraft? _draft;
  OnboardingApplyResult? _applyResult;
  bool _generating = false;
  bool _applying = false;
  String? _error;

  OnboardingInput get input => _input;
  OnboardingDraft? get draft => _draft;
  OnboardingApplyResult? get applyResult => _applyResult;
  bool get generating => _generating;
  bool get applying => _applying;
  String? get error => _error;
  bool get hasDraft => _draft != null;

  /// 从设置中恢复上次保存的输入，用于重新进入向导时预填。
  void loadLastInput(SettingsProvider settingsProvider) {
    final raw = settingsProvider.settings.onboardingInputJson;
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _input = OnboardingInput.fromJson(Map<String, dynamic>.from(decoded));
        notifyListeners();
      }
    } catch (_) {
      // 上次输入损坏时使用空输入。
    }
  }

  void setInput(OnboardingInput input) {
    _input = input;
    notifyListeners();
  }

  void setPurposes(List<String> purposes) {
    _input = _input.copyWith(
      purposes: purposes.toSet().toList(growable: false),
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setOccupation(String occupation, {String custom = ''}) {
    _input = _input.copyWith(
      occupation: occupation,
      occupationCustom: custom,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  void setFreeText(String text) {
    _input = _input.copyWith(freeText: text, updatedAt: DateTime.now());
    notifyListeners();
  }

  void updateDraft(OnboardingDraft draft) {
    _draft = draft;
    notifyListeners();
  }

  Future<void> generate(OnboardingService service) async {
    _generating = true;
    _error = null;
    _applyResult = null;
    notifyListeners();
    try {
      final draft = await service.generate(input: _input, currentDraft: _draft);
      _draft = draft;
    } catch (e) {
      _error = '生成失败: $e';
    } finally {
      _generating = false;
      notifyListeners();
    }
  }

  Future<void> regenerate(OnboardingService service) async {
    await generate(service);
  }

  Future<void> apply(
    OnboardingService service, {
    required SettingsProvider settingsProvider,
    required KnowledgeProvider knowledgeProvider,
    required MemoryCardProvider memoryCardProvider,
    required TaskProvider taskProvider,
    required FeatureProvider featureProvider,
    required PluginProvider pluginProvider,
  }) async {
    final draft = _draft;
    if (draft == null) return;
    _applying = true;
    _error = null;
    notifyListeners();
    try {
      _applyResult = await service.applyDraft(
        draft: draft,
        settingsProvider: settingsProvider,
        knowledgeProvider: knowledgeProvider,
        memoryCardProvider: memoryCardProvider,
        taskProvider: taskProvider,
        featureProvider: featureProvider,
        pluginProvider: pluginProvider,
      );
    } catch (e) {
      _error = '应用失败: $e';
    } finally {
      _applying = false;
      notifyListeners();
    }
  }

  /// 标记向导完成并保存本次输入，供下次重新进入时预填。
  Future<void> finish(
    SettingsProvider settingsProvider, {
    bool skipped = false,
  }) async {
    final input = skipped ? OnboardingInput.empty() : _input;
    final updated = settingsProvider.settings.copyWith(
      hasCompletedOnboarding: true,
      onboardingInputJson: input.isEmpty ? null : jsonEncode(input.toJson()),
    );
    await settingsProvider.replaceSettings(updated);
  }
}
