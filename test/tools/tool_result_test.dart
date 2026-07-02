import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('ToolResult', () {
    // ── ToolSuccess ──────────────────────────────────────────────────────────

    test('ToolSuccess.isSuccess is true', () {
      final r = ToolSuccess({'result': 42});
      expect(r.isSuccess, isTrue);
      expect(r.isError, isFalse);
    });

    test('ToolSuccess.toMap returns the data map', () {
      final data = {'value': 'hello', 'count': 3};
      final r = ToolSuccess(data);
      expect(r.toMap(), data);
    });

    test('ToolSuccess.toMap with empty data returns empty map', () {
      expect(ToolSuccess({}).toMap(), isEmpty);
    });

    // ── ToolError ────────────────────────────────────────────────────────────

    test('ToolError.isError is true', () {
      final r = ToolError('something failed');
      expect(r.isError, isTrue);
      expect(r.isSuccess, isFalse);
    });

    test('ToolError.toMap contains error message', () {
      final r = ToolError('DB connection failed');
      expect(r.toMap()['error'], 'DB connection failed');
    });

    test('ToolError.toMap includes error_code when provided', () {
      final r = ToolError('Not found', code: 'NOT_FOUND');
      final map = r.toMap();
      expect(map['error'], 'Not found');
      expect(map['error_code'], 'NOT_FOUND');
    });

    test('ToolError.toMap omits error_code when not provided', () {
      final r = ToolError('Oops');
      expect(r.toMap().containsKey('error_code'), isFalse);
    });

    test('ToolError stores cause object', () {
      final ex = Exception('root cause');
      final r = ToolError('wrapped', cause: ex);
      expect(r.cause, ex);
    });

    // ── sealed class exhaustiveness ──────────────────────────────────────────

    test('ToolResult is either ToolSuccess or ToolError', () {
      final results = <ToolResult>[
        ToolSuccess({'x': 1}),
        ToolError('fail'),
      ];
      for (final r in results) {
        expect(r.isSuccess || r.isError, isTrue);
      }
    });
  });
}
