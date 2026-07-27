import 'dart:collection';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_json_schema.dart';

typedef AgentToolHandler =
    Future<Object?> Function(
      AgentToolInvocation invocation,
      AgentCancellationToken cancellationToken,
    );

class AgentToolRegistration {
  final String registrationId;
  final int version;
  final AgentToolDescriptor descriptor;
  final AgentToolHandler handler;

  const AgentToolRegistration({
    required this.registrationId,
    required this.version,
    required this.descriptor,
    required this.handler,
  });
}

class AgentToolSnapshot {
  final int registryVersion;
  final Map<String, AgentToolRegistration> _registrations;

  AgentToolSnapshot._(
    this.registryVersion,
    Map<String, AgentToolRegistration> registrations,
  ) : _registrations = UnmodifiableMapView(registrations);

  Iterable<AgentToolRegistration> get registrations => _registrations.values;

  AgentToolRegistration? operator [](String name) => _registrations[name];

  bool isStaleAgainst(AgentToolRegistry registry) {
    return registryVersion != registry.version;
  }

  bool isRegistrationCurrent(AgentToolRegistry registry, String toolName) {
    final captured = _registrations[toolName];
    final current = registry.registration(toolName);
    return captured != null &&
        current != null &&
        captured.registrationId == current.registrationId &&
        captured.version == current.version;
  }
}

class AgentToolRegistry {
  final AgentJsonSchemaValidator _schemaValidator;
  final Map<String, AgentToolRegistration> _registrations = {};
  int _version = 0;
  int _nextRegistrationId = 0;

  AgentToolRegistry({
    AgentJsonSchemaValidator schemaValidator = const AgentJsonSchemaValidator(),
  }) : _schemaValidator = schemaValidator;

  int get version => _version;

  AgentToolRegistration register(
    AgentToolDescriptor descriptor,
    AgentToolHandler handler,
  ) {
    final schemaValidation = _schemaValidator.validateSchema(
      descriptor.parameters,
    );
    if (!schemaValidation.isValid) {
      throw ArgumentError.value(
        descriptor.parameters,
        'descriptor.parameters',
        schemaValidation.issues.join('; '),
      );
    }
    final previous = _registrations[descriptor.name];
    final registration = AgentToolRegistration(
      registrationId: 'tool_${++_nextRegistrationId}',
      version: (previous?.version ?? 0) + 1,
      descriptor: descriptor,
      handler: handler,
    );
    _registrations[descriptor.name] = registration;
    _version++;
    return registration;
  }

  bool unregister(String name) {
    if (_registrations.remove(name) == null) return false;
    _version++;
    return true;
  }

  AgentToolRegistration? registration(String name) => _registrations[name];

  AgentToolSnapshot snapshot() {
    return AgentToolSnapshot._(_version, Map.of(_registrations));
  }
}
