/// Unit tests for [ModelFormat] detection and capability queries.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/src/hub/model_format.dart';

void main() {
  // ── detect() from extension ─────────────────────────────────────────────
  group('ModelFormat.detect — extension', () {
    test('.litertlm → litertlm', () {
      expect(ModelFormat.detect('model.litertlm'), ModelFormat.litertlm);
      expect(ModelFormat.detect('/some/path/qwen3-0.6b-q4_1.litertlm'),
          ModelFormat.litertlm);
    });

    test('.task → task', () {
      expect(ModelFormat.detect('gemma-3n.task'), ModelFormat.task);
    });

    test('.gguf → gguf', () {
      expect(ModelFormat.detect('Qwen3-0.6B-Q4_K_M.gguf'), ModelFormat.gguf);
      expect(
          ModelFormat.detect(
              'https://huggingface.co/bartowski/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf'),
          ModelFormat.gguf);
    });

    test('.tflite → tflite', () {
      expect(ModelFormat.detect('model.tflite'), ModelFormat.tflite);
    });

    test('.bin → binary', () {
      expect(ModelFormat.detect('model.bin'), ModelFormat.binary);
    });

    test('.safetensors → safetensors', () {
      expect(ModelFormat.detect('model.safetensors'), ModelFormat.safetensors);
    });

    test('.onnx → onnx', () {
      expect(ModelFormat.detect('model.onnx'), ModelFormat.onnx);
    });

    test('unknown extension → unknown', () {
      expect(ModelFormat.detect('model.xyz'), ModelFormat.unknown);
      expect(ModelFormat.detect('model.pt'), ModelFormat.unknown);
    });

    test('strips query string before detecting', () {
      expect(
        ModelFormat.detect(
            'https://cdn.example.com/model.gguf?token=abc&rev=main'),
        ModelFormat.gguf,
      );
    });

    test('strips fragment before detecting', () {
      expect(
        ModelFormat.detect('model.litertlm#some-fragment'),
        ModelFormat.litertlm,
      );
    });

    test('case-insensitive extension matching', () {
      expect(ModelFormat.detect('model.GGUF'), ModelFormat.gguf);
      expect(ModelFormat.detect('model.LiteRtLm'), ModelFormat.litertlm);
    });
  });

  // ── detect() Ollama names ────────────────────────────────────────────────
  group('ModelFormat.detect — Ollama names', () {
    test('simple model names → ollama', () {
      expect(ModelFormat.detect('llama3.2'), ModelFormat.ollama);
      expect(ModelFormat.detect('phi4'), ModelFormat.ollama);
      expect(ModelFormat.detect('qwen3'), ModelFormat.ollama);
    });

    test('model:tag pattern → ollama', () {
      expect(ModelFormat.detect('gemma3:27b'), ModelFormat.ollama);
      expect(ModelFormat.detect('llama3.2:1b'), ModelFormat.ollama);
      expect(ModelFormat.detect('deepseek-r1:14b'), ModelFormat.ollama);
    });

    test('model with hyphen → ollama', () {
      expect(ModelFormat.detect('phi4-mini'), ModelFormat.ollama);
      expect(ModelFormat.detect('qwen3-0.6b'), ModelFormat.ollama);
    });
  });

  // ── detectFromHF ─────────────────────────────────────────────────────────
  group('ModelFormat.detectFromHF', () {
    test('filename given — uses file extension', () {
      expect(
        ModelFormat.detectFromHF('owner/repo',
            filename: 'model.litertlm'),
        ModelFormat.litertlm,
      );
      expect(
        ModelFormat.detectFromHF('owner/repo', filename: 'model.gguf'),
        ModelFormat.gguf,
      );
    });

    test('no filename — litert-community org → litertlm', () {
      expect(
        ModelFormat.detectFromHF('litert-community/Qwen3-0.6B'),
        ModelFormat.litertlm,
      );
    });

    test('no filename — GGUF repo hint', () {
      expect(
        ModelFormat.detectFromHF('bartowski/Qwen3-0.6B-GGUF'),
        ModelFormat.gguf,
      );
    });

    test('no filename — unknown repo → unknown', () {
      expect(
        ModelFormat.detectFromHF('some/random-repo'),
        ModelFormat.unknown,
      );
    });
  });

  // ── isOnDevice / requiresCloud ───────────────────────────────────────────
  group('ModelFormat capability: isOnDevice', () {
    test('on-device formats', () {
      for (final fmt in [
        ModelFormat.litertlm,
        ModelFormat.task,
        ModelFormat.gguf,
        ModelFormat.tflite,
        ModelFormat.binary,
        ModelFormat.ollama,
      ]) {
        expect(fmt.isOnDevice, isTrue, reason: '${fmt.name} should be on-device');
      }
    });

    test('cloud-only formats', () {
      for (final fmt in [
        ModelFormat.safetensors,
        ModelFormat.hfInference,
        ModelFormat.onnx,
      ]) {
        expect(fmt.requiresCloud, isTrue,
            reason: '${fmt.name} should require cloud');
      }
    });
  });

  // ── platform support ─────────────────────────────────────────────────────
  group('ModelFormat platform support', () {
    test('litertlm supports all platforms', () {
      expect(ModelFormat.litertlm.supportsDesktop, isTrue);
      expect(ModelFormat.litertlm.supportsAndroid, isTrue);
      expect(ModelFormat.litertlm.supportsIOS, isTrue);
    });

    test('task is mobile-only', () {
      expect(ModelFormat.task.supportsDesktop, isFalse);
      expect(ModelFormat.task.supportsAndroid, isTrue);
      expect(ModelFormat.task.supportsIOS, isTrue);
    });

    test('gguf supports all', () {
      expect(ModelFormat.gguf.supportsDesktop, isTrue);
      expect(ModelFormat.gguf.supportsAndroid, isTrue);
      expect(ModelFormat.gguf.supportsIOS, isTrue);
    });

    test('ollama is desktop-only', () {
      expect(ModelFormat.ollama.supportsDesktop, isTrue);
      expect(ModelFormat.ollama.supportsAndroid, isFalse);
      expect(ModelFormat.ollama.supportsIOS, isFalse);
    });
  });

  // ── displayName ──────────────────────────────────────────────────────────
  group('ModelFormat.displayName', () {
    test('all formats have non-empty displayName', () {
      for (final fmt in ModelFormat.values) {
        expect(fmt.displayName, isNotEmpty,
            reason: '${fmt.name} should have a displayName');
      }
    });

    test('litertlm name includes extension', () {
      expect(ModelFormat.litertlm.displayName, contains('.litertlm'));
    });

    test('gguf name includes extension', () {
      expect(ModelFormat.gguf.displayName, contains('.gguf'));
    });
  });

  // ── UnsupportedFormatException ───────────────────────────────────────────
  group('UnsupportedFormatException', () {
    test('toString includes format and message', () {
      const e = UnsupportedFormatException(
          ModelFormat.safetensors, 'cannot run on-device');
      expect(e.toString(), contains('safetensors'));
      expect(e.toString(), contains('cannot run on-device'));
    });

    test('is an Exception', () {
      expect(
          const UnsupportedFormatException(ModelFormat.onnx, 'x'),
          isA<Exception>());
    });
  });
}
