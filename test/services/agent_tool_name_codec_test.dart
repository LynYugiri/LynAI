import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/services/agent_tool_name_codec.dart';

void main() {
  test('canonical names distinguish framing, Unicode, and reserved inputs', () {
    final codec = AgentToolNameCodec();
    final names = {
      codec.encode(source: AgentToolSource.mcp, namespace: 'a_b', name: 'c'),
      codec.encode(source: AgentToolSource.mcp, namespace: 'a', name: 'b_c'),
      codec.encode(
        source: AgentToolSource.plugin,
        namespace: '服务器',
        name: '天气/查询',
      ),
      codec.encode(
        source: AgentToolSource.runtime,
        namespace: 'system_',
        name: 'mcp_tool',
      ),
    };

    expect(names, hasLength(4));
    expect(
      names.every(
        (name) => AgentToolNameCodec.reservedPrefixes.every(
          (prefix) => !name.startsWith(prefix),
        ),
      ),
      isTrue,
    );
  });

  test('canonical names avoid legacy escape and boundary collisions', () {
    final codec = AgentToolNameCodec();
    final names = {
      codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server.name',
        name: 'tool',
      ),
      codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server_2e_name',
        name: 'tool',
      ),
      codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server',
        name: 'name_tool',
      ),
      codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server_name',
        name: 'tool',
      ),
      codec.encode(source: AgentToolSource.mcp, namespace: '服务器', name: '天气'),
      codec.encode(source: AgentToolSource.mcp, namespace: '服务器', name: '天_气'),
    };

    expect(names, hasLength(6));
    expect(names.every((name) => name.length <= 64), isTrue);
  });

  test('length fallback reports digest collisions explicitly', () {
    final codec = AgentToolNameCodec(
      maxLength: 28,
      digest: (input) => List<int>.filled(32, 7),
    );
    final first = codec.encode(
      source: AgentToolSource.mcp,
      namespace: 'server-${'x' * 100}',
      name: 'tool-a',
    );
    expect(
      () => codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server-${'x' * 100}',
        name: 'tool-b',
      ),
      throwsA(isA<AgentToolNameCollisionException>()),
    );
    expect(first.length, lessThanOrEqualTo(28));
    expect(
      codec.encode(
        source: AgentToolSource.mcp,
        namespace: 'server-${'x' * 100}',
        name: 'tool-a',
      ),
      first,
    );
  });
}
