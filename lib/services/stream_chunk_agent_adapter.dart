import '../models/agent_runtime.dart';
import 'agent_model_stream_adapter.dart';
import 'api_service.dart';

class StreamChunkAgentAdapter implements AgentModelStreamAdapter<StreamChunk> {
  const StreamChunkAgentAdapter();

  @override
  Stream<AgentModelStreamEvent> adapt(Stream<StreamChunk> source) async* {
    try {
      await for (final chunk in source) {
        final content = chunk.content;
        if (content != null && content.isNotEmpty) {
          yield AgentModelTextDelta(content);
        }
        final reasoning = chunk.reasoningContent;
        if (reasoning != null && reasoning.isNotEmpty) {
          yield AgentModelReasoningDelta(reasoning);
        }
        if (chunk.toolCalls.isNotEmpty) {
          yield AgentModelToolCalls(
            chunk.toolCalls.map(
              (call) => AgentToolInvocation(
                id: call.id,
                name: call.name,
                arguments: call.arguments,
              ),
            ),
          );
        }
        if (chunk.isDone) {
          yield const AgentModelStreamCompleted();
          return;
        }
      }
      yield const AgentModelStreamCompleted();
    } catch (error, stackTrace) {
      yield AgentModelStreamFailure(error, stackTrace);
    }
  }
}
