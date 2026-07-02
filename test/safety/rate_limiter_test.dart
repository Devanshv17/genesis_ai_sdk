import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('RateLimiter', () {
    test('allows requests up to the limit', () {
      final lim = RateLimiter(
          maxRequests: 3,
          windowDuration: const Duration(minutes: 1));
      expect(() {
        lim.check('u');
        lim.check('u');
        lim.check('u');
      }, returnsNormally);
    });

    test('blocks the request that exceeds the limit', () {
      final lim = RateLimiter(
          maxRequests: 3,
          windowDuration: const Duration(minutes: 1));
      lim.check('u');
      lim.check('u');
      lim.check('u');
      expect(
        () => lim.check('u'),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('exception message contains key and limit info', () {
      final lim = RateLimiter(
          maxRequests: 1,
          windowDuration: const Duration(minutes: 1));
      lim.check('user_42');
      try {
        lim.check('user_42');
      } on RateLimitException catch (e) {
        expect(e.reason, contains('user_42'));
        expect(e.toString(), contains('RateLimitException'));
      }
    });

    test('different keys have independent counters', () {
      final lim = RateLimiter(
          maxRequests: 1,
          windowDuration: const Duration(minutes: 1));
      lim.check('alice');
      // Bob hasn't used his slot yet — should not throw
      expect(() => lim.check('bob'), returnsNormally);
    });

    test('usage returns current count for key', () {
      final lim = RateLimiter(
          maxRequests: 5,
          windowDuration: const Duration(minutes: 1));
      lim.check('u');
      lim.check('u');
      expect(lim.usage('u'), 2);
    });

    test('usage returns 0 for key with no history', () {
      final lim = RateLimiter(
          maxRequests: 5,
          windowDuration: const Duration(minutes: 1));
      expect(lim.usage('unknown'), 0);
    });

    test('reset clears all counters', () {
      final lim = RateLimiter(
          maxRequests: 2,
          windowDuration: const Duration(minutes: 1));
      lim.check('u');
      lim.check('u');
      lim.reset();
      // After reset, counter is back to 0 — should not throw on next check
      expect(() => lim.check('u'), returnsNormally);
      expect(lim.usage('u'), 1);
    });

    test('window expiry resets counter', () async {
      final lim = RateLimiter(
          maxRequests: 1,
          windowDuration: const Duration(milliseconds: 50));
      lim.check('u'); // uses the 1 slot
      await Future<void>.delayed(const Duration(milliseconds: 60));
      // Window should have expired — this call opens a new window
      expect(() => lim.check('u'), returnsNormally);
    });
  });

  group('ConcurrencyLimiter', () {
    test('allows call when under limit', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 2);
      final result = await lim.run<String>('u', () async => 'ok');
      expect(result, 'ok');
    });

    test('blocks when max concurrent is reached', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 1);
      // Start a slow call that won't finish yet
      final slow = lim.run<String>('u', () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'slow';
      });
      // Immediately try a second call — should be rejected
      expect(
        () => lim.run<String>('u', () async => 'fast'),
        throwsA(isA<RateLimitException>()),
      );
      await slow; // clean up
    });

    test('slot is released after call completes', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 1);
      await lim.run<void>('u', () async {});
      // Slot released — next call should succeed
      expect(
        () => lim.run<String>('u', () async => 'ok'),
        returnsNormally,
      );
    });

    test('slot is released even when call throws', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 1);
      try {
        await lim.run<void>('u', () async => throw Exception('boom'));
      } catch (_) {}
      // Slot should be released after the throw
      expect(
        () => lim.run<String>('u', () async => 'ok'),
        returnsNormally,
      );
    });

    test('different keys have independent concurrency', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 1);
      final slow = lim.run<String>('alice', () async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'done';
      });
      // bob has a separate slot — should not be blocked
      expect(
        () => lim.run<String>('bob', () async => 'ok'),
        returnsNormally,
      );
      await slow;
    });

    test('exception message contains key and limit', () async {
      final lim = ConcurrencyLimiter(maxConcurrent: 1);
      final slow = lim.run<void>('u', () async =>
          Future<void>.delayed(const Duration(milliseconds: 200)));
      try {
        await lim.run<void>('u', () async {});
      } on RateLimitException catch (e) {
        expect(e.reason, contains('"u"'));
        expect(e.reason, contains('1'));
      }
      await slow;
    });
  });
}
