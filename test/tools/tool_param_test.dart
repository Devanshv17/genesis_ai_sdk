import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('ToolParam', () {
    // ── factory constructors ─────────────────────────────────────────────────

    test('string param has correct type and description', () {
      final p = ToolParam.string(description: 'City name', required: true);
      expect(p.type, ToolParamType.string);
      expect(p.description, 'City name');
      expect(p.required, isTrue);
    });

    test('string param defaults required to false', () {
      expect(ToolParam.string(description: 'x').required, isFalse);
    });

    test('stringEnum param sets enumValues', () {
      final p = ToolParam.stringEnum(
        ['celsius', 'fahrenheit'],
        description: 'Unit',
      );
      expect(p.type, ToolParamType.string);
      expect(p.enumValues, ['celsius', 'fahrenheit']);
    });

    test('number param has number type', () {
      final p = ToolParam.number(description: 'Price');
      expect(p.type, ToolParamType.number);
    });

    test('integer param has integer type', () {
      final p = ToolParam.integer(description: 'Count');
      expect(p.type, ToolParamType.integer);
    });

    test('boolean param has boolean type', () {
      final p = ToolParam.boolean(description: 'Enabled');
      expect(p.type, ToolParamType.boolean);
    });

    test('array param has array type and items schema', () {
      final p = ToolParam.array(
        description: 'Tags',
        items: ToolParam.string(description: 'Tag'),
      );
      expect(p.type, ToolParamType.array);
      expect(p.items, isNotNull);
    });

    test('object param has object type and properties', () {
      final p = ToolParam.object(
        description: 'Address',
        properties: {
          'city': ToolParam.string(description: 'City', required: true),
          'zip': ToolParam.string(description: 'ZIP'),
        },
      );
      expect(p.type, ToolParamType.object);
      expect(p.properties, hasLength(2));
    });

    // ── toJsonSchema / toSchema ──────────────────────────────────────────────

    test('string param serialises to correct JSON Schema', () {
      final schema = ToolParam.string(description: 'Name', required: true)
          .toJsonSchema();
      expect(schema['type'], 'string');
      expect(schema['description'], 'Name');
    });

    test('toSchema is an alias for toJsonSchema', () {
      final p = ToolParam.integer(description: 'Count');
      expect(p.toSchema(), p.toJsonSchema());
    });

    test('stringEnum adds enum key to schema', () {
      final schema = ToolParam.stringEnum(
        ['a', 'b'],
        description: 'Choice',
      ).toJsonSchema();
      expect(schema['enum'], ['a', 'b']);
    });

    test('defaultValue is included in schema', () {
      final schema = ToolParam.string(
        description: 'Unit',
        defaultValue: 'celsius',
      ).toJsonSchema();
      expect(schema['default'], 'celsius');
    });

    test('array schema includes items', () {
      final schema = ToolParam.array(
        description: 'Tags',
        items: ToolParam.string(description: 'Tag'),
      ).toJsonSchema();
      expect(schema['type'], 'array');
      expect(schema['items'], isA<Map>());
      expect((schema['items'] as Map)['type'], 'string');
    });

    test('object schema includes properties and required list', () {
      final schema = ToolParam.object(
        description: 'Person',
        properties: {
          'name': ToolParam.string(description: 'Name', required: true),
          'age': ToolParam.integer(description: 'Age'),
        },
      ).toJsonSchema();
      expect(schema['type'], 'object');
      expect((schema['properties'] as Map).containsKey('name'), isTrue);
      expect(schema['required'], ['name']);
    });

    test('object schema omits required key when no params are required', () {
      final schema = ToolParam.object(
        description: 'Opts',
        properties: {
          'x': ToolParam.string(description: 'x'),
        },
      ).toJsonSchema();
      expect(schema.containsKey('required'), isFalse);
    });

    // ── buildParametersSchema ────────────────────────────────────────────────

    test('buildParametersSchema wraps params in object envelope', () {
      final schema = buildParametersSchema({
        'city': ToolParam.string(description: 'City', required: true),
        'limit': ToolParam.integer(description: 'Limit'),
      });
      expect(schema['type'], 'object');
      expect((schema['properties'] as Map).keys, containsAll(['city', 'limit']));
      expect(schema['required'], ['city']);
    });

    test('buildParametersSchema omits required key when none required', () {
      final schema = buildParametersSchema({
        'x': ToolParam.string(description: 'X'),
      });
      expect(schema.containsKey('required'), isFalse);
    });
  });
}
