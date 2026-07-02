/// Unit tests for [HFHub] URL construction and parsing.
///
/// Network-free tests only — URL construction and parsing are pure functions.
/// The live `modelInfo` / `listFiles` methods are tested in integration tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/src/hub/hf_hub.dart';
import 'package:flutter_agents/src/hub/model_format.dart';

void main() {
  // ── downloadUrl ──────────────────────────────────────────────────────────
  group('HFHub.downloadUrl', () {
    test('constructs correct CDN URL', () {
      final url = HFHub.downloadUrl(
          'litert-community/Qwen3-0.6B', 'qwen3-0.6b-q4_1.litertlm');
      expect(url,
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0.6b-q4_1.litertlm');
    });

    test('custom revision is included', () {
      final url = HFHub.downloadUrl(
        'owner/repo',
        'file.gguf',
        revision: 'v1.0',
      );
      expect(url, contains('/resolve/v1.0/'));
    });

    test('subdirectory filenames are preserved', () {
      final url =
          HFHub.downloadUrl('owner/repo', 'weights/shard-0001.safetensors');
      expect(url, endsWith('/weights/shard-0001.safetensors'));
    });
  });

  // ── inferenceUrl ─────────────────────────────────────────────────────────
  group('HFHub.inferenceUrl', () {
    test('constructs correct router URL', () {
      final url = HFHub.inferenceUrl('microsoft/Phi-4-mini-instruct');
      expect(url, contains('router.huggingface.co'));
      expect(url, contains('microsoft/Phi-4-mini-instruct'));
      expect(url, endsWith('/v1/chat/completions'));
    });
  });

  // ── parseUrl ─────────────────────────────────────────────────────────────
  group('HFHub.parseUrl', () {
    test('parses resolve URL', () {
      final result = HFHub.parseUrl(
          'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/qwen3-0.6b-q4_1.litertlm');
      expect(result, isNotNull);
      expect(result!.repoId, 'litert-community/Qwen3-0.6B');
      expect(result.filename, 'qwen3-0.6b-q4_1.litertlm');
      expect(result.revision, 'main');
    });

    test('parses blob URL', () {
      final result = HFHub.parseUrl(
          'https://huggingface.co/owner/repo/blob/main/model.gguf');
      expect(result, isNotNull);
      expect(result!.filename, 'model.gguf');
    });

    test('parses subdirectory path', () {
      final result = HFHub.parseUrl(
          'https://huggingface.co/owner/repo/resolve/main/weights/model.safetensors');
      expect(result!.filename, 'weights/model.safetensors');
    });

    test('returns null for non-HF URL', () {
      expect(
          HFHub.parseUrl('https://example.com/model.gguf'), isNull);
    });

    test('returns null for HF root URL (no file)', () {
      expect(
          HFHub.parseUrl('https://huggingface.co/owner/repo'), isNull);
    });
  });

  // ── HFFile ───────────────────────────────────────────────────────────────
  group('HFFile', () {
    test('format inferred from rfilename', () {
      expect(HFFile(rfilename: 'model.litertlm').format,
          ModelFormat.litertlm);
      expect(HFFile(rfilename: 'model.gguf').format, ModelFormat.gguf);
      expect(HFFile(rfilename: 'model.safetensors').format,
          ModelFormat.safetensors);
    });

    test('sizeDisplay shows MB for medium files', () {
      const f = HFFile(rfilename: 'model.gguf', size: 400 * 1024 * 1024);
      expect(f.sizeDisplay, contains('MB'));
    });

    test('sizeDisplay shows GB for large files', () {
      const f = HFFile(rfilename: 'model.gguf', size: 2500 * 1024 * 1024);
      expect(f.sizeDisplay, contains('GB'));
    });

    test('sizeDisplay shows "unknown size" when null', () {
      expect(const HFFile(rfilename: 'x').sizeDisplay, contains('unknown'));
    });
  });

  // ── HFModelInfo.recommendedFile ──────────────────────────────────────────
  group('HFModelInfo.recommendedFile', () {
    test('prefers .litertlm over .gguf', () {
      final info = HFModelInfo(
        modelId: 'test/repo',
        files: [
          const HFFile(rfilename: 'model.gguf', size: 400 * 1024 * 1024),
          const HFFile(
              rfilename: 'model.litertlm', size: 400 * 1024 * 1024),
        ],
      );
      expect(info.recommendedFile?.format, ModelFormat.litertlm);
    });

    test('prefers .gguf over .task', () {
      final info = HFModelInfo(
        modelId: 'test/repo',
        files: [
          const HFFile(rfilename: 'model.task'),
          const HFFile(rfilename: 'model.gguf'),
        ],
      );
      expect(info.recommendedFile?.format, ModelFormat.gguf);
    });

    test('picks smallest of multiple .gguf files', () {
      final info = HFModelInfo(
        modelId: 'test/repo',
        files: [
          const HFFile(rfilename: 'large-Q8.gguf', size: 800 * 1024 * 1024),
          const HFFile(rfilename: 'small-Q4.gguf', size: 400 * 1024 * 1024),
        ],
      );
      expect(info.recommendedFile?.rfilename, contains('small'));
    });

    test('returns null when only safetensors present', () {
      final info = HFModelInfo(
        modelId: 'test/repo',
        files: [
          const HFFile(rfilename: 'model.safetensors'),
        ],
      );
      expect(info.recommendedFile, isNull);
    });

    test('returns null for empty repo', () {
      expect(
        HFModelInfo(modelId: 'test/repo', files: const []).recommendedFile,
        isNull,
      );
    });
  });

  // ── HFModelInfo.runnableFiles ────────────────────────────────────────────
  group('HFModelInfo.runnableFiles', () {
    test('excludes safetensors and onnx', () {
      final info = HFModelInfo(
        modelId: 'test/repo',
        files: [
          const HFFile(rfilename: 'model.safetensors'),
          const HFFile(rfilename: 'model.onnx'),
          const HFFile(rfilename: 'model.gguf'),
          const HFFile(rfilename: 'model.litertlm'),
        ],
      );
      final runnable = info.runnableFiles;
      expect(runnable.length, 2);
      expect(runnable.map((f) => f.rfilename),
          containsAll(['model.gguf', 'model.litertlm']));
    });
  });

  // ── HFException ──────────────────────────────────────────────────────────
  group('HFException', () {
    test('toString includes status code and message', () {
      const e = HFException('not found', statusCode: 404);
      expect(e.toString(), contains('404'));
      expect(e.toString(), contains('not found'));
    });

    test('toString works without status code', () {
      const e = HFException('generic error');
      expect(e.toString(), contains('generic error'));
    });
  });
}
