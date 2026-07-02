import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('OutputGuard', () {
    final guard = OutputGuard.withPiiRedaction();

    // ── PiiRedactionRule ─────────────────────────────────────────────────────

    test('redacts email address', () {
      final out = guard.process('Contact us at john.doe@example.com for help.');
      expect(out.contains('@'), isFalse,
          reason: 'email should be redacted');
      expect(out.contains('[REDACTED]'), isTrue);
    });

    test('redacts US phone number', () {
      final out = guard.process('Call me at 555-867-5309 anytime.');
      expect(out.contains('867-5309'), isFalse);
    });

    test('redacts SSN', () {
      final out = guard.process('My SSN is 123-45-6789.');
      expect(out.contains('123-45-6789'), isFalse);
    });

    test('redacts multiple PII in one string', () {
      const raw = 'Email: jane@test.org, Phone: 555-867-5309, SSN: 123-45-6789.';
      final out = guard.process(raw);
      expect(out.contains('@'), isFalse);
      expect(out.contains('867-5309'), isFalse);
      expect(out.contains('123-45-6789'), isFalse);
    });

    test('non-PII text passes through unchanged', () {
      const raw = 'The sky is blue and the grass is green.';
      expect(guard.process(raw), raw);
    });

    test('custom placeholder is used', () {
      final custom = OutputGuard(extraRules: [
        const PiiRedactionRule(placeholder: '***'),
      ]);
      final out = custom.process('Email me at foo@bar.com');
      expect(out.contains('***'), isTrue);
    });

    // ── TruncateOutputRule ───────────────────────────────────────────────────

    test('short text is not truncated', () {
      final g = OutputGuard();
      const text = 'Short response.';
      expect(g.process(text), text);
    });

    test('text over limit is truncated with suffix', () {
      final g = OutputGuard(extraRules: [
        const TruncateOutputRule(maxChars: 10, suffix: '…'),
      ]);
      final out = g.process('123456789012345');
      expect(out.length, lessThanOrEqualTo(11)); // 10 + 1 for '…'
      expect(out.endsWith('…'), isTrue);
    });

    // ── BlocklistOutputRule ──────────────────────────────────────────────────

    test('throws OutputGuardException when blocked word present', () {
      final g = OutputGuard(extraRules: [
        BlocklistOutputRule(blocklist: ['forbidden', 'banned']),
      ]);
      expect(
        () => g.process('This contains a forbidden word.'),
        throwsA(isA<OutputGuardException>()),
      );
    });

    test('blocklist check is case-insensitive by default', () {
      final g = OutputGuard(extraRules: [
        BlocklistOutputRule(blocklist: ['forbidden']),
      ]);
      expect(
        () => g.process('FORBIDDEN word here'),
        throwsA(isA<OutputGuardException>()),
      );
    });

    test('blocklist allows text without blocked words', () {
      final g = OutputGuard(extraRules: [
        BlocklistOutputRule(blocklist: ['forbidden']),
      ]);
      expect(() => g.process('Totally fine text.'), returnsNormally);
    });

    test('case-sensitive blocklist does not block differently cased word', () {
      final g = OutputGuard(extraRules: [
        BlocklistOutputRule(blocklist: ['forbidden'], caseSensitive: true),
      ]);
      // "FORBIDDEN" ≠ "forbidden" in case-sensitive mode → no throw
      expect(() => g.process('FORBIDDEN is fine here'), returnsNormally);
    });

    // ── OutputGuardException ─────────────────────────────────────────────────

    test('exception carries a reason and toString is descriptive', () {
      final g = OutputGuard(extraRules: [
        BlocklistOutputRule(blocklist: ['bad']),
      ]);
      try {
        g.process('bad word');
      } on OutputGuardException catch (e) {
        expect(e.reason, isNotEmpty);
        expect(e.toString(), contains('OutputGuardException'));
      }
    });
  });
}
