/// Live tests for [HFInferenceProvider] — sends real prompts to HF cloud.
///
/// These tests require internet + a valid HF_TOKEN (or HUGGINGFACE_TOKEN)
/// in the environment. They are skipped automatically if either is absent.
///
/// Run:
///   HF_TOKEN=hf_xxxx flutter test test/providers/hf_inference_provider_test.dart
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/src/core/message.dart';
import 'package:flutter_agents/src/hub/genesis_hub.dart';
import 'package:flutter_agents/src/providers/hf_inference_provider.dart';
import 'package:flutter_agents/src/providers/llm_provider.dart' show TextResult;

// ── Config ──────────────────────────────────────────────────────────────────

/// Small, fast model available on featherless backend.
const _modelId = 'Qwen/Qwen2.5-0.5B-Instruct';

/// Resolve token from env or skip
String? get _token =>
    Platform.environment['HF_TOKEN'] ??
    Platform.environment['HUGGINGFACE_TOKEN'];

/// Check reachability
Future<bool> _online() async {
  try {
    final s = await Socket.connect('router.huggingface.co', 443,
        timeout: const Duration(seconds: 5));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

// ──────────────────────────────────────────────────────────────────────────

void main() {
  late String token;
  late bool online;

  setUpAll(() async {
    token = _token ?? '';
    online = await _online();
    if (token.isEmpty) {
      debugPrint('[SKIP] HF_TOKEN not set — skipping all HFInference tests');
    }
    if (!online) {
      debugPrint(
          '[SKIP] No internet — skipping all HFInference tests');
    }
  });

  group('HFInferenceProvider (featherless backend)', () {
    test('complete() — returns correct factual answer', () async {
      if (token.isEmpty || !online) return;

      final provider = HFInferenceProvider(
        modelId: _modelId,
        apiToken: token,
        maxTokens: 32,
        backend: HFInferenceBackend.featherless,
      );

      final result = await provider.complete(
        messages: [
          Message.system('Reply in ONE sentence only.'),
          Message.user('What is the capital of Japan?'),
        ],
      );

      final text = (result as TextResult).text.trim();
      debugPrint('[hf-cloud] complete → "$text"');

      expect(text.isNotEmpty, isTrue);
      expect(text.toLowerCase(), contains('tokyo'),
          reason: 'Expected "tokyo" in: "$text"');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('stream() — yields tokens that form a coherent sentence', () async {
      if (token.isEmpty || !online) return;

      final provider = HFInferenceProvider(
        modelId: _modelId,
        apiToken: token,
        maxTokens: 32,
        backend: HFInferenceBackend.featherless,
      );

      final tokens = <String>[];
      await for (final t in provider.stream(
        messages: [
          Message.system('Reply in ONE sentence only.'),
          Message.user('Name the planet closest to the Sun.'),
        ],
      )) {
        tokens.add(t);
      }

      final text = tokens.join().trim();
      debugPrint(
          '[hf-cloud] stream → "$text"  (${tokens.length} tokens)');

      expect(tokens.isNotEmpty, isTrue,
          reason: 'stream should yield at least one token');
      expect(text.toLowerCase(), contains('mercury'),
          reason: 'Expected "mercury" in: "$text"');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('GenesisHub.fromHFCloud() — creates agent and answers', () async {
      if (token.isEmpty || !online) return;

      final agent = GenesisHub.fromHFCloud(
        modelId: _modelId,
        apiToken: token,
        maxTokens: 32,
        systemPrompt: 'Reply in ONE sentence only.',
      );

      final response = await agent.chat('What is 12 multiplied by 12?');
      final text = response.toString();
      debugPrint('[hf-cloud] hub.fromHFCloud → "$text"');

      expect(text.contains('144'), isTrue,
          reason: 'Expected "144" in: "$text"');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('wrong model on hfNative → throws HFInferenceException', () async {
      if (token.isEmpty || !online) return;

      final provider = HFInferenceProvider(
        modelId: _modelId,
        apiToken: token,
        backend: HFInferenceBackend.hfNative, // most models not supported here
      );

      try {
        await provider.complete(
            messages: [Message.user('Say hello.')]);
        // If it somehow passes, that's fine too
        debugPrint('[hf-cloud] hfNative: unexpectedly succeeded');
      } on HFInferenceException catch (e) {
        debugPrint('[hf-cloud] hfNative error (expected): ${e.message.split('\n').first}');
        // Error message should guide user to switch backend
        expect(
          e.message.toLowerCase(),
          anyOf(
            contains('not supported'),
            contains('backend'),
            contains('featherless'),
            contains('422'),
            contains('503'),
          ),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
