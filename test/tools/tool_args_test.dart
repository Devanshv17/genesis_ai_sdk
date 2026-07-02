import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('ToolArgs', () {
    // ── string ───────────────────────────────────────────────────────────────

    test('string returns value when present', () {
      final args = ToolArgs({'city': 'London'});
      expect(args.string('city'), 'London');
    });

    test('string returns fallback for missing key', () {
      final args = ToolArgs({});
      expect(args.string('city'), '');
      expect(args.string('city', fallback: 'Unknown'), 'Unknown');
    });

    test('string coerces int to string via toString', () {
      final args = ToolArgs({'count': 42});
      expect(args.string('count'), '42');
    });

    // ── integer ──────────────────────────────────────────────────────────────

    test('integer returns int value', () {
      final args = ToolArgs({'limit': 10});
      expect(args.integer('limit'), 10);
    });

    test('integer coerces double to int', () {
      final args = ToolArgs({'limit': 3.9});
      expect(args.integer('limit'), 3);
    });

    test('integer returns fallback for missing key', () {
      final args = ToolArgs({});
      expect(args.integer('limit'), 0);
      expect(args.integer('limit', fallback: 5), 5);
    });

    // ── number ───────────────────────────────────────────────────────────────

    test('number returns double value', () {
      final args = ToolArgs({'price': 9.99});
      expect(args.number('price'), closeTo(9.99, 0.001));
    });

    test('number coerces int to double', () {
      final args = ToolArgs({'price': 10});
      expect(args.number('price'), 10.0);
    });

    test('number returns fallback for missing key', () {
      final args = ToolArgs({});
      expect(args.number('price'), 0.0);
      expect(args.number('price', fallback: 1.5), 1.5);
    });

    // ── boolean ──────────────────────────────────────────────────────────────

    test('boolean returns true when value is true', () {
      final args = ToolArgs({'enabled': true});
      expect(args.boolean('enabled'), isTrue);
    });

    test('boolean returns false when value is false', () {
      final args = ToolArgs({'enabled': false});
      expect(args.boolean('enabled'), isFalse);
    });

    test('boolean returns fallback for missing key', () {
      expect(ToolArgs({}).boolean('enabled'), isFalse);
      expect(ToolArgs({}).boolean('enabled', fallback: true), isTrue);
    });

    // ── list ─────────────────────────────────────────────────────────────────

    test('list returns typed list', () {
      final args = ToolArgs({'tags': ['a', 'b', 'c']});
      expect(args.list<String>('tags'), ['a', 'b', 'c']);
    });

    test('list returns empty list for missing key', () {
      expect(ToolArgs({}).list<String>('tags'), isEmpty);
    });

    // ── map ──────────────────────────────────────────────────────────────────

    test('map returns nested map', () {
      final args = ToolArgs({'address': {'city': 'Paris', 'zip': '75001'}});
      expect(args.map('address'), {'city': 'Paris', 'zip': '75001'});
    });

    test('map returns empty map for missing key', () {
      expect(ToolArgs({}).map('address'), isEmpty);
    });

    // ── nested ───────────────────────────────────────────────────────────────

    test('nested returns ToolArgs wrapping the sub-map', () {
      final args = ToolArgs({'user': {'name': 'Alice', 'age': 30}});
      final user = args.nested('user');
      expect(user.string('name'), 'Alice');
      expect(user.integer('age'), 30);
    });

    // ── nestedList ───────────────────────────────────────────────────────────

    test('nestedList returns list of ToolArgs', () {
      final args = ToolArgs({
        'items': [
          {'id': 1, 'name': 'foo'},
          {'id': 2, 'name': 'bar'},
        ],
      });
      final items = args.nestedList('items');
      expect(items.length, 2);
      expect(items[0].integer('id'), 1);
      expect(items[1].string('name'), 'bar');
    });

    // ── optional ─────────────────────────────────────────────────────────────

    test('optional returns value when present', () {
      final args = ToolArgs({'unit': 'celsius'});
      expect(args.optional<String>('unit'), 'celsius');
    });

    test('optional returns null for missing key', () {
      expect(ToolArgs({}).optional<String>('unit'), isNull);
    });

    test('optional coerces num to int', () {
      final args = ToolArgs({'count': 7});
      expect(args.optional<int>('count'), 7);
    });

    // ── oneOf ────────────────────────────────────────────────────────────────

    test('oneOf returns value when in allowed list', () {
      final args = ToolArgs({'unit': 'fahrenheit'});
      expect(
        args.oneOf('unit', ['celsius', 'fahrenheit'], fallback: 'celsius'),
        'fahrenheit',
      );
    });

    test('oneOf returns fallback for value not in allowed list', () {
      final args = ToolArgs({'unit': 'kelvin'});
      expect(
        args.oneOf('unit', ['celsius', 'fahrenheit'], fallback: 'celsius'),
        'celsius',
      );
    });

    test('oneOf returns fallback for missing key', () {
      expect(
        ToolArgs({}).oneOf('unit', ['celsius', 'fahrenheit'], fallback: 'celsius'),
        'celsius',
      );
    });

    // ── has ──────────────────────────────────────────────────────────────────

    test('has returns true for present non-null key', () {
      expect(ToolArgs({'x': 1}).has('x'), isTrue);
    });

    test('has returns false for missing key', () {
      expect(ToolArgs({}).has('x'), isFalse);
    });

    test('has returns false for null value', () {
      expect(ToolArgs({'x': null}).has('x'), isFalse);
    });

    // ── keys / raw / subscript ────────────────────────────────────────────────

    test('keys returns set of all argument keys', () {
      final args = ToolArgs({'a': 1, 'b': 2});
      expect(args.keys, {'a', 'b'});
    });

    test('subscript operator returns raw value', () {
      final args = ToolArgs({'score': 99});
      expect(args['score'], 99);
    });

    test('raw returns unmodifiable map', () {
      final args = ToolArgs({'x': 1});
      expect(() => args.raw['x'] = 2, throwsUnsupportedError);
    });
  });
}
