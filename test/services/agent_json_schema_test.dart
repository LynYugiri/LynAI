import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_json_schema.dart';

void main() {
  const validator = AgentJsonSchemaValidator();

  test('validates nested practical object schemas strictly', () {
    final schema = <String, dynamic>{
      'type': 'object',
      'required': ['name', 'steps'],
      'additionalProperties': false,
      'properties': {
        'name': {'type': 'string', 'minLength': 2, 'pattern': r'^[a-z]+$'},
        'priority': {'type': 'integer', 'minimum': 1, 'maximum': 5},
        'steps': {
          'type': 'array',
          'minItems': 1,
          'items': {
            'type': 'object',
            'required': ['kind'],
            'additionalProperties': false,
            'properties': {
              'kind': {
                'type': 'string',
                'enum': ['read', 'write'],
              },
            },
          },
        },
      },
    };

    expect(
      validator.validate({
        'name': 'agent',
        'priority': 3,
        'steps': [
          {'kind': 'read'},
        ],
      }, schema).isValid,
      isTrue,
    );

    final invalid = validator.validate({
      'name': 'A',
      'priority': 3.5,
      'steps': [
        {'kind': 'delete', 'extra': true},
      ],
      'unknown': true,
    }, schema);
    expect(invalid.isValid, isFalse);
    expect(
      invalid.issues.map((issue) => issue.path),
      containsAll([
        r'$.name',
        r'$.priority',
        r'$.steps[0].kind',
        r'$.steps[0].extra',
        r'$.unknown',
      ]),
    );
  });

  test('supports composition and rejects unsupported schema keywords', () {
    final composed = validator.validate('ok', {
      'allOf': [
        {'type': 'string'},
        {
          'anyOf': [
            {'const': 'ok'},
            {'const': 'also-ok'},
          ],
        },
      ],
    });
    expect(composed.isValid, isTrue);

    final ambiguous = validator.validate(1, {
      'oneOf': [
        {'type': 'number'},
        {'type': 'integer'},
      ],
    });
    expect(ambiguous.isValid, isFalse);

    final unsupported = validator.validateSchema({
      'type': 'string',
      'format': 'uri',
    });
    expect(unsupported.isValid, isFalse);
    expect(unsupported.issues.single.message, contains('unsupported keyword'));
  });
}
