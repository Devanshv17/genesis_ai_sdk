import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

/// Fake provider that records calls and returns a fixed reply.
class _FakeProvider extends LlmProvider {
  @override
  final String name;
  final bool shouldFail;
  int completeCalls = 0;
  int streamCalls = 0;

  _FakeProvider(this.name, {this.shouldFail = false});

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    completeCalls++;
    if (shouldFail) throw Exception('$name is down');
    return TextResult('reply-from-$name');
  }

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    streamCalls++;
    if (shouldFail) throw Exception('$name is down');
    yield 'token-from-$name';
  }
}

void main() {
  group('RouteContext', () {
    test('latestUserMessage returns newest user message', () {
      final ctx = RouteContext(messages: [
        Message.system('sys'),
        Message.user('first'),
        Message.assistant('hi'),
        Message.user('second'),
      ]);
      expect(ctx.latestUserMessage, 'second');
    });

    test('latestUserMessage is empty with no user messages', () {
      final ctx = RouteContext(messages: [Message.system('sys')]);
      expect(ctx.latestUserMessage, '');
    });

    test('totalLength sums all message content', () {
      final ctx = RouteContext(messages: [
        Message.user('abc'),
        Message.assistant('de'),
      ]);
      expect(ctx.totalLength, 5);
    });
  });

  group('RouteRules', () {
    test('sensitive matches keywords case-insensitively', () {
      final rule = RouteRules.sensitive(useProvider: 'local');
      final hit = RouteContext(messages: [Message.user('My PASSWORD is x')]);
      final miss = RouteContext(messages: [Message.user('hello world')]);
      expect(rule.when(hit), isTrue);
      expect(rule.when(miss), isFalse);
    });

    test('shortInput matches by latest message length', () {
      final rule = RouteRules.shortInput(useProvider: 'local', maxChars: 5);
      expect(
          rule.when(RouteContext(messages: [Message.user('hi')])), isTrue);
      expect(
          rule.when(
              RouteContext(messages: [Message.user('a much longer prompt')])),
          isFalse);
    });

    test('needsTools matches only when tools present', () {
      final rule = RouteRules.needsTools(useProvider: 'cloud');
      final tool = AgenticTool.define(
        name: 't',
        description: 'd',
        params: {},
        execute: (_) async => {},
      );
      expect(
          rule.when(RouteContext(
              messages: [Message.user('x')], tools: [tool])),
          isTrue);
      expect(rule.when(RouteContext(messages: [Message.user('x')])), isFalse);
    });

    test('streaming matches only streaming calls', () {
      final rule = RouteRules.streaming(useProvider: 'local');
      expect(
          rule.when(RouteContext(
              messages: [Message.user('x')], isStreaming: true)),
          isTrue);
      expect(rule.when(RouteContext(messages: [Message.user('x')])), isFalse);
    });
  });

  group('PolicyRouter', () {
    test('throws when defaultProvider is unknown', () {
      expect(
        () => PolicyRouter(
          providers: {'a': _FakeProvider('a')},
          defaultProvider: 'missing',
        ),
        throwsArgumentError,
      );
    });

    test('throws when a rule routes to unknown provider', () {
      expect(
        () => PolicyRouter(
          providers: {'a': _FakeProvider('a')},
          defaultProvider: 'a',
          rules: [RouteRules.needsTools(useProvider: 'nope')],
        ),
        throwsArgumentError,
      );
    });

    test('first matching rule wins', () async {
      final local = _FakeProvider('local');
      final cloud = _FakeProvider('cloud');
      final router = PolicyRouter(
        providers: {'local': local, 'cloud': cloud},
        defaultProvider: 'cloud',
        rules: [
          RouteRules.shortInput(useProvider: 'local', maxChars: 100),
          RouteRules.sensitive(useProvider: 'cloud'),
        ],
      );

      final result = await router.complete(messages: [Message.user('hi')]);
      expect((result as TextResult).text, 'reply-from-local');
      expect(local.completeCalls, 1);
      expect(cloud.completeCalls, 0);
    });

    test('falls through to default when no rule matches', () async {
      final local = _FakeProvider('local');
      final cloud = _FakeProvider('cloud');
      final router = PolicyRouter(
        providers: {'local': local, 'cloud': cloud},
        defaultProvider: 'cloud',
        rules: [RouteRules.needsTools(useProvider: 'local')],
      );

      final result = await router.complete(messages: [Message.user('hello')]);
      expect((result as TextResult).text, 'reply-from-cloud');
    });

    test('onRoute reports the decision with matched rule', () async {
      final decisions = <RouteDecision>[];
      final router = PolicyRouter(
        providers: {
          'local': _FakeProvider('local'),
          'cloud': _FakeProvider('cloud'),
        },
        defaultProvider: 'cloud',
        rules: [RouteRules.shortInput(useProvider: 'local', maxChars: 100)],
        onRoute: decisions.add,
      );

      await router.complete(messages: [Message.user('hi')]);
      expect(decisions, hasLength(1));
      expect(decisions.first.providerKey, 'local');
      expect(decisions.first.matchedRule, isNotNull);
    });

    test('falls back to default when routed provider fails', () async {
      final local = _FakeProvider('local', shouldFail: true);
      final cloud = _FakeProvider('cloud');
      final router = PolicyRouter(
        providers: {'local': local, 'cloud': cloud},
        defaultProvider: 'cloud',
        rules: [RouteRules.shortInput(useProvider: 'local', maxChars: 100)],
      );

      final result = await router.complete(messages: [Message.user('hi')]);
      expect((result as TextResult).text, 'reply-from-cloud');
    });

    test('rethrows when fallbackToDefault is false', () async {
      final router = PolicyRouter(
        providers: {
          'local': _FakeProvider('local', shouldFail: true),
          'cloud': _FakeProvider('cloud'),
        },
        defaultProvider: 'cloud',
        rules: [RouteRules.shortInput(useProvider: 'local', maxChars: 100)],
        fallbackToDefault: false,
      );

      expect(
        () => router.complete(messages: [Message.user('hi')]),
        throwsException,
      );
    });

    test('routes streams per-call with fallback', () async {
      final local = _FakeProvider('local', shouldFail: true);
      final cloud = _FakeProvider('cloud');
      final router = PolicyRouter(
        providers: {'local': local, 'cloud': cloud},
        defaultProvider: 'cloud',
        rules: [RouteRules.streaming(useProvider: 'local')],
      );

      final tokens =
          await router.stream(messages: [Message.user('hi')]).toList();
      expect(tokens, ['token-from-cloud']);
    });

    test('decide() previews routing without calling providers', () {
      final local = _FakeProvider('local');
      final router = PolicyRouter(
        providers: {'local': local, 'cloud': _FakeProvider('cloud')},
        defaultProvider: 'cloud',
        rules: [RouteRules.sensitive(useProvider: 'local')],
      );

      final decision = router.decide(RouteContext(
          messages: [Message.user('what is my bank balance')]));
      expect(decision.providerKey, 'local');
      expect(local.completeCalls, 0);
    });
  });
}
