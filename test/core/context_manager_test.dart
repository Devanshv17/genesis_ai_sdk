import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

List<Message> makeMessages(int count) => List.generate(
      count,
      (i) => i.isEven ? Message.user('user $i') : Message.assistant('reply $i'),
    );

void main() {
  group('ContextManager', () {
    // ── maxMessages ──────────────────────────────────────────────────────────

    test('fit trims to maxMessages when history exceeds limit', () {
      final mgr = ContextManager(maxMessages: 4);
      expect(mgr.fit(makeMessages(10)).length, 4);
    });

    test('fit keeps ALL messages when under maxMessages', () {
      final mgr = ContextManager(maxMessages: 20);
      expect(mgr.fit(makeMessages(5)).length, 5);
    });

    test('fit with empty list returns empty list', () {
      final mgr = ContextManager(maxMessages: 10);
      expect(mgr.fit([]), isEmpty);
    });

    test('fit preserves newest messages when trimming', () {
      final mgr = ContextManager(maxMessages: 2);
      final history = [
        Message.user('old'),
        Message.assistant('also old'),
        Message.user('new'),
        Message.assistant('newest'),
      ];
      final fitted = mgr.fit(history);
      expect(fitted.length, 2);
      expect(fitted[0].content, 'new');
      expect(fitted[1].content, 'newest');
    });

    // ── system message preservation ──────────────────────────────────────────

    test('fit always keeps system message even when trimming', () {
      final mgr = ContextManager(maxMessages: 2);
      final history = [
        Message.system('You are helpful.'),
        ...List.generate(6, (i) => Message.user('msg $i')),
      ];
      final fitted = mgr.fit(history);
      // System + 2 most-recent user messages
      expect(fitted.first.role, MessageRole.system);
      expect(fitted.first.content, 'You are helpful.');
      expect(fitted.length, 3);
    });

    // ── maxTokens ────────────────────────────────────────────────────────────

    test('fit keeps all messages within generous token budget', () {
      // 4 chars ≈ 1 token; "user X" / "reply X" ~ 6 chars = ~2 tokens each
      final mgr = ContextManager(maxTokens: 100);
      expect(mgr.fit(makeMessages(4)).length, 4);
    });

    test('fit drops messages that exceed token budget', () {
      // Each message is ~400 chars = ~100 tokens. Budget = 100 → only 1 fits.
      final longHistory = List.generate(5, (i) => Message.user('x' * 400));
      final mgr = ContextManager(maxTokens: 100);
      expect(mgr.fit(longHistory).length, lessThanOrEqualTo(1));
    });

    test('approximateTokenCount returns non-zero for non-empty messages', () {
      final mgr = ContextManager(maxTokens: 10000);
      expect(mgr.approximateTokenCount(makeMessages(4)), greaterThan(0));
    });

    // ── static presets ───────────────────────────────────────────────────────

    test('ContextManager.small has maxTokens 3500 and maxMessages 20', () {
      final mgr = ContextManager.small;
      expect(mgr.maxTokens, 3500);
      expect(mgr.maxMessages, 20);
    });

    test('ContextManager.medium has maxTokens 7500', () {
      expect(ContextManager.medium.maxTokens, 7500);
    });

    test('ContextManager.large has maxTokens 30000', () {
      expect(ContextManager.large.maxTokens, 30000);
    });

    test('ContextManager.xlarge has maxTokens 120000', () {
      expect(ContextManager.xlarge.maxTokens, 120000);
    });

    // ── forModel ─────────────────────────────────────────────────────────────

    test('forModel returns small preset for tiny local model', () {
      expect(ContextManager.forModel('smollm-135m').maxTokens, 3500);
    });

    test('forModel returns medium preset for gemma-3n-e2b-it', () {
      expect(ContextManager.forModel('gemma-3n-e2b-it').maxTokens, 7500);
    });

    test('forModel returns xlarge preset for gemini-2.5-flash', () {
      expect(ContextManager.forModel('gemini-2.5-flash').maxTokens, 120000);
    });

    test('forModel returns xlarge for unknown model (fallback)', () {
      expect(ContextManager.forModel('totally-unknown-model').maxTokens, 120000);
    });

    test('forModel is case-insensitive', () {
      final a = ContextManager.forModel('Gemini-2.5-Flash');
      final b = ContextManager.forModel('gemini-2.5-flash');
      expect(a.maxTokens, b.maxTokens);
    });

    // ── assert ───────────────────────────────────────────────────────────────

    test('ContextManager requires at least one limit', () {
      expect(
        () => ContextManager(),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
