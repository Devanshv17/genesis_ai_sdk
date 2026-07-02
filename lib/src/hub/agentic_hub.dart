/// AgenticHub — one-stop factory for creating AI agents from any source.
///
/// This is the single highest-level API in flutter_agentic. Give it a URL,
/// a HuggingFace repo, an Ollama model name, or a local file path — it
/// downloads the model (if needed), detects the format, picks the right
/// provider, and returns a ready-to-use [AgenticAgent].
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import '../agent/agentic_agent.dart';
import '../memory/memory_store.dart';
import '../providers/gemma_provider.dart';
import '../providers/hf_inference_provider.dart';
import '../providers/llm_provider.dart';
import '../providers/ollama_provider.dart';
import '../tools/agentic_tool.dart';
import 'hf_hub.dart';
import 'model_format.dart';
import 'universal_model_manager.dart';

/// One-stop factory for creating [AgenticAgent]s from any AI model source.
///
/// ## Examples
///
/// ```dart
/// // ── From HuggingFace (downloads + runs locally) ──────────────────────
/// final agent = await AgenticHub.fromHuggingFace(
///   repoId: 'litert-community/Qwen3-0.6B',
///   destinationDir: await _modelsDir(),
///   systemPrompt: 'You are a helpful assistant.',
///   onProgress: (r, t) => setState(() => progress = r / t),
/// );
///
/// // ── From any URL ─────────────────────────────────────────────────────
/// final agent = await AgenticHub.fromUrl(
///   url: 'https://huggingface.co/bartowski/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
///   destinationPath: '/tmp/models/qwen3.gguf',
///   systemPrompt: 'You are a helpful assistant.',
/// );
///
/// // ── From Ollama (no download; server must be running) ────────────────
/// final agent = AgenticHub.fromOllama(
///   model: 'llama3.2',
///   systemPrompt: 'You are a helpful assistant.',
/// );
///
/// // ── From HF cloud (no download; any HF model, any format) ───────────
/// final agent = AgenticHub.fromHFCloud(
///   modelId: 'microsoft/Phi-4-mini-instruct',
///   apiToken: 'hf_xxxx',
///   systemPrompt: 'You are a helpful assistant.',
/// );
///
/// // ── From a local file already on disk ────────────────────────────────
/// final agent = AgenticHub.fromFile(
///   modelPath: '/storage/emulated/0/models/qwen3.litertlm',
///   systemPrompt: 'You are a helpful assistant.',
/// );
/// ```
///
/// All factory methods accept the same common agent parameters:
/// [systemPrompt], [tools], [memory], [sessionId].
abstract class AgenticHub {
  // ── HuggingFace (on-device) ───────────────────────────────────────────────

  /// Download the best model file from a HuggingFace repo and create an agent.
  ///
  /// Automatically:
  /// 1. Queries the HF Hub API to list repo files.
  /// 2. Picks the best file for Flutter (`.litertlm` > `.gguf` > `.task`).
  /// 3. Downloads it to [destinationDir] (skips if already present).
  /// 4. Constructs the right provider and wraps it in a [AgenticAgent].
  ///
  /// [repoId] — HuggingFace `owner/name`, e.g. `"litert-community/Qwen3-0.6B"`.
  /// [filename] — Pin a specific file; otherwise auto-selects the best.
  /// [destinationDir] — Directory to save the model. Use `path_provider`
  ///   to get a platform-appropriate path.
  /// [hfToken] — HF access token. Read from `HF_TOKEN` env var if omitted.
  /// [onProgress] — `(bytesReceived, totalBytes)` callback for UI progress.
  /// [forceRedownload] — Re-download even if the file already exists.
  ///
  /// Throws [HFException], [ModelDownloadException], [UnsupportedFormatException].
  static Future<AgenticAgent> fromHuggingFace({
    required String repoId,
    String? filename,
    required String destinationDir,
    String? hfToken,
    String revision = 'main',
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
    ProgressCallback? onProgress,
    bool forceRedownload = false,
  }) async {
    _assertNative('fromHuggingFace');

    // Resolve which file to use
    final HFFile targetFile;
    if (filename != null) {
      targetFile = HFFile(rfilename: filename);
    } else {
      final best = await HFHub.findBestFile(repoId,
          hfToken: hfToken, revision: revision);
      if (best == null) {
        throw UnsupportedFormatException(
          ModelFormat.unknown,
          'No runnable file found in "$repoId". '
          'Use fromHFCloud() for cloud inference, or specify a filename manually.',
        );
      }
      targetFile = best;
    }

    final destPath = _joinPath(
        destinationDir, targetFile.rfilename.split('/').last);

    // Download only if needed
    final alreadyPresent =
        !forceRedownload && await UniversalModelManager.isDownloaded(destPath);
    if (!alreadyPresent) {
      await UniversalModelManager.downloadFromHF(
        repoId: repoId,
        filename: targetFile.rfilename,
        destinationDir: destinationDir,
        hfToken: hfToken,
        revision: revision,
        onProgress: onProgress,
      );
    }

    final provider = _providerForFile(destPath, repoId);
    return _makeAgent(provider,
        systemPrompt: systemPrompt,
        tools: tools,
        memory: memory,
        sessionId: sessionId);
  }

  // ── Direct URL (on-device) ────────────────────────────────────────────────

  /// Download a model from any URL and create an agent.
  ///
  /// The format is inferred from the file extension in [url].
  /// HuggingFace URLs are detected automatically and the token is attached.
  ///
  /// [url] — Direct download link (e.g. HuggingFace CDN, GitHub releases).
  /// [destinationPath] — Full path where the file will be saved.
  ///
  /// Throws [ModelDownloadException], [UnsupportedFormatException].
  static Future<AgenticAgent> fromUrl({
    required String url,
    required String destinationPath,
    String? hfToken,
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
    ProgressCallback? onProgress,
    bool forceRedownload = false,
  }) async {
    _assertNative('fromUrl');

    final alreadyPresent = !forceRedownload &&
        await UniversalModelManager.isDownloaded(destinationPath);
    if (!alreadyPresent) {
      await UniversalModelManager.downloadFromUrl(
        url: url,
        destinationPath: destinationPath,
        hfToken: hfToken,
        onProgress: onProgress,
      );
    }

    final provider = _providerForFile(destinationPath, null);
    return _makeAgent(provider,
        systemPrompt: systemPrompt,
        tools: tools,
        memory: memory,
        sessionId: sessionId);
  }

  // ── Ollama (local server) ─────────────────────────────────────────────────

  /// Create an agent backed by a locally running [Ollama](https://ollama.ai)
  /// model.
  ///
  /// Ollama must already be running. This method optionally pulls the model
  /// if [autoPull] is `true` and Ollama does not already have it.
  ///
  /// [model] — Ollama model name, e.g. `"llama3.2"`, `"phi4"`, `"qwen3"`.
  /// [baseUrl] — Ollama API base URL (default `http://localhost:11434`).
  /// [autoPull] — If `true`, run `ollama pull <model>` if not yet downloaded.
  /// [onPullProgress] — Progress callback for the pull operation.
  ///
  /// Throws [OllamaException] if the server is unreachable.
  static Future<AgenticAgent> fromOllama({
    required String model,
    String baseUrl = 'http://localhost:11434',
    bool autoPull = false,
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
    ProgressCallback? onPullProgress,
  }) async {
    if (autoPull) {
      // Check if the model is already available; only pull if missing
      final provider = OllamaProvider(model: model, baseUrl: baseUrl);
      final status = await provider.checkStatus();
      if (!status.modelAvailable) {
        await UniversalModelManager.pullOllamaModel(
          model,
          baseUrl: baseUrl,
          onProgress: onPullProgress,
        );
      }
    }

    return _makeAgent(
      OllamaProvider(model: model, baseUrl: baseUrl),
      systemPrompt: systemPrompt,
      tools: tools,
      memory: memory,
      sessionId: sessionId,
    );
  }

  // ── HF Inference API (cloud) ──────────────────────────────────────────────

  /// Create an agent backed by the HuggingFace Serverless Inference API.
  ///
  /// No download required. Inference runs on HF's GPU fleet. Works for any
  /// public model on HuggingFace, including SafeTensors-only models.
  ///
  /// [modelId] — HF model ID, e.g. `"microsoft/Phi-4-mini-instruct"`.
  /// [apiToken] — HF API token. Read from `HF_TOKEN` env var if omitted.
  static AgenticAgent fromHFCloud({
    required String modelId,
    String? apiToken,
    int maxTokens = 1024,
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
  }) =>
      _makeAgent(
        HFInferenceProvider(
          modelId: modelId,
          apiToken: apiToken,
          maxTokens: maxTokens,
        ),
        systemPrompt: systemPrompt,
        tools: tools,
        memory: memory,
        sessionId: sessionId,
      );

  // ── Local file (already downloaded) ──────────────────────────────────────

  /// Create an agent from a model file that is already on disk.
  ///
  /// The provider is selected by file extension:
  /// - `.litertlm`, `.task`, `.tflite`, `.bin` → [GemmaProvider]
  /// - `.gguf` → guidance to use [LlamaCppProvider] directly
  ///
  /// Throws [UnsupportedFormatException] for SafeTensors / ONNX.
  static AgenticAgent fromFile({
    required String modelPath,
    String? modelId,
    bool supportImage = false,
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
  }) {
    final provider = UniversalModelManager.providerForFile(
      modelPath,
      modelId: modelId,
      supportImage: supportImage,
    );
    return _makeAgent(provider,
        systemPrompt: systemPrompt,
        tools: tools,
        memory: memory,
        sessionId: sessionId);
  }

  // ── Provider-first shortcut ───────────────────────────────────────────────

  /// Create an agent from any already-constructed [LlmProvider].
  ///
  /// Use this when you have a provider from another source (e.g. a custom
  /// provider, or [LlamaCppProvider] for GGUF files).
  static AgenticAgent fromProvider({
    required LlmProvider provider,
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
  }) =>
      _makeAgent(provider,
          systemPrompt: systemPrompt,
          tools: tools,
          memory: memory,
          sessionId: sessionId);

  // ── Utilities ─────────────────────────────────────────────────────────────

  /// Check whether a model file at [modelPath] has already been downloaded.
  static Future<bool> isDownloaded(String modelPath) =>
      UniversalModelManager.isDownloaded(modelPath);

  /// Delete a cached model file to free storage.
  static Future<void> deleteModel(String modelPath) =>
      UniversalModelManager.deleteModel(modelPath);

  /// Fetch the list of files in a HuggingFace repo to browse available models.
  static Future<List<HFFile>> listHFFiles(
    String repoId, {
    String? hfToken,
  }) =>
      HFHub.listFiles(repoId, hfToken: hfToken);

  // ── Private ───────────────────────────────────────────────────────────────

  static AgenticAgent _makeAgent(
    LlmProvider provider, {
    String? systemPrompt,
    List<AgenticTool> tools = const [],
    MemoryStore? memory,
    String? sessionId,
  }) =>
      AgenticAgent(
        provider: provider,
        systemPrompt: systemPrompt ?? 'You are a helpful assistant.',
        tools: tools,
        memory: memory,
        sessionId: sessionId ?? 'default',
      );

  /// Create the appropriate provider for a local file, with special handling
  /// for `.gguf` files (points developer to LlamaCppProvider).
  static LlmProvider _providerForFile(String path, String? hint) {
    final format = ModelFormat.detect(path);
    if (format == ModelFormat.gguf) {
      throw UnsupportedError(
        'GGUF file detected at "$path".\n'
        'Use LlamaCppProvider directly (it requires llama_cpp_dart):\n\n'
        "  import 'package:flutter_agentic/src/providers/llama_cpp_provider.dart';\n\n"
        '  final provider = LlamaCppProvider(modelPath: "$path");\n'
        '  final agent = AgenticHub.fromProvider(provider: provider);\n',
      );
    }
    return UniversalModelManager.providerForFile(path,
        modelId: hint ?? path.split('/').last);
  }

  static void _assertNative(String method) {
    if (kIsWeb) {
      throw UnsupportedError(
        'AgenticHub.$method is not available on web. '
        'Use AgenticHub.fromHFCloud() or AgenticHub.fromOllama() instead.',
      );
    }
  }

  static String _joinPath(String dir, String file) {
    final d = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    return '$d/$file';
  }
}

/// Convenience extension that lets you get the platform models directory
/// without importing path_provider directly.
///
/// Usage:
/// ```dart
/// final dir = await AgenticHub.platformModelsDir();
/// final agent = await AgenticHub.fromHuggingFace(
///   repoId: 'litert-community/Qwen3-0.6B',
///   destinationDir: dir,
/// );
/// ```
extension AgenticHubPlatformPaths on AgenticHub {
  /// Returns a platform-appropriate **writable** directory for storing model files.
  ///
  /// Uses `path_provider` internally so the path is always correct:
  ///
  /// | Platform | Directory | Notes |
  /// |----------|-----------|-------|
  /// | Android  | `getApplicationSupportDirectory()` | App-private, survives updates |
  /// | iOS      | `getApplicationSupportDirectory()` | App sandbox, survives updates |
  /// | macOS    | `getApplicationSupportDirectory()` | `~/Library/Application Support/…` |
  /// | Windows  | `getApplicationSupportDirectory()` | `%APPDATA%/…` |
  /// | Linux    | `getApplicationSupportDirectory()` | `~/.local/share/…` |
  ///
  /// A `genesis_models` sub-directory is created inside the support dir.
  /// Override [subdir] to use a custom folder name.
  ///
  /// Throws [UnsupportedError] on web (use [AgenticHub.fromHFCloud] there).
  static Future<String> platformModelsDir({String subdir = 'genesis_models'}) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'platformModelsDir() is not available on web. '
        'Use AgenticHub.fromHFCloud() for web builds.',
      );
    }

    // path_provider gives the right OS-specific writable directory on every
    // platform (Android, iOS, macOS, Windows, Linux).
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$subdir');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
