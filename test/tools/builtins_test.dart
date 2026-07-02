import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agentic/flutter_agentic.dart';
import 'package:flutter_agentic/src/tools/builtins/calculator_tool.dart';
import 'package:flutter_agentic/src/tools/builtins/datetime_tool.dart';

void main() {
  group('Calculator tool (calculate)', () {
    Future<Map<String, dynamic>> calc(String expr) =>
        calculatorTool.execute({'expression': expr});

    test('tool name is "calculate"', () {
      expect(calculatorTool.name, 'calculate');
    });

    test('addition', () async {
      final r = await calc('2 + 3');
      expect(r['result'], '5');
    });

    test('subtraction', () async {
      final r = await calc('10 - 4');
      expect(r['result'], '6');
    });

    test('multiplication', () async {
      final r = await calc('1337 * 42');
      expect(r['result'], '56154');
    });

    test('division', () async {
      final r = await calc('10 / 4');
      expect(double.parse(r['result'] as String), closeTo(2.5, 0.001));
    });

    test('power operator', () async {
      final r = await calc('2^10');
      expect(r['result'], '1024');
    });

    test('modulo operator', () async {
      final r = await calc('17 % 5');
      expect(r['result'], '2');
    });

    test('sqrt function', () async {
      final r = await calc('sqrt(225)');
      expect(r['result'], '15');
    });

    test('abs function', () async {
      final r = await calc('abs(-42)');
      expect(r['result'], '42');
    });

    test('parentheses respected', () async {
      final r = await calc('(2 + 3) * 4');
      expect(r['result'], '20');
    });

    test('pi constant', () async {
      final r = await calc('pi');
      expect(double.parse(r['result'] as String), closeTo(3.14159, 0.0001));
    });

    test('nested sqrt and multiplication', () async {
      final r = await calc('sqrt(9) * sqrt(16)');
      expect(r['result'], '12');
    });

    test('invalid expression returns error key', () async {
      final r = await calc('abc_unknown_fn(1)');
      expect(r.containsKey('error'), isTrue);
    });

    test('result includes original expression', () async {
      final r = await calc('3 + 3');
      expect(r['expression'], '3 + 3');
    });
  });

  group('DateTime tool (get_datetime)', () {
    Future<Map<String, dynamic>> dt([double? offset]) =>
        dateTimeTool.execute(offset != null ? {'timezone_offset_hours': offset} : {});

    test('tool name is "get_datetime"', () {
      expect(dateTimeTool.name, 'get_datetime');
    });

    test('returns date key in YYYY-MM-DD format', () async {
      final r = await dt();
      final date = r['date'] as String;
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date), isTrue,
          reason: 'date should be YYYY-MM-DD, got $date');
    });

    test('returns time key in HH:MM:SS format', () async {
      final r = await dt();
      final time = r['time'] as String;
      expect(RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(time), isTrue,
          reason: 'time should be HH:MM:SS, got $time');
    });

    test('returns day_of_week as a named day', () async {
      final r = await dt();
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday',
                    'Friday', 'Saturday', 'Sunday'];
      expect(days.contains(r['day_of_week']), isTrue);
    });

    test('returns unix_timestamp as positive integer', () async {
      final r = await dt();
      expect(r['unix_timestamp'], isA<int>());
      expect(r['unix_timestamp'] as int, greaterThan(0));
    });

    test('returns iso8601 string', () async {
      final r = await dt();
      expect(() => DateTime.parse(r['iso8601'] as String), returnsNormally);
    });

    test('without offset returns "local" timezone label', () async {
      final r = await dt();
      expect(r['timezone'], 'local');
    });

    test('with UTC+0 offset timezone label is UTC+00:00', () async {
      final r = await dt(0);
      expect(r['timezone'], 'UTC+00:00');
    });

    test('with positive offset timezone label formatted correctly', () async {
      final r = await dt(5.5); // IST
      expect(r['timezone'], 'UTC+05:30');
    });

    test('with negative offset timezone label formatted correctly', () async {
      final r = await dt(-5); // EST
      expect(r['timezone'], 'UTC-05:00');
    });
  });

  group('AgenticTools', () {
    test('AgenticTools.all is non-empty', () {
      expect(AgenticTools.all, isNotEmpty);
    });

    test('AgenticTools.all includes calculator', () {
      expect(
        AgenticTools.all.any((t) => t.name == 'calculate'),
        isTrue,
      );
    });

    test('AgenticTools.all includes get_datetime', () {
      expect(
        AgenticTools.all.any((t) => t.name == 'get_datetime'),
        isTrue,
      );
    });

    test('AgenticTools.all includes http_request', () {
      expect(
        AgenticTools.all.any((t) => t.name == 'http_request'),
        isTrue,
      );
    });

    test('all tool names are unique', () {
      final names = AgenticTools.all.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
    });
  });
}
