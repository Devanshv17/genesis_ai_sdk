import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('Message', () {
    test('Message.user sets role and content', () {
      final m = Message.user('hello');
      expect(m.role, MessageRole.user);
      expect(m.content, 'hello');
      expect(m.toolName, isNull);
    });

    test('Message.assistant sets role and content', () {
      final m = Message.assistant('hi there');
      expect(m.role, MessageRole.assistant);
      expect(m.content, 'hi there');
    });

    test('Message.system sets role and content', () {
      final m = Message.system('You are helpful.');
      expect(m.role, MessageRole.system);
      expect(m.content, 'You are helpful.');
    });

    test('Message.tool sets role, toolName, and content', () {
      final m = Message.tool('calculate', '{"result": "42"}');
      expect(m.role, MessageRole.tool);
      expect(m.toolName, 'calculate');
      expect(m.content, '{"result": "42"}');
    });

    test('toString includes role prefix', () {
      final m = Message.user('test message');
      expect(m.toString(), '[user] test message');
    });

    test('Message roles cover all four values', () {
      expect(MessageRole.values.length, 4);
      expect(MessageRole.values, containsAll([
        MessageRole.system,
        MessageRole.user,
        MessageRole.assistant,
        MessageRole.tool,
      ]));
    });
  });
}
