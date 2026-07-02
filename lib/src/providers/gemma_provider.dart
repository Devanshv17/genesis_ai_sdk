import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_gemma/core/model.dart' as fg_model;
import 'package:flutter_gemma/flutter_gemma.dart' as fg;
import 'package:http/http.dart' as http;
import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// On-device LLM provider using [flutter_gemma](https://pub.dev/packages/flutter_gemma).
///
/// Runs models 100% locally — no internet after the first download, no API key.
/// Supports **Android, iOS, macOS, Windows, Linux**.
/// On web, throws [UnsupportedError] — use a cloud provider instead.
///
/// ## Supported models
/// | Model ID            | Size  | Desktop | Mobile | Tool call | Vision |
/// |---------------------|-------|:-------:|:------:|:---------:|:------:|
/// | qwen3-0.6b          | 400MB |   ✅    |   ✅   |    ❌     |   ❌   |
/// | qwen3-1.7b          | 1GB   |   ✅    |   ✅   |    ❌     |   ❌   |
/// | gemma-3-1b-it       | 500MB |   ✅    |   ✅   |    ❌     |   ❌   |
/// | gemma-3-270m-it     | 150MB |   ✅    |   ✅   |    ❌     |   ❌   |
/// | function-gemma-270m | 271MB |   ✅    |   ✅   |    ✅     |   ❌   |
/// | phi-4-mini          | 2.4GB |   ✅    |   ✅   |    ❌     |   ❌   |
/// | smollm-135m         | 90MB  |   ❌    |   ✅   |    ❌     |   ❌   |
/// | gemma-3n-e2b-it     | 1.1GB |   ❌    |   ✅   |    ✅     |   ✅   |
/// | gemma-3n-e4b-it     | 2.2GB |   ❌    |   ✅   |    ✅     |   ✅   |
///
/// Desktop = macOS / Windows / Linux; Mobile = Android / iOS.
///
/// ## Quick start
/// ```dart
/// // 1. Download the model (one-time)
/// await GemmaModelManager.download(
///   modelId: 'qwen3-0.6b',
///   destinationPath: '/path/to/models/qwen3.litertlm',
///   onProgress: (r, t) => print('${r ~/ 1e6}/${t ~/ 1e6} MB'),
/// );
///
/// // 2. Initialize (once at app startup)
/// await FlutterGemma.initialize();
///
/// // 3. Create the provider
/// final provider = GemmaProvider(
///   modelId: 'qwen3-0.6b',
///   modelPath: '/path/to/models/qwen3.litertlm',
/// );
/// ```
///
/// See `PLATFORM_SETUP.md` for macOS Podfile hooks, iOS entitlements,
/// Android manifest, and Windows setup.
///
/// Use [GemmaModelManager] to download models, check presence, and delete them.
class GemmaProvider extends LlmProvider {
  /// One of the supported model IDs listed in the doc above.
  final String modelId;

  /// Absolute path to the downloaded `.task` or `.litertlm` model file.
  final String modelPath;

  /// Enable image input. Only works with gemma-3n models.
  final bool supportImage;

  GemmaProvider({
    required this.modelId,
    required this.modelPath,
    this.supportImage = false,
  });

  @override
  String get name => 'Gemma ($modelId)';

  // ── complete ────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    _assertSupported();

    final (chat, model) = await _createChat(tools);
    try {
      for (final msg in messages) {
        await _addMessage(chat, msg);
      }

      String fullText = '';
      fg.FunctionCallResponse? toolCall;

      await for (final token in chat.generateChatResponseAsync()) {
        if (token is fg.TextResponse) {
          fullText += token.token;
        } else if (token is fg.FunctionCallResponse) {
          toolCall = token;
        }
      }

      if (toolCall != null) {
        return ToolCallResult(ToolCall(
          toolName: toolCall.name,
          arguments: Map<String, dynamic>.from(toolCall.args),
        ));
      }
      return TextResult(fullText.trim());
    } finally {
      await model.close();
    }
  }

  // ── stream ──────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    _assertSupported();

    final (chat, model) = await _createChat(const []);
    try {
      for (final msg in messages) {
        await _addMessage(chat, msg);
      }
      await for (final token in chat.generateChatResponseAsync()) {
        if (token is fg.TextResponse) yield token.token;
      }
    } finally {
      await model.close();
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<(fg.InferenceChat, fg.InferenceModel)> _createChat(
      List<AgenticTool> tools) async {
    final modelType = _modelTypeFor(modelId);
    final fileType = _fileTypeFor(modelPath);

    // Install (or confirm already installed) the model file.
    await fg.FlutterGemma.installModel(
      modelType: modelType,
      fileType: fileType,
    ).fromFile(modelPath).install();

    // Obtain an InferenceModel configured for this session.
    final model = await fg.FlutterGemma.getActiveModel(
      supportImage: supportImage,
    );

    final hasTools = tools.isNotEmpty;
    final chat = await model.createChat(
      supportImage: supportImage,
      tools: hasTools ? _convertTools(tools) : [],
      supportsFunctionCalls: hasTools,
    );

    return (chat, model);
  }

  Future<void> _addMessage(fg.InferenceChat chat, Message msg) async {
    await chat.addQueryChunk(fg.Message.text(
      text: msg.content,
      isUser: msg.role == MessageRole.user || msg.role == MessageRole.system,
    ));
  }

  List<fg.Tool> _convertTools(List<AgenticTool> tools) => tools
      .map((t) => fg.Tool(
            name: t.name,
            description: t.description,
            parameters: t.parameters,
          ))
      .toList();

  /// Maps a [modelId] string to the flutter_gemma [ModelType] enum.
  static fg_model.ModelType _modelTypeFor(String modelId) {
    if (modelId.startsWith('gemma-3n')) return fg_model.ModelType.gemma4;
    if (modelId == 'function-gemma-270m') {
      return fg_model.ModelType.functionGemma;
    }
    if (modelId.startsWith('phi')) return fg_model.ModelType.phi;
    if (modelId.startsWith('qwen3')) return fg_model.ModelType.qwen3;
    if (modelId.startsWith('qwen')) return fg_model.ModelType.qwen;
    // gemma-3-1b-it, smollm, etc.
    return fg_model.ModelType.gemmaIt;
  }

  /// Infers [ModelFileType] from the file extension.
  static fg_model.ModelFileType _fileTypeFor(String path) {
    if (path.endsWith('.litertlm')) return fg_model.ModelFileType.litertlm;
    if (path.endsWith('.bin') || path.endsWith('.tflite')) {
      return fg_model.ModelFileType.binary;
    }
    return fg_model.ModelFileType.task; // default: .task
  }

  void _assertSupported() {
    if (kIsWeb) {
      throw UnsupportedError(
        'GemmaProvider does not support web builds. '
        'Use GeminiProvider or OpenAIProvider for web.',
      );
    }
  }
}

/// Helpers for managing local Gemma / LiteRT-LM model files.
///
/// ## Platform compatibility matrix
///
/// | Format      | Extension   | macOS | Windows | Linux | Android | iOS |
/// |-------------|-------------|:-----:|:-------:|:-----:|:-------:|:---:|
/// | LiteRT-LM   | `.litertlm` |  ✅   |   ✅    |  ✅   |   ✅    | ✅  |
/// | MediaPipe   | `.task`     |  ❌   |   ❌    |  ❌   |   ✅    | ✅  |
/// | Binary/TFLite | `.bin` / `.tflite` | ⚠️ | ⚠️ | ⚠️ | ✅ | ✅ |
///
/// **Rule of thumb:** always use `.litertlm` — it works everywhere.
///
/// ## Quick download
/// ```dart
/// // By model ID — uses the built-in URL catalogue:
/// await GemmaModelManager.download(
///   modelId: 'qwen3-0.6b',
///   destinationPath: '/data/user/0/.../qwen3-0.6b.litertlm',
///   onProgress: (received, total) => print('${received ~/ 1e6} MB'),
/// );
///
/// // By arbitrary URL (any HuggingFace or CDN link):
/// await GemmaModelManager.downloadFromUrl(
///   url: 'https://huggingface.co/.../model.litertlm',
///   destinationPath: '/data/user/0/.../model.litertlm',
/// );
/// ```
///
/// A HuggingFace token is read automatically from the `HF_TOKEN` or
/// `HUGGINGFACE_TOKEN` environment variable — set either one for gated
/// (private / restricted) repos.
abstract class GemmaModelManager {
  // ── URL catalogue ─────────────────────────────────────────────────────────

  /// HuggingFace download URL for a known [modelId].
  ///
  /// All URLs return `.litertlm` files (LiteRT-LM format) unless noted —
  /// these work on every supported platform (macOS, Windows, Linux, Android, iOS).
  ///
  /// Exceptions:
  /// - `gemma-3n-*` — only available as `.task` (Google preview); mobile only.
  /// - `smollm-135m` — only available as `.task`; mobile only.
  static String downloadUrl(String modelId) => switch (modelId) {
        // ── Gemma 3n (multimodal) — .task, mobile only ──────────────────────
        'gemma-3n-e2b-it' =>
          'https://huggingface.co/google/gemma-3n-E2B-it-litert-preview/resolve/main/gemma-3n-E2B-it-int4.task',
        'gemma-3n-e4b-it' =>
          'https://huggingface.co/google/gemma-3n-E4B-it-litert-preview/resolve/main/gemma-3n-E4B-it-int4.task',
        // ── Gemma 3 text models — .litertlm, all platforms ──────────────────
        'gemma-3-1b-it' =>
          'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/gemma3-1b-it-q4_1.litertlm',
        'gemma-3-270m-it' =>
          'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.litertlm',
        // ── FunctionGemma — .litertlm, tool calling, all platforms ──────────
        'function-gemma-270m' =>
          'https://huggingface.co/sasha-denisov/function-gemma-270M-it/resolve/main/functiongemma-270M-it.litertlm',
        // ── Phi-4 Mini — .litertlm, all platforms ───────────────────────────
        'phi-4-mini' =>
          'https://huggingface.co/litert-community/Phi-4-mini-instruct/resolve/main/phi-4-mini-instruct-q4_1.litertlm',
        // ── Qwen3 — .litertlm, all platforms ────────────────────────────────
        'qwen3-0.6b' =>
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0.6b-q4_1.litertlm',
        'qwen3-1.7b' =>
          'https://huggingface.co/litert-community/Qwen3-1.7B/resolve/main/qwen3-1.7b-q4_1.litertlm',
        // ── SmolLM — .task, mobile only ─────────────────────────────────────
        'smollm-135m' =>
          'https://huggingface.co/litert-community/SmolLM-135M-Instruct/resolve/main/SmolLM-135M-Instruct_multi-prefill-seq_q8_ekv1280.task',
        _ => throw ArgumentError(
            'Unknown model ID: "$modelId". '
            'Pass a full URL to downloadFromUrl() for custom models.'),
      };

  /// Approximate compressed download size in MB for each known model.
  static int approximateSizeMb(String modelId) => switch (modelId) {
        'gemma-3n-e2b-it' => 1100,
        'gemma-3n-e4b-it' => 2200,
        'gemma-3-1b-it' => 500,
        'gemma-3-270m-it' => 150,
        'function-gemma-270m' => 271,
        'phi-4-mini' => 2400,
        'qwen3-0.6b' => 400,
        'qwen3-1.7b' => 1000,
        'smollm-135m' => 90,
        _ => 0,
      };

  // ── Download helpers ──────────────────────────────────────────────────────

  /// Downloads a known model by [modelId] to [destinationPath].
  ///
  /// Equivalent to calling [downloadFromUrl] with the URL returned by
  /// [downloadUrl]. A HuggingFace token is read from the `HF_TOKEN` /
  /// `HUGGINGFACE_TOKEN` environment variable automatically.
  ///
  /// [onProgress] is called periodically with `(bytesReceived, totalBytes)`.
  /// `totalBytes` is -1 if the server does not send a Content-Length header.
  ///
  /// Throws [ModelDownloadException] on HTTP errors or I/O failures.
  static Future<void> download({
    required String modelId,
    required String destinationPath,
    String? hfToken,
    void Function(int received, int total)? onProgress,
  }) =>
      downloadFromUrl(
        url: downloadUrl(modelId),
        destinationPath: destinationPath,
        hfToken: hfToken,
        onProgress: onProgress,
      );

  /// Downloads a model from any [url] to [destinationPath].
  ///
  /// ### Authentication
  /// Supply [hfToken] directly, or set the `HF_TOKEN` / `HUGGINGFACE_TOKEN`
  /// environment variable. The token is sent as `Authorization: Bearer <token>`
  /// and is only attached to requests that go to `huggingface.co`.
  ///
  /// ### Progress
  /// [onProgress] receives `(bytesReceived, totalBytes)` where `totalBytes`
  /// equals -1 when no Content-Length header is present.
  ///
  /// ### Resumption
  /// A partially downloaded `.part` file is left on disk if the download is
  /// interrupted. Re-calling this method discards the partial file and
  /// restarts from scratch (resumable downloads are not yet implemented).
  ///
  /// Throws [ModelDownloadException] on HTTP ≥ 400 or I/O errors.
  static Future<void> downloadFromUrl({
    required String url,
    required String destinationPath,
    String? hfToken,
    void Function(int received, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'GemmaModelManager.downloadFromUrl is not available on web.');
    }

    // Resolve token: explicit arg > env vars.
    // An explicit hfToken is attached to any domain (caller's responsibility).
    // Env-var tokens are restricted to huggingface.co to avoid leaking creds.
    final envToken = Platform.environment['HF_TOKEN'] ??
        Platform.environment['HUGGINGFACE_TOKEN'];

    final dest = File(destinationPath);
    final partFile = File('$destinationPath.part');

    // Remove stale partial download
    if (await partFile.exists()) await partFile.delete();

    final client = http.Client();
    try {
      final uri = Uri.parse(url);
      final request = http.Request('GET', uri);

      // Attach auth header when:
      //  • an explicit token was passed (any domain), OR
      //  • env token exists AND URL is on huggingface.co
      final effectiveToken = hfToken ??
          (uri.host.contains('huggingface.co') ? envToken : null);
      if (effectiveToken != null) {
        request.headers['Authorization'] = 'Bearer $effectiveToken';
      }

      final response = await client.send(request);

      if (response.statusCode == 401) {
        throw ModelDownloadException(
          'HTTP 401 Unauthorized for $url.\n'
          'Set the HF_TOKEN environment variable or pass hfToken: "<token>".',
        );
      }
      if (response.statusCode == 403) {
        throw ModelDownloadException(
          'HTTP 403 Forbidden for $url.\n'
          'Accept the model license on HuggingFace and supply a valid HF token.',
        );
      }
      if (response.statusCode >= 400) {
        throw ModelDownloadException(
            'HTTP ${response.statusCode} downloading $url');
      }

      final total = response.contentLength ?? -1;
      int received = 0;

      final sink = partFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // Rename .part → final destination
      await partFile.rename(destinationPath);
    } on ModelDownloadException {
      rethrow;
    } on Exception catch (e) {
      if (await partFile.exists()) await partFile.delete();
      throw ModelDownloadException('Download failed for $url: $e');
    } finally {
      client.close();
    }

    // Sanity-check: ensure the file landed where expected
    if (!await dest.exists()) {
      throw ModelDownloadException(
          'Download appeared to succeed but file not found at $destinationPath');
    }
  }

  // ── File-system helpers ───────────────────────────────────────────────────

  /// Returns `true` if a file already exists at [modelPath].
  static Future<bool> isDownloaded(String modelPath) async {
    if (kIsWeb) return false;
    return File(modelPath).exists();
  }

  /// Deletes the model file at [modelPath] to free disk space.
  /// Does nothing if the file does not exist.
  static Future<void> deleteModel(String modelPath) async {
    if (kIsWeb) return;
    final f = File(modelPath);
    if (await f.exists()) await f.delete();
  }
}

/// Thrown when [GemmaModelManager.downloadFromUrl] encounters an error.
class ModelDownloadException implements Exception {
  final String message;
  const ModelDownloadException(this.message);
  @override
  String toString() => 'ModelDownloadException: $message';
}
