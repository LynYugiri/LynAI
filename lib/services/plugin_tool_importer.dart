import '../models/agent_runtime.dart';
import 'agent_tool_name_codec.dart';

final AgentToolNameCodec pluginToolNameCodec = AgentToolNameCodec();

String canonicalPluginToolName(String pluginId, String toolName) =>
    pluginToolNameCodec.encode(
      source: AgentToolSource.plugin,
      namespace: pluginId,
      name: toolName,
    );
