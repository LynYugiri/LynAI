import 'dart:convert';

import '../models/agent_runtime.dart';

class AgentProtocolCodec {
  const AgentProtocolCodec();

  Map<String, dynamic> assistantToolCallMessage(
    String content,
    Iterable<AgentToolInvocation> calls,
  ) {
    return {
      'role': 'assistant',
      'content': content,
      'reasoning_content': '',
      'tool_calls': calls
          .map(
            (call) => {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> toolResultMessage(AgentToolResult result) {
    return {
      'role': 'tool',
      'tool_call_id': result.invocationId,
      'content': jsonEncode(_resultPayload(result)),
    };
  }

  Object? _resultPayload(AgentToolResult result) {
    if (result.status == AgentToolResultStatus.success) return result.value;
    if (result.value != null) return result.value;
    return {
      'ok': false,
      'error': {
        'code': result.errorCode ?? 'tool_execution_failed',
        'message': result.errorMessage ?? 'Tool execution failed',
      },
    };
  }
}
