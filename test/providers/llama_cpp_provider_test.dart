/// Unit / on-device test for [LlamaCppProvider] using the real GGUF model.
///
/// Run with:
///   cd packages/genesis_ai
///   flutter test test/providers/llama_cpp_provider_test.dart
///
/// This test runs as a host-side Dart process (no macOS app sandbox), so
/// [Llama.libraryPath] works fine pointing to the pub-cache prebuilt dylibs.
///
/// The test is skipped automatically when:
///   • The GGUF model file is not on disk (first run / CI without artifacts)
///   • The prebuilt dylib is not present
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart' show Llama;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_agents/src/core/message.dart';
import 'package:flutter_agents/src/providers/llama_cpp_provider.dart';
import 'package:flutter_agents/src/providers/llm_provider.dart' show TextResult;
import 'package:flutter_agents/src/hub/genesis_hub.dart';

// ── Paths ──────────────────────────────────────────────────────────────────

const _ggufPath =
    '/Users/devansh/Harddisk/17012026/Downloads/Llama-3.2-1B-Instruct.IQ1_M.gguf';

const _llamaLibPath =
    '/Users/devansh/.pub-cache/hosted/pub.dev/llama_cpp_dart-0.2.2/bin/MAC_ARM64/libmtmd.dylib';

// ──────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Point llama_cpp_dart at the prebuilt macOS ARM64 dylib.
    // In a non-sandboxed flutter test process this path is accessible.
    if (File(_llamaLibPath).existsSync()) {
      Llama.libraryPath = _llamaLibPath;
    }
  });

  // ── LlamaCppProvider complete() ──────────────────────────────────────────
  group('LlamaCppProvider (.gguf)', () {
    test('complete() — produces non-empty text', () async {
      if (!File(_ggufPath).existsSync()) {
        markTestSkipped('GGUF model not found: $_ggufPath');
        return;
      }
      if (!File(_llamaLibPath).existsSync()) {
        markTestSkipped('llama dylib not found: $_llamaLibPath');
        return;
      }

      final provider = LlamaCppProvider(
        modelPath: _ggufPath,
        chatFormat: LlamaChatFormat.chatml,
        nGpuLayers: 0,
        nCtx: 512,
        maxTokens: 64,
        temperature: 0.0,
      );

      final result = await provider.complete(
        messages: [
          Message.system('You are a concise assistant. Reply in ONE sentence.'),
          Message.user('What is 3 plus 4?'),
        ],
      );

      final text = (result as TextResult).text.trim();
      debugPrint('[gguf] complete → "$text"');

      expect(text.isNotEmpty, isTrue,
          reason: 'LlamaCppProvider should produce non-empty output');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('stream() — yields tokens', () async {
      if (!File(_ggufPath).existsSync()) {
        markTestSkipped('GGUF model not found: $_ggufPath');
        return;
      }
      if (!File(_llamaLibPath).existsSync()) {
        markTestSkipped('llama dylib not found: $_llamaLibPath');
        return;
      }

      final provider = LlamaCppProvider(
        modelPath: _ggufPath,
        chatFormat: LlamaChatFormat.chatml,
        nGpuLayers: 0,
        nCtx: 512,
        maxTokens: 32,
        temperature: 0.0,
      );

      final tokens = <String>[];
      await for (final t in provider.stream(
        messages: [Message.user('Say the word hello.')],
      )) {
        tokens.add(t);
        if (tokens.length >= 20) break;
      }

      final text = tokens.join().trim();
      debugPrint('[gguf] stream → "$text"  (${tokens.length} tokens)');
      expect(tokens, isNotEmpty, reason: 'stream should yield at least 1 token');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('GenesisHub.fromFile(.gguf) throws UnsupportedError', () {
      expect(
        () => GenesisHub.fromFile(modelPath: '/tmp/model.gguf'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
