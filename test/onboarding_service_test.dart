import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/onboarding/onboarding_input.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';
import 'package:lynai/services/onboarding_service.dart';

void main() {
  test('permissionsForIntents maps intents to assignable permissions', () {
    final service = OnboardingService();
    final permissions = service.permissionsForIntents(['notes', 'todos']);

    expect(
      permissions,
      containsAll([
        LynAIPermissions.notesRead,
        LynAIPermissions.notesWrite,
        LynAIPermissions.notesPropose,
        LynAIPermissions.todosRead,
        LynAIPermissions.todosWrite,
      ]),
    );
    expect(
      permissions.every(LynAIPermissions.agentAssignable.contains),
      isTrue,
    );
  });

  test('permissionsForIntents falls back to minimal model chat', () {
    final service = OnboardingService();
    final permissions = service.permissionsForIntents(['minimal']);
    expect(permissions, contains(LynAIPermissions.modelChat));
  });

  test('safeSystemPrompt appends tool safety exactly once', () {
    final service = OnboardingService();
    final prompt = service.safeSystemPrompt('你是一个助手');
    expect(prompt, contains('DSML'));
    final again = service.safeSystemPrompt(prompt);
    expect(again, prompt);
  });

  test('buildLocalDraft for student creates knowledge, deck and tasks', () {
    final service = OnboardingService();
    final draft = service.buildLocalDraft(
      OnboardingInput(
        userName: '小明',
        purposes: const ['knowledge', 'cards', 'todos'],
        occupation: 'student',
        freeText: '准备考研',
        updatedAt: DateTime.now(),
      ),
    );

    expect(draft.role.name, '学习助手');
    expect(draft.role.systemPrompt, contains('学生'));
    expect(draft.role.systemPrompt, contains('小明'));
    expect(draft.roleMemory.goal, '准备考研');
    expect(draft.knowledgeBases, isNotEmpty);
    expect(draft.knowledgeBases.single.categories.length, 2);
    expect(draft.memoryDecks, isNotEmpty);
    expect(draft.taskLists, isNotEmpty);
    expect(draft.agent.enabledByDefault, isTrue);
    expect(draft.welcomeMessage, contains('小明'));
    expect(draft.welcomeMessage, contains('学习助手'));
    expect(draft.welcomeMessage, contains('学习资料库'));
    expect(draft.welcomeMessage, contains('准备考研'));
  });

  test(
    'generate falls back to local draft when no api/model provider',
    () async {
      final service = OnboardingService();
      final draft = await service.generate(
        input: OnboardingInput(
          purposes: const ['writing'],
          occupation: 'creator',
          updatedAt: DateTime.now(),
        ),
      );
      expect(draft.role.name, '创作助手');
      expect(draft.noteFolders, isNotEmpty);
      expect(draft.welcomeMessage, isNotEmpty);
    },
  );

  test('generateWelcome falls back to local welcome without api', () async {
    final service = OnboardingService();
    final draft = service.buildLocalDraft(
      OnboardingInput(
        purposes: const ['knowledge'],
        occupation: 'researcher',
        updatedAt: DateTime.now(),
      ),
    );
    final welcome = await service.generateWelcome(
      input: OnboardingInput(
        purposes: const ['knowledge'],
        occupation: 'researcher',
        updatedAt: DateTime.now(),
      ),
      draft: draft,
    );
    expect(welcome, contains('研究助手'));
    expect(welcome, contains('我的知识库'));
  });
}
