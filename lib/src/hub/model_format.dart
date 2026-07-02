/// Model file format enumeration and detection utilities.
library;

/// Every on-device and cloud model format understood by the flutter_agentic SDK.
///
/// | Format | Extension(s) | Backend | Platforms |
/// |--------|-------------|---------|-----------|
/// | [litertlm] | `.litertlm` | flutter_gemma / LiteRT-LM | All |
/// | [task] | `.task` | flutter_gemma / MediaPipe | Android, iOS |
/// | [gguf] | `.gguf` | llama_cpp_dart | macOS, Windows, Linux, Android, iOS |
/// | [tflite] | `.tflite` | flutter_gemma | Android, iOS, macOS |
/// | [binary] | `.bin` | flutter_gemma | Android, iOS |
/// | [safetensors] | `.safetensors` | HF Inference API (cloud) | Web + Native |
/// | [onnx] | `.onnx` | Not yet supported | — |
/// | [ollama] | _(name)_ | OllamaProvider (local server) | macOS, Windows, Linux |
/// | [hfInference] | _(repo id)_ | HFInferenceProvider (cloud) | All |
enum ModelFormat {
  // ── On-device: flutter_gemma ──────────────────────────────────────────────
  /// LiteRT-LM format — the preferred format for Flutter.
  /// Works on **all** platforms: macOS, Windows, Linux, Android, iOS.
  litertlm,

  /// MediaPipe Task format — **mobile only** (Android + iOS).
  /// Does NOT work on macOS / Windows / Linux desktop.
  task,

  /// TFLite flat-buffer format — Android, iOS, and some desktop builds.
  tflite,

  /// Raw binary TFLite — older format, limited model support.
  binary,

  // ── On-device: llama_cpp_dart ─────────────────────────────────────────────
  /// GGUF format — works on all platforms via [llama_cpp_dart].
  /// Most models on HuggingFace that are "community" quantisations are GGUF.
  gguf,

  // ── Cloud-only ────────────────────────────────────────────────────────────
  /// HuggingFace SafeTensors — native HF training format.
  /// Cannot be run on-device in Flutter. Genesis falls back to the HF
  /// Serverless Inference API automatically when this format is detected.
  safetensors,

  /// ONNX model — no Flutter package supports it yet.
  /// Genesis raises a [UnsupportedFormatException] with a conversion guide.
  onnx,

  // ── Server-based ─────────────────────────────────────────────────────────
  /// Ollama model name (e.g. `llama3.2`, `phi4`). No file download needed;
  /// Ollama's server must be running locally.
  ollama,

  /// HuggingFace Serverless Inference API — a cloud endpoint that runs any
  /// public model on HF's GPU fleet. Requires an HF API token.
  hfInference,

  /// Unknown / unsupported format.
  unknown;

  // ── Detection helpers ─────────────────────────────────────────────────────

  /// Infer the [ModelFormat] from a file path, URL, or Ollama model name.
  ///
  /// Rules (in order):
  /// 1. If [urlOrPath] contains no file extension and no `/` separator
  ///    (e.g. `llama3.2`, `phi4-mini`) → [ollama].
  /// 2. Extension match (case-insensitive).
  /// 3. Falls back to [unknown].
  ///
  /// ```dart
  /// ModelFormat.detect('qwen3-0.6b-q4_1.litertlm') // → litertlm
  /// ModelFormat.detect('model.gguf')                // → gguf
  /// ModelFormat.detect('llama3.2')                  // → ollama
  /// ModelFormat.detect('model.safetensors')         // → safetensors
  /// ```
  static ModelFormat detect(String urlOrPath) {
    // Strip query string and fragment
    final clean = urlOrPath.split('?').first.split('#').first.trim();

    // Try extension-based detection first.
    // If the extension matches a known format, return it immediately.
    // If it does NOT match (e.g. ".6b" in "qwen3-0.6b"), fall through to
    // the Ollama name check rather than returning `unknown`.
    final ext = _extension(clean).toLowerCase();
    if (ext.isNotEmpty) {
      final fromExt = switch (ext) {
        '.litertlm' => ModelFormat.litertlm,
        '.task' => ModelFormat.task,
        '.gguf' => ModelFormat.gguf,
        '.tflite' => ModelFormat.tflite,
        '.bin' => ModelFormat.binary,
        '.safetensors' => ModelFormat.safetensors,
        '.onnx' => ModelFormat.onnx,
        _ => null, // unrecognised extension — inspect further
      };
      if (fromExt != null) return fromExt;

      // Pure-letter extension (≥ 2 letters, e.g. ".xyz", ".pt", ".json"):
      // treat as a real but unsupported file type — return unknown immediately,
      // do NOT fall through to the Ollama name check.
      if (RegExp(r'^\.[a-zA-Z]{2,}$').hasMatch(ext)) {
        return ModelFormat.unknown;
      }
      // Mixed/numeric "extension" (e.g. ".6b" in "qwen3-0.6b", ".2:1b" in
      // "llama3.2:1b") — these are version suffixes, not real extensions.
      // Fall through to the Ollama name check below.
    }

    // No known file extension — check if this looks like an Ollama model name.
    // Ollama names never contain '/' (that would be a file path / URL segment).
    // Examples: "llama3.2", "phi4-mini", "qwen3:14b", "deepseek-r1:14b"
    if (!clean.contains('/') && _isOllamaName(clean)) {
      return ModelFormat.ollama;
    }

    return ModelFormat.unknown;
  }

  /// Infer [ModelFormat] from a HuggingFace repo+file pair.
  ///
  /// If [filename] is null, attempts to determine from the [repoId] hint
  /// (e.g. repos ending in `-GGUF` → [gguf]).
  static ModelFormat detectFromHF(String repoId, {String? filename}) {
    if (filename != null) return detect(filename);
    final lower = repoId.toLowerCase();
    if (lower.contains('gguf')) return ModelFormat.gguf;
    if (lower.contains('litertlm') || lower.contains('litert')) {
      return ModelFormat.litertlm;
    }
    // Default for litert-community org (known .litertlm publisher)
    if (lower.startsWith('litert-community/')) return ModelFormat.litertlm;
    return ModelFormat.unknown;
  }

  // ── Capability queries ────────────────────────────────────────────────────

  /// Whether this format can be run entirely on-device (no internet needed
  /// after the initial download).
  bool get isOnDevice => switch (this) {
        litertlm || task || gguf || tflite || binary || ollama => true,
        safetensors || hfInference || onnx || unknown => false,
      };

  /// Whether this format requires a network connection at inference time.
  bool get requiresCloud => !isOnDevice;

  /// Whether this format is supported on desktop (macOS, Windows, Linux).
  bool get supportsDesktop => switch (this) {
        litertlm || gguf || ollama || hfInference || safetensors => true,
        task || tflite || binary => false,
        onnx || unknown => false,
      };

  /// Whether this format is supported on Android.
  bool get supportsAndroid => switch (this) {
        litertlm || task || gguf || tflite || binary || hfInference => true,
        ollama || safetensors => false,
        onnx || unknown => false,
      };

  /// Whether this format is supported on iOS.
  bool get supportsIOS => switch (this) {
        litertlm || task || gguf || tflite || binary || hfInference => true,
        ollama || safetensors => false,
        onnx || unknown => false,
      };

  /// Human-readable display name.
  String get displayName => switch (this) {
        litertlm => 'LiteRT-LM (.litertlm)',
        task => 'MediaPipe Task (.task)',
        gguf => 'GGUF (.gguf)',
        tflite => 'TFLite (.tflite)',
        binary => 'Binary (.bin)',
        safetensors => 'SafeTensors (.safetensors)',
        onnx => 'ONNX (.onnx)',
        ollama => 'Ollama (local server)',
        hfInference => 'HF Inference API (cloud)',
        unknown => 'Unknown',
      };

  // ── Private helpers ───────────────────────────────────────────────────────

  static String _extension(String path) {
    final lastSlash = path.lastIndexOf('/');
    final filename = lastSlash >= 0 ? path.substring(lastSlash + 1) : path;
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    // Ignore extension if it looks like a version number (e.g. ".1", ".2")
    final ext = filename.substring(dot);
    if (RegExp(r'^\.\d+$').hasMatch(ext)) return '';
    return ext;
  }

  // Ollama model names: alphanumeric, hyphens, underscores, optional tag
  // Examples: llama3.2, phi4, gemma3:27b, qwen3-0.6b, deepseek-r1:14b
  static bool _isOllamaName(String s) {
    return RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._\-]*(:[a-zA-Z0-9._\-]+)?$')
        .hasMatch(s);
  }
}

/// Thrown when a model format is detected but is not runnable in the
/// current context (e.g. SafeTensors on-device, ONNX, or .task on desktop).
class UnsupportedFormatException implements Exception {
  final ModelFormat format;
  final String message;

  const UnsupportedFormatException(this.format, this.message);

  @override
  String toString() => 'UnsupportedFormatException(${format.displayName}): $message';
}
