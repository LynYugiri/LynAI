import 'dart:async';
import 'dart:collection';

import '../models/agent_runtime.dart';
import 'agent_cancellation.dart';
import 'agent_json_schema.dart';
import 'lynai_permission_definitions.dart';

typedef AgentToolHandler =
    Future<Object?> Function(
      AgentToolInvocation invocation,
      AgentCancellationToken cancellationToken,
    );

typedef AgentToolContextHandler =
    Future<Object?> Function(
      AgentToolInvocation invocation,
      AgentToolExecutionContext context,
    );

typedef AgentToolConcurrencyKeyResolver =
    String Function(
      AgentToolInvocation invocation,
      AgentToolExecutionIdentity identity,
    );

typedef AgentToolAuthorizer =
    FutureOr<bool> Function(
      AgentToolRegistration registration,
      AgentToolExecutionContext context,
    );

typedef AgentToolErrorSanitizer = String Function(Object error);

class AgentToolExecutionContext {
  final AgentToolExecutionIdentity identity;
  final AgentPermissionSnapshot permissionSnapshot;
  final AgentCancellationToken cancellationToken;
  final AgentToolSnapshot snapshot;
  final DateTime deadline;

  const AgentToolExecutionContext({
    required this.identity,
    required this.permissionSnapshot,
    required this.cancellationToken,
    required this.snapshot,
    required this.deadline,
  });
}

class AgentToolRegistrationSpec {
  final AgentToolDescriptor descriptor;
  final AgentToolPermissionRequirements permissionRequirements;
  final AgentToolSemantics semantics;

  AgentToolRegistrationSpec({
    required this.descriptor,
    AgentToolPermissionRequirements? permissionRequirements,
    this.semantics = const AgentToolSemantics(),
  }) : permissionRequirements =
           permissionRequirements ?? AgentToolPermissionRequirements() {
    if (semantics.timeout <= Duration.zero) {
      throw ArgumentError.value(
        semantics.timeout,
        'semantics.timeout',
        'must be positive',
      );
    }
  }
}

class AgentToolRegistration {
  final String registrationId;
  final int version;
  final AgentToolRegistrationSpec spec;
  final AgentToolContextHandler handler;
  final AgentToolConcurrencyKeyResolver? concurrencyKeyResolver;

  const AgentToolRegistration({
    required this.registrationId,
    required this.version,
    required this.spec,
    required this.handler,
    this.concurrencyKeyResolver,
  });

  AgentToolDescriptor get descriptor => spec.descriptor;
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

  AgentToolSnapshot where(
    bool Function(AgentToolRegistration registration) include,
  ) {
    return AgentToolSnapshot._(registryVersion, {
      for (final registration in _registrations.values)
        if (include(registration)) registration.descriptor.name: registration,
    });
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
    return registerSpec(
      AgentToolRegistrationSpec(descriptor: descriptor),
      (invocation, context) => handler(invocation, context.cancellationToken),
      concurrencyKeyResolver:
          descriptor.concurrency == AgentToolConcurrency.keyed
          ? (invocation, identity) =>
                invocation.concurrencyKey ?? descriptor.name
          : null,
    );
  }

  AgentToolRegistration registerSpec(
    AgentToolRegistrationSpec spec,
    AgentToolContextHandler handler, {
    AgentToolConcurrencyKeyResolver? concurrencyKeyResolver,
  }) {
    final descriptor = spec.descriptor;
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
    if (descriptor.concurrency == AgentToolConcurrency.keyed &&
        concurrencyKeyResolver == null) {
      throw ArgumentError.notNull('concurrencyKeyResolver');
    }
    final previous = _registrations[descriptor.name];
    final registration = AgentToolRegistration(
      registrationId: 'tool_${++_nextRegistrationId}',
      version: (previous?.version ?? 0) + 1,
      spec: spec,
      handler: handler,
      concurrencyKeyResolver: concurrencyKeyResolver,
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
