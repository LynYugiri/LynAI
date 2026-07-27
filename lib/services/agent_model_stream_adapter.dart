import '../models/agent_runtime.dart';

abstract interface class AgentModelStreamAdapter<T> {
  Stream<AgentModelStreamEvent> adapt(Stream<T> source);
}
