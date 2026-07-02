import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('ModelRegistry', () {
    // ── Known models ─────────────────────────────────────────────────────────

    test('returns correct config for gemini-2.5-flash', () {
      final cfg = ModelRegistry.get('gemini-2.5-flash');
      expect(cfg.name, 'Gemini 2.5 Flash');
      expect(cfg.provider, ModelProvider.gemini);
      expect(cfg.contextWindow, 1048576);
      expect(cfg.inputCostPer1MTokens, 0.15);
      expect(cfg.supportsToolCalling, isTrue);
      expect(cfg.isLocal, isFalse);
    });

    test('returns correct config for gemini-2.5-flash-lite', () {
      final cfg = ModelRegistry.get('gemini-2.5-flash-lite');
      expect(cfg.name, 'Gemini 2.5 Flash Lite');
      expect(cfg.inputCostPer1MTokens, 0.10);
    });

    test('returns correct config for gpt-4o', () {
      final cfg = ModelRegistry.get('gpt-4o');
      expect(cfg.provider, ModelProvider.openai);
      expect(cfg.contextWindow, 128000);
      expect(cfg.supportsVision, isTrue);
    });

    test('returns correct config for claude-sonnet-4-5', () {
      final cfg = ModelRegistry.get('claude-sonnet-4-5');
      expect(cfg.provider, ModelProvider.anthropic);
      expect(cfg.contextWindow, 200000);
      expect(cfg.maxOutputTokens, 32000);
    });

    test('returns local flag for gemma model', () {
      final cfg = ModelRegistry.get('gemma-3n-e2b-it');
      expect(cfg.isLocal, isTrue);
      expect(cfg.provider, ModelProvider.gemma);
    });

    test('returns correct config for function-gemma-270m', () {
      final cfg = ModelRegistry.get('function-gemma-270m');
      expect(cfg.supportsToolCalling, isTrue);
      expect(cfg.isLocal, isTrue);
    });

    // ── Fallback ─────────────────────────────────────────────────────────────

    test('returns fallback for unknown model ID', () {
      final cfg = ModelRegistry.get('nonexistent-xyz-9000');
      expect(cfg.name, 'Unknown Model');
      expect(cfg.provider, ModelProvider.unknown);
    });

    test('fallback contextWindow is 8192', () {
      expect(ModelRegistry.get('nonexistent').contextWindow, 8192);
    });

    // ── Lookup helpers ───────────────────────────────────────────────────────

    test('has returns true for registered model', () {
      expect(ModelRegistry.has('gemini-2.0-flash'), isTrue);
    });

    test('has returns false for unknown model', () {
      expect(ModelRegistry.has('fake-model-123'), isFalse);
    });

    test('get is case-insensitive', () {
      final lower = ModelRegistry.get('gemini-2.0-flash');
      final upper = ModelRegistry.get('GEMINI-2.0-FLASH');
      expect(lower.name, upper.name);
    });

    // ── Collection helpers ───────────────────────────────────────────────────

    test('allIds is non-empty', () {
      expect(ModelRegistry.allIds, isNotEmpty);
    });

    test('localModelIds contains only local models', () {
      for (final id in ModelRegistry.localModelIds) {
        expect(ModelRegistry.get(id).isLocal, isTrue,
            reason: '$id should be local');
      }
    });

    test('cloudModelIds contains only cloud models', () {
      for (final id in ModelRegistry.cloudModelIds) {
        expect(ModelRegistry.get(id).isLocal, isFalse,
            reason: '$id should be cloud');
      }
    });

    test('modelsFor returns only gemini models', () {
      final ids = ModelRegistry.modelsFor(ModelProvider.gemini);
      expect(ids, isNotEmpty);
      for (final id in ids) {
        expect(ModelRegistry.get(id).provider, ModelProvider.gemini,
            reason: '$id should be gemini');
      }
    });

    test('localModelIds and cloudModelIds are disjoint', () {
      final local = ModelRegistry.localModelIds.toSet();
      final cloud = ModelRegistry.cloudModelIds.toSet();
      expect(local.intersection(cloud), isEmpty);
    });

    test('allIds includes both local and cloud models', () {
      final all = ModelRegistry.allIds.toSet();
      expect(all.containsAll(ModelRegistry.localModelIds), isTrue);
      expect(all.containsAll(ModelRegistry.cloudModelIds), isTrue);
    });
  });
}
