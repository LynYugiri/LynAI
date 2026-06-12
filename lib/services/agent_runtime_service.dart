import 'package:uuid/uuid.dart';

import '../models/agent_plan.dart';
import '../models/agent_trace.dart';
import '../providers/conversation_provider.dart';

class AgentRuntimeService {
  static const _uuid = Uuid();

  const AgentRuntimeService();

  Map<String, dynamic> addNote(
    ConversationProvider conversations,
    String conversationId,
    Map<String, dynamic> args,
  ) {
    final conv = conversations.getConversation(conversationId);
    if (conv?.settings.agentEnabled != true) {
      return error('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final content = (args['content'] as String? ?? '').trim();
    if (content.isEmpty) {
      return error('invalid_arguments', 'add_agent_note 缺少 content');
    }
    final limited = content.length > 500 ? content.substring(0, 500) : content;
    appendTrace(
      conversations,
      conversationId,
      AgentTraceEvent.assistantNote,
      'Agent 说明',
      content: limited,
    );
    return ok({'noted': true});
  }

  Map<String, dynamic> createPlan(
    ConversationProvider conversations,
    String conversationId,
    Map<String, dynamic> args,
  ) {
    final conv = conversations.getConversation(conversationId);
    if (conv == null) return error('missing_context', '对话不存在');
    if (!conv.settings.agentEnabled) {
      return error('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final title = (args['title'] as String? ?? 'Agent Plan').trim();
    final rawItems = args['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return error('invalid_arguments', 'create_plan 缺少 items');
    }
    final items = <AgentPlanItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final itemTitle = (json['title'] as String? ?? '').trim();
      if (itemTitle.isEmpty) continue;
      final id = (json['id'] as String? ?? '').trim();
      items.add(
        AgentPlanItem(
          id: id.isEmpty ? 'step_${items.length + 1}' : id,
          title: itemTitle,
        ),
      );
    }
    if (items.isEmpty) {
      return error('invalid_arguments', 'create_plan 没有有效步骤');
    }
    final now = DateTime.now();
    final plan = AgentPlan(
      id: 'plan_${now.microsecondsSinceEpoch}',
      title: title.isEmpty ? 'Agent Plan' : title,
      items: items,
      createdAt: now,
      updatedAt: now,
    );
    conversations.updateAgentPlan(conversationId, plan);
    appendTrace(
      conversations,
      conversationId,
      AgentTraceEvent.planUpdate,
      '创建 Agent 计划',
      content: '${plan.items.length} 个步骤',
      metadata: {'planId': plan.id},
    );
    return ok({'plan': plan.toJson()});
  }

  Map<String, dynamic> updatePlan(
    ConversationProvider conversations,
    String conversationId,
    Map<String, dynamic> args,
  ) {
    final conv = conversations.getConversation(conversationId);
    if (conv == null) return error('missing_context', '对话不存在');
    if (!conv.settings.agentEnabled) {
      return error('agent_disabled', '当前对话未启用 Agent 模式');
    }
    final plan = conv.agentPlan;
    if (plan == null) return error('plan_not_found', '当前对话没有 Agent Plan');
    final rawItems = args['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      return error('invalid_arguments', 'update_plan 缺少 items');
    }
    final updates = <String, Map<String, dynamic>>{};
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final id = (json['id'] as String? ?? '').trim();
      final status = (json['status'] as String? ?? '').trim();
      if (id.isEmpty || !AgentPlanItem.statuses.contains(status)) continue;
      updates[id] = json;
    }
    if (updates.isEmpty) {
      return error('invalid_arguments', 'update_plan 没有有效更新');
    }
    final known = plan.items.map((item) => item.id).toSet();
    final unknown = updates.keys.where((id) => !known.contains(id)).toList();
    if (unknown.isNotEmpty) {
      return error('plan_step_not_found', '未知计划步骤: ${unknown.join(', ')}');
    }
    final nextItems = plan.items
        .map((item) {
          final update = updates[item.id];
          if (update == null) return item;
          var next = item.copyWith(status: update['status'] as String);
          if (update.containsKey('summary')) {
            next = next.copyWith(
              summary: (update['summary'] as String? ?? '').trim(),
            );
          }
          if (update.containsKey('resultSummary')) {
            next = next.copyWith(
              resultSummary: (update['resultSummary'] as String? ?? '').trim(),
            );
          }
          if (update.containsKey('error')) {
            next = next.copyWith(
              error: (update['error'] as String? ?? '').trim(),
            );
          }
          return next;
        })
        .toList(growable: false);
    final next = plan.copyWith(items: nextItems, updatedAt: DateTime.now());
    conversations.updateAgentPlan(conversationId, next);
    appendTrace(
      conversations,
      conversationId,
      AgentTraceEvent.planUpdate,
      '更新 Agent 计划',
      content: '${updates.length} 个步骤已更新',
      metadata: {'updatedStepIds': updates.keys.toList(growable: false)},
    );
    return ok({'plan': next.toJson()});
  }

  void appendTrace(
    ConversationProvider conversations,
    String conversationId,
    String type,
    String title, {
    String? content,
    Map<String, dynamic>? metadata,
  }) {
    conversations.appendAgentTraceEvent(
      conversationId,
      AgentTraceEvent(
        id: _uuid.v4(),
        type: type,
        title: title,
        content: content,
        metadata: metadata,
        timestamp: DateTime.now(),
      ),
    );
  }

  static Map<String, dynamic> error(
    String code,
    String message, {
    Map<String, dynamic>? details,
  }) => {
    'ok': false,
    'error': {
      'code': code,
      'message': message,
      if (details != null && details.isNotEmpty) 'details': details,
    },
  };

  static Map<String, dynamic> ok([Map<String, dynamic>? result]) {
    if (result == null) return {'ok': true};
    return {'ok': true, 'result': result};
  }
}
