/// On-device GGUF inference via [llama_cpp_dart] 0.2.x.
///
/// ## Setup
/// Add to your pubspec.yaml:
/// ```yaml
/// dependencies:
///   llama_cpp_dart: ^0.2.2
/// ```
///
/// ## Platform native library
///
/// | Platform | Native library | Setup |
/// |----------|---------------|-------|
/// | Android  | libmtmd.so (ships in AAR) | nothing — auto-loaded |
/// | macOS    | libmtmd.dylib (ships via CocoaPods) | nothing |
/// | iOS      | libmtmd.a (ships via CocoaPods) | nothing |
/// | Windows  | llama.dll | set [Llama.libraryPath] before first use |
/// | Linux    | libllama.so | set [Llama.libraryPath] before first use |
///
/// On Windows/Linux, download the prebuilt library from the llama_cpp_dart
/// GitHub releases and set the path in main() before any [LlamaCppProvider]
/// is used:
/// ```dart
/// import 'package:llama_cpp_dart/llama_cpp_dart.dart';
/// Llama.libraryPath = '/path/to/llama.dll';
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:llama_cpp_dart/llama_cpp_dart.dart' as lc;
import '../core/message.dart' as sdk;
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// On-device LLM provider for **GGUF** model files using
/// [llama_cpp_dart](https://pub.dev/packages/llama_cpp_dart) 0.2.x.
///
/// GGUF is the most widely available quantised format on HuggingFace.
/// Works on macOS, Windows, Linux, and Android.
///
/// > **iOS note**: `llama_cpp_dart` 0.2.x ships an iOS xcframework that must
/// > be built locally from source (see the package's `ios/` directory and
/// > `darwin/build.sh`). If you only target Android + desktop, GGUF works
/// > out of the box. For iOS on-device inference consider using a `.litertlm`
/// > model with [GemmaProvider] instead.
///
/// ## Quick start
/// ```dart
/// final provider = LlamaCppProvider(
///   modelPath: '/path/to/model.gguf',
///   chatFormat: LlamaChatFormat.chatml, // for Qwen / Yi / most modern models
/// );
///
/// final agent = AgenticAgent(provider: provider, systemPrompt: 'Be helpful.');
/// final response = await agent.chat('What is 2+2?');
/// ```
///
/// ## Native library — platform setup
///
/// | Platform | Setup required |
/// |----------|---------------|
/// | Android  | **None** — the `.so` is bundled in the plugin's AAR automatically |
/// | iOS      | **None** — linked via CocoaPods xcframework (must be built first) |
/// | macOS    | **None** for CocoaPods builds; set [Llama.libraryPath] only when running *outside* a bundled app (e.g. unit tests) |
/// | Windows  | Set `Llama.libraryPath = 'path/to/llama.dll'` before first use |
/// | Linux    | Set `Llama.libraryPath = 'path/to/libllama.so'` before first use |
///
/// ```dart
/// // macOS / Linux / Windows — only needed outside an app bundle:
/// import 'package:llama_cpp_dart/llama_cpp_dart.dart';
/// Llama.libraryPath = '/path/to/libmtmd.dylib';
/// ```
///
/// ## Choosing a chat format
/// Most modern community GGUF models use ChatML. Check the model card:
/// - `chatml` — Qwen, Yi, Mistral, most 2024+ models
/// - `gemma`  — Gemma family
/// - `alpaca` — older Alpaca-finetuned models
/// - `auto`   — defaults to chatml
///
/// ## GPU acceleration
/// Set [nGpuLayers] > 0 to offload transformer layers to Metal/Vulkan/CUDA:
/// ```dart
/// LlamaCppProvider(modelPath: '...', nGpuLayers: 99) // all layers on GPU
/// ```
class LlamaCppProvider extends LlmProvider {
  /// Absolute path to the `.gguf` model file.
  final String modelPath;

  /// Chat template format. Defaults to [LlamaChatFormat.chatml].
  final LlamaChatFormat chatFormat;

  /// Number of layers to offload to GPU/NPU.
  /// `0` = CPU only. `99` = all layers (use if VRAM allows).
  final int nGpuLayers;

  /// Context window in tokens. Default 2048; increase for long documents.
  final int nCtx;

  /// Maximum new tokens to generate per response.
  final int maxTokens;

  /// Sampling temperature (0 = deterministic, 1+ = creative).
  final double temperature;

  /// Optional display name for logging / SmartRouter.
  final String? displayName;

  LlamaCppProvider({
    required this.modelPath,
    this.chatFormat = LlamaChatFormat.chatml,
    this.nGpuLayers = 0,
    this.nCtx = 2048,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.displayName,
  });

  @override
  String get name => displayName ?? 'LlamaCpp(${_shortName(modelPath)})';

  // ── complete ──────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<sdk.Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    _assertNative();

    final (parent, prompt) = await _buildParentAndPrompt(messages, temperature);
    final buffer = StringBuffer();

    await parent.init();

    // Subscribe BEFORE sending the prompt to avoid missing early tokens.
    // parent.stream is a broadcast stream that never closes on its own;
    // we drive termination via waitForCompletion().
    final sub = parent.stream.listen((t) => buffer.write(t));
    try {
      final promptId = await parent.sendPrompt(prompt);
      await parent.waitForCompletion(promptId);
    } finally {
      await sub.cancel();
      await _safeDispose(parent);
    }

    return TextResult(buffer.toString().trim());
  }

  // ── stream ────────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<sdk.Message> messages,
    double temperature = 0.7,
  }) async* {
    _assertNative();

    final (parent, prompt) = await _buildParentAndPrompt(messages, temperature);

    await parent.init();

    // Bridge the broadcast stream (which never closes on its own) into a
    // single-subscriber StreamController so the async* generator can consume
    // it safely.  We close the bridge as soon as the generation is complete.
    final bridge = StreamController<String>();
    StreamSubscription<String>? sub;

    try {
      sub = parent.stream.listen(
        (t) {
          if (t.isNotEmpty && !bridge.isClosed) bridge.add(t);
        },
      );

      final promptId = await parent.sendPrompt(prompt);

      // Close the bridge when generation finishes so the await-for below ends.
      parent.waitForCompletion(promptId).then(
        (_) { if (!bridge.isClosed) bridge.close(); },
        onError: (Object e) {
          if (!bridge.isClosed) { bridge.addError(e); bridge.close(); }
        },
      );

      await for (final token in bridge.stream) {
        yield token;
      }
    } finally {
      await sub?.cancel();
      await _safeDispose(parent);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<(lc.LlamaParent, String)> _buildParentAndPrompt(
    List<sdk.Message> messages,
    double temp,
  ) async {
    final modelParams = lc.ModelParams()..nGpuLayers = nGpuLayers;
    final contextParams = lc.ContextParams()
      ..nCtx = nCtx
      ..nPredict = maxTokens;
    final samplerParams = lc.SamplerParams()..temp = temp;

    final loadCmd = lc.LlamaLoad(
      path: modelPath,
      modelParams: modelParams,
      contextParams: contextParams,
      samplingParams: samplerParams,
    );

    final formatter = _formatFor(chatFormat);
    final parent = lc.LlamaParent(loadCmd, formatter);

    // Build chat history list for the formatter
    final history = messages.map((m) => {
          'role': switch (m.role) {
            sdk.MessageRole.system => 'system',
            sdk.MessageRole.user => 'user',
            sdk.MessageRole.assistant => 'assistant',
            sdk.MessageRole.tool => 'user', // treat tool result as user turn
          },
          'content': m.content,
        }).toList();

    // Render the full conversation into a single prompt string
    final prompt = formatter?.formatMessages(history) ??
        history.map((m) => '${m['role']}: ${m['content']}').join('\n');

    return (parent, prompt);
  }

  static lc.PromptFormat? _formatFor(LlamaChatFormat fmt) => switch (fmt) {
        LlamaChatFormat.chatml => lc.ChatMLFormat(),
        LlamaChatFormat.alpaca => lc.AlpacaFormat(),
        LlamaChatFormat.gemma => lc.GemmaFormat(),
        LlamaChatFormat.auto => lc.ChatMLFormat(),
      };

  static void _assertNative() {
    if (kIsWeb) {
      throw UnsupportedError(
        'LlamaCppProvider does not support web. '
        'Use GeminiProvider or OpenAIProvider for web builds.',
      );
    }
  }

  /// Stops any in-flight generation then disposes [parent].
  ///
  /// Calling [lc.LlamaParent.dispose] while the isolate is still emitting
  /// tokens closes the internal broadcast controller, causing the isolate
  /// message handler to throw "Cannot add new events after calling close".
  /// Stopping first lets the isolate acknowledge the stop before we close.
  static Future<void> _safeDispose(lc.LlamaParent parent) async {
    try {
      if (parent.isGenerating) await parent.stop();
    } catch (_) {
      // ignore: stop may time-out if already done
    }
    try {
      await parent.dispose();
    } catch (_) {
      // ignore: dispose errors are non-fatal
    }
  }

  static String _shortName(String path) {
    final n = path.replaceAll('\\', '/').split('/').last;
    return n.length > 40 ? '…${n.substring(n.length - 37)}' : n;
  }
}

/// Chat template format for [LlamaCppProvider].
enum LlamaChatFormat {
  /// ChatML — used by Qwen, Yi, Mistral, and most 2024+ models.
  chatml,

  /// Alpaca — older instruction-tuned models.
  alpaca,

  /// Gemma — Google Gemma family.
  gemma,

  /// Auto — defaults to ChatML.
  auto,
}

/// Thrown when llama.cpp encounters a generation error.
class LlamaCppException implements Exception {
  final String message;
  const LlamaCppException(this.message);
  @override
  String toString() => 'LlamaCppException: $message';
}
