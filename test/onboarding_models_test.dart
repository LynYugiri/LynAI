import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_working_memory.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/chat_role.dart';
import 'package:lynai/models/onboarding/onboarding_draft.dart';
import 'package:lynai/models/onboarding/onboarding_input.dart';

void main() {
  test('AppSettings defaults trigger onboarding for fresh installs', () {
    final settings = AppSettings.defaults();
    expect(settings.hasCompletedOnboarding, isFalse);
    expect(settings.onboardingVersion, 1);
  });

  test('AppSettings from legacy JSON does not trigger onboarding', () {
    final legacy = AppSettings.defaults().toJson()
      ..remove('hasCompletedOnboarding')
      ..remove('hasCompletedGuidedTour')
      ..remove('onboardingInputJson')
      ..remove('onboardingVersion');
    final settings = AppSettings.fromJson(legacy);
    expect(settings.hasCompletedOnboarding, isTrue);
    expect(settings.hasCompletedGuidedTour, isTrue);
  });

  test('AppSettings onboarding fields round-trip', () {
    final settings = AppSettings.defaults().copyWith(
      hasCompletedOnboarding: true,
      hasCompletedGuidedTour: false,
      onboardingInputJson: '{"version":1,"purposes":["knowledge"]}',
      onboardingVersion: 3,
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.hasCompletedOnboarding, isTrue);
    expect(restored.hasCompletedGuidedTour, isFalse);
    expect(
      restored.onboardingInputJson,
      '{"version":1,"purposes":["knowledge"]}',
    );
    expect(restored.onboardingVersion, 3);
  });

  test('ChatRole default memory round-trip and legacy fallback', () {
    final now = DateTime.now();
    final role = ChatRole(
      id: 'r1',
      name: '学习助手',
      systemPrompt: 'help',
      defaultMemory: AgentWorkingMemory(
        goal: '帮助学习',
        entries: [
          AgentMemoryEntry(
            id: 'm1',
            kind: AgentMemoryEntry.fact,
            content: '用户是学生',
            pinned: true,
            createdAt: now,
          ),
        ],
        updatedAt: now,
      ),
    );

    final restored = ChatRole.fromJson(role.toJson());
    expect(restored.defaultMemory?.goal, '帮助学习');
    expect(restored.defaultMemory?.entries.single.content, '用户是学生');

    final legacy = role.toJson()..remove('defaultMemory');
    expect(ChatRole.fromJson(legacy).defaultMemory, isNull);
  });

  test('OnboardingInput round-trip trims duplicates', () {
    final input = OnboardingInput(
      purposes: const ['knowledge', 'knowledge', 'todos'],
      occupation: 'student',
      occupationCustom: ' 考研学生 ',
      freeText: ' 请帮我复习 ',
      updatedAt: DateTime.now(),
    );
    final restored = OnboardingInput.fromJson(
      jsonDecode(jsonEncode(input.toJson())) as Map<String, dynamic>,
    );
    expect(restored.purposes, ['knowledge', 'todos']);
    expect(restored.occupationCustom, '考研学生');
    expect(restored.freeText, '请帮我复习');
  });

  test('OnboardingDraft round-trip', () {
    final draft = OnboardingDraft(
      role: const OnboardingRoleDraft(
        name: '学习助手',
        description: 'desc',
        systemPrompt: 'prompt',
      ),
      roleMemory: AgentWorkingMemory(
        goal: 'goal',
        entries: [
          AgentMemoryEntry(
            id: 'm1',
            kind: AgentMemoryEntry.note,
            content: 'entry',
            createdAt: DateTime.now(),
          ),
        ],
        updatedAt: DateTime.now(),
      ),
      agent: const OnboardingAgentDraft(
        enabledByDefault: true,
        intents: ['notes', 'todos'],
      ),
      knowledgeBases: [
        OnboardingKnowledgeBaseDraft(
          name: 'kb',
          categories: [
            OnboardingKnowledgeCategoryDraft(name: 'cat', alias: 'cat_alias'),
          ],
          entries: [
            OnboardingKnowledgeEntryDraft(
              title: 'entry',
              content: 'content',
              categoryName: 'cat',
            ),
          ],
        ),
      ],
      memoryDecks: [
        OnboardingMemoryDeckDraft(
          name: 'deck',
          cards: [OnboardingMemoryCardDraft(front: 'f', back: 'b', hint: 'h')],
        ),
      ],
      taskLists: [
        OnboardingTaskListDraft(
          title: 'list',
          tasks: [OnboardingTaskDraft(title: 'task', note: 'note')],
        ),
      ],
      noteFolders: [
        OnboardingNoteFolderDraft(
          title: 'folder',
          notes: [OnboardingNoteDraft(title: 'note', content: 'content')],
        ),
      ],
      skill: OnboardingSkillDraft(
        pluginId: 'user-onboarding-skill',
        name: 'my_skill',
        title: 'My Skill',
        description: 'desc',
        body: 'body',
      ),
      welcomeMessage: '你好，我是学习助手。',
    );

    final restored = OnboardingDraft.fromJson(
      jsonDecode(jsonEncode(draft.toJson())) as Map<String, dynamic>,
    );
    expect(restored.role.name, '学习助手');
    expect(restored.roleMemory.goal, 'goal');
    expect(restored.agent.intents, ['notes', 'todos']);
    expect(restored.knowledgeBases.single.categories.single.alias, 'cat_alias');
    expect(restored.memoryDecks.single.cards.single.front, 'f');
    expect(restored.taskLists.single.tasks.single.title, 'task');
    expect(restored.noteFolders.single.notes.single.content, 'content');
    expect(restored.skill?.name, 'my_skill');
    expect(restored.welcomeMessage, '你好，我是学习助手。');
  });
}
