/// Universal model download and routing manager.
///
/// Single entry-point for every model acquisition flow:
/// - HuggingFace URL / repo+file
/// - Direct HTTPS URL (any CDN)
/// - Ollama model pull
///
/// Format is detected automatically from the file extension.
/// The appropriate [LlmProvider] subclass is returned ready to use.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../providers/llm_provider.dart';
import '../providers/gemma_provider.dart';
import '../providers/ollama_provider.dart';
import 'hf_hub.dart';
import 'model_format.dart';

/// Callback type for download progress: `(bytesReceived, totalBytes)`.
/// `totalBytes` is -1 when the server omits a Content-Length header.
typedef ProgressCallback = void Function(int received, int total);

/// Central manager for acquiring and instantiating any supported model format.
///
/// ## Quick examples
///
/// ```dart
/// // From a HuggingFace repo (auto-picks the best file):
/// final path = await UniversalModelManager.downloadFromHF(
///   repoId: 'litert-community/Qwen3-0.6B',
///   destinationDir: '/path/to/models',
///   onProgress: (r, t) => print('${r ~/ 1e6} MB'),
/// );
///
/// // From any URL:
/// await UniversalModelManager.downloadFromUrl(
///   url: 'https://huggingface.co/.../model.gguf',
///   destinationPath: '/path/to/model.gguf',
/// );
///
/// // Create the right provider for a local file:
/// final provider = UniversalModelManager.providerForFile('/path/to/model.litertlm');
///
/// // Pull an Ollama model:
/// await UniversalModelManager.pullOllamaModel('llama3.2');
/// ```
///
/// HuggingFace tokens are read from `HF_TOKEN` / `HUGGINGFACE_TOKEN` env
/// variables automatically, or supply [hfToken] explicitly.
abstract class UniversalModelManager {
  // ── Download: HuggingFace repo ───────────────────────────────────────────

  /// Download the best model file from a HuggingFace repo.
  ///
  /// [repoId] is `owner/name` (e.g. `"litert-community/Qwen3-0.6B"`).
  /// [filename] picks a specific file; omit to auto-select the best one for
  /// Flutter (prefers `.litertlm` > `.gguf` > `.task`).
  /// [destinationDir] is the directory where the file will be saved.
  ///
  /// Returns the absolute path to the downloaded file.
  ///
  /// Throws [HFException] if the repo is not found / auth fails.
  /// Throws [ModelDownloadException] on I/O or HTTP errors.
  /// Throws [UnsupportedFormatException] if no runnable file exists.
  static Future<String> downloadFromHF({
    required String repoId,
    String? filename,
    required String destinationDir,
    String? hfToken,
    String revision = 'main',
    ProgressCallback? onProgress,
  }) async {
    _assertNative();

    final HFFile targetFile;
    if (filename != null) {
      targetFile = HFFile(rfilename: filename);
    } else {
      final best = await HFHub.findBestFile(
        repoId,
        hfToken: hfToken,
        revision: revision,
      );
      if (best == null) {
        throw UnsupportedFormatException(
          ModelFormat.unknown,
          'No runnable model file found in "$repoId". '
          'The repo may only contain SafeTensors or ONNX files — use '
          'HFInferenceProvider for cloud inference instead.',
        );
      }
      targetFile = best;
    }

    final url =
        HFHub.downloadUrl(repoId, targetFile.rfilename, revision: revision);
    final destPath = _join(destinationDir, _basename(targetFile.rfilename));

    await downloadFromUrl(
      url: url,
      destinationPath: destPath,
      hfToken: hfToken,
      onProgress: onProgress,
    );

    return destPath;
  }

  // ── Download: direct URL ─────────────────────────────────────────────────

  /// Download a model from any HTTPS URL to [destinationPath].
  ///
  /// ### Authentication
  /// Supply [hfToken] directly, or set `HF_TOKEN` / `HUGGINGFACE_TOKEN`.
  /// The token is only attached to `huggingface.co` requests unless an
  /// explicit [hfToken] is provided (to avoid leaking credentials to
  /// arbitrary hosts).
  ///
  /// ### Partial files
  /// A `<destinationPath>.part` file is used during download. If one already
  /// exists it is deleted first (full restart). On failure the `.part` file
  /// is also deleted.
  ///
  /// Throws [ModelDownloadException] on HTTP ≥ 400 or I/O errors.
  static Future<void> downloadFromUrl({
    required String url,
    required String destinationPath,
    String? hfToken,
    ProgressCallback? onProgress,
  }) async {
    _assertNative();

    final envToken = Platform.environment['HF_TOKEN'] ??
        Platform.environment['HUGGINGFACE_TOKEN'];
    final uri = Uri.parse(url);
    final effectiveToken =
        hfToken ?? (uri.host.contains('huggingface.co') ? envToken : null);

    // Ensure destination directory exists
    await File(destinationPath).parent.create(recursive: true);

    final partFile = File('$destinationPath.part');
    if (await partFile.exists()) await partFile.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', uri);
      if (effectiveToken != null) {
        request.headers['Authorization'] = 'Bearer $effectiveToken';
      }

      final response = await client.send(request);
      _checkHttpStatus(response.statusCode, url);

      final total = response.contentLength ?? -1;
      var received = 0;

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

      await partFile.rename(destinationPath);
    } on ModelDownloadException {
      rethrow;
    } on Exception catch (e) {
      if (await partFile.exists()) await partFile.delete();
      throw ModelDownloadException('Download failed for $url: $e');
    } finally {
      client.close();
    }

    if (!await File(destinationPath).exists()) {
      throw ModelDownloadException(
          'Download appeared to succeed but file not found: $destinationPath');
    }
  }

  // ── Ollama ────────────────────────────────────────────────────────────────

  /// Pull (download) an Ollama model by name using the Ollama HTTP API.
  ///
  /// Requires Ollama to be running at [baseUrl] (default `localhost:11434`).
  /// [onProgress] fires with `(pulledBytes, totalBytes)` when the server
  /// reports progress. `totalBytes` may be -1 if unknown.
  ///
  /// Throws [OllamaException] if the server is unreachable or the pull fails.
  static Future<void> pullOllamaModel(
    String model, {
    String baseUrl = 'http://localhost:11434',
    ProgressCallback? onProgress,
  }) async {
    final client = http.Client();
    try {
      final request =
          http.Request('POST', Uri.parse('$baseUrl/api/pull'));
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'name': model, 'stream': true});

      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        throw OllamaException(
            'Pull failed (HTTP ${streamed.statusCode}): $body');
      }

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        final Map<String, dynamic> json;
        try {
          json = jsonDecode(line) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final err = json['error'] as String?;
        if (err != null) throw OllamaException('Pull error: $err');

        final completed = (json['completed'] as num?)?.toInt() ?? 0;
        final total = (json['total'] as num?)?.toInt() ?? -1;
        if (completed > 0 || total > 0) onProgress?.call(completed, total);

        if ((json['status'] as String?) == 'success') break;
      }
    } on OllamaException {
      rethrow;
    } on Exception catch (e) {
      throw OllamaException(
          'Failed to pull "$model" from $baseUrl: $e\n'
          'Is Ollama running? Install from https://ollama.ai');
    } finally {
      client.close();
    }
  }

  // ── Provider factory ──────────────────────────────────────────────────────

  /// Create the appropriate [LlmProvider] for a local model file.
  ///
  /// The format is inferred from the file extension. Supply [modelId] for
  /// better logging and model-type detection.
  ///
  /// | Extension | Returns |
  /// |-----------|---------|
  /// | `.litertlm` | [GemmaProvider] |
  /// | `.task` | [GemmaProvider] |
  /// | `.tflite` | [GemmaProvider] |
  /// | `.bin` | [GemmaProvider] |
  /// | `.gguf` | Guidance to use [LlamaCppProvider] |
  ///
  /// Throws [UnsupportedFormatException] for SafeTensors, ONNX, or unknown.
  static LlmProvider providerForFile(
    String modelPath, {
    String? modelId,
    bool supportImage = false,
  }) {
    final format = ModelFormat.detect(modelPath);
    final id = modelId ?? _basename(modelPath);

    switch (format) {
      case ModelFormat.litertlm:
      case ModelFormat.task:
      case ModelFormat.tflite:
      case ModelFormat.binary:
        return GemmaProvider(
          modelId: id,
          modelPath: modelPath,
          supportImage: supportImage,
        );

      case ModelFormat.gguf:
        throw UnsupportedError(
          'GGUF detected — use LlamaCppProvider directly:\n'
          "  import 'package:flutter_agents/src/providers/llama_cpp_provider.dart';\n"
          '  LlamaCppProvider(modelPath: "$modelPath")',
        );

      case ModelFormat.safetensors:
        throw UnsupportedFormatException(
          format,
          'SafeTensors cannot run on-device in Flutter.\n'
          'Options:\n'
          '  • Use HFInferenceProvider for cloud inference\n'
          '  • Convert to GGUF: python llama.cpp/convert_hf_to_gguf.py <dir> --outtype q4_k_m\n'
          '  • Convert to .litertlm: use the litert-community conversion tools',
        );

      case ModelFormat.onnx:
        throw UnsupportedFormatException(
          format,
          'ONNX is not yet supported in Flutter. '
          'Convert to GGUF or .litertlm, or use a cloud provider.',
        );

      case ModelFormat.ollama:
        return OllamaProvider(model: modelPath);

      case ModelFormat.hfInference:
      case ModelFormat.unknown:
        throw UnsupportedFormatException(
          format,
          'Cannot create an on-device provider for "$modelPath". '
          'Use HFInferenceProvider for HF cloud inference, '
          'or OllamaProvider for a local Ollama model.',
        );
    }
  }

  // ── File-system helpers ───────────────────────────────────────────────────

  /// Returns `true` if a model file already exists at [path].
  static Future<bool> isDownloaded(String path) async {
    if (kIsWeb) return false;
    return File(path).exists();
  }

  /// Delete a model file to free disk space. No-op if the file is missing.
  static Future<void> deleteModel(String path) async {
    if (kIsWeb) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static void _assertNative() {
    if (kIsWeb) {
      throw UnsupportedError(
          'UniversalModelManager is not available on web.');
    }
  }

  static String _basename(String path) =>
      path.replaceAll('\\', '/').split('/').last;

  static String _join(String dir, String file) {
    final d = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    return '$d/$file';
  }

  static void _checkHttpStatus(int code, String url) {
    if (code == 200) return;
    if (code == 401) {
      throw ModelDownloadException(
        'HTTP 401 Unauthorized: $url\n'
        'Set the HF_TOKEN env var or pass hfToken: "<token>".',
      );
    }
    if (code == 403) {
      throw ModelDownloadException(
        'HTTP 403 Forbidden: $url\n'
        'Accept the model license on huggingface.co and supply a valid token.',
      );
    }
    if (code >= 400) {
      throw ModelDownloadException('HTTP $code downloading $url');
    }
  }
}
