/// Unit tests for [UniversalModelManager].
///
/// Downloads are tested against a local HTTP server — no real network.
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/src/hub/model_format.dart';
import 'package:flutter_agents/src/hub/universal_model_manager.dart';
import 'package:flutter_agents/src/providers/gemma_provider.dart';
import 'package:flutter_agents/src/providers/ollama_provider.dart';

void main() {
  // ── isDownloaded / deleteModel ───────────────────────────────────────────
  group('UniversalModelManager file helpers', () {
    test('isDownloaded returns false for missing file', () async {
      expect(
        await UniversalModelManager.isDownloaded(
            '/tmp/__umm_nonexistent.litertlm'),
        isFalse,
      );
    });

    test('isDownloaded returns true for existing file', () async {
      final f = await File('/tmp/__umm_exists.litertlm').create();
      try {
        expect(await UniversalModelManager.isDownloaded(f.path), isTrue);
      } finally {
        await f.delete();
      }
    });

    test('deleteModel removes existing file', () async {
      final f = await File('/tmp/__umm_delete.litertlm').create();
      await UniversalModelManager.deleteModel(f.path);
      expect(await f.exists(), isFalse);
    });

    test('deleteModel is a no-op for missing file', () async {
      // Should complete without throwing
      await UniversalModelManager.deleteModel('/tmp/__umm_no_file.litertlm');
    });
  });

  // ── providerForFile ──────────────────────────────────────────────────────
  group('UniversalModelManager.providerForFile', () {
    test('.litertlm → GemmaProvider', () {
      final p = UniversalModelManager.providerForFile(
          '/models/qwen3.litertlm');
      expect(p, isA<GemmaProvider>());
    });

    test('.task → GemmaProvider', () {
      final p = UniversalModelManager.providerForFile(
          '/models/gemma3n.task');
      expect(p, isA<GemmaProvider>());
    });

    test('.tflite → GemmaProvider', () {
      final p = UniversalModelManager.providerForFile(
          '/models/smollm.tflite');
      expect(p, isA<GemmaProvider>());
    });

    test('.bin → GemmaProvider', () {
      final p = UniversalModelManager.providerForFile(
          '/models/model.bin');
      expect(p, isA<GemmaProvider>());
    });

    test('ollama name → OllamaProvider', () {
      final p = UniversalModelManager.providerForFile('llama3.2');
      expect(p, isA<OllamaProvider>());
    });

    test('.safetensors → UnsupportedFormatException', () {
      expect(
        () => UniversalModelManager.providerForFile('model.safetensors'),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('.onnx → UnsupportedFormatException', () {
      expect(
        () => UniversalModelManager.providerForFile('model.onnx'),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('.gguf → UnsupportedError (with LlamaCppProvider hint)', () {
      expect(
        () => UniversalModelManager.providerForFile('model.gguf'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('.gguf error message mentions LlamaCppProvider', () {
      try {
        UniversalModelManager.providerForFile('model.gguf');
        fail('should throw');
      } on UnsupportedError catch (e) {
        expect(e.message, contains('LlamaCppProvider'));
      }
    });

    test('.safetensors error message mentions HFInferenceProvider', () {
      try {
        UniversalModelManager.providerForFile('model.safetensors');
        fail('should throw');
      } on UnsupportedFormatException catch (e) {
        expect(e.message.toLowerCase(),
            anyOf(contains('hfinferenceprovider'), contains('cloud')));
      }
    });

    test('.safetensors error message mentions GGUF conversion', () {
      try {
        UniversalModelManager.providerForFile('model.safetensors');
        fail('should throw');
      } on UnsupportedFormatException catch (e) {
        expect(e.message, contains('gguf'));
      }
    });

    test('custom modelId is passed to GemmaProvider', () {
      final p = UniversalModelManager.providerForFile(
        '/models/qwen3.litertlm',
        modelId: 'qwen3-0.6b',
      );
      expect(p.name, contains('qwen3-0.6b'));
    });
  });

  // ── downloadFromUrl — local HTTP server ──────────────────────────────────
  group('UniversalModelManager.downloadFromUrl (local server)', () {
    late HttpServer server;
    late String baseUrl;
    const content = 'FAKE_GGUF_MODEL_DATA';

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://localhost:${server.port}';

      server.listen((req) async {
        if (req.uri.path == '/model.gguf') {
          final bytes = content.codeUnits;
          req.response
            ..statusCode = 200
            ..headers.set(HttpHeaders.contentLengthHeader, bytes.length)
            ..add(bytes);
          await req.response.close();
        } else if (req.uri.path == '/no-length') {
          req.response
            ..statusCode = 200
            ..add(content.codeUnits);
          await req.response.close();
        } else if (req.uri.path == '/auth') {
          final auth = req.headers.value('authorization');
          if (auth == 'Bearer mytoken') {
            req.response
              ..statusCode = 200
              ..add(content.codeUnits);
          } else {
            req.response.statusCode = 401;
          }
          await req.response.close();
        } else if (req.uri.path == '/forbidden') {
          req.response.statusCode = 403;
          await req.response.close();
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
    });

    tearDown(() => server.close(force: true));

    test('downloads file with correct content', () async {
      const dest = '/tmp/__umm_dl.gguf';
      try {
        await UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/model.gguf', destinationPath: dest);
        expect(await File(dest).readAsString(), content);
      } finally {
        await UniversalModelManager.deleteModel(dest);
      }
    });

    test('onProgress called with correct byte counts', () async {
      const dest = '/tmp/__umm_progress.gguf';
      final calls = <(int, int)>[];
      try {
        await UniversalModelManager.downloadFromUrl(
          url: '$baseUrl/model.gguf',
          destinationPath: dest,
          onProgress: (r, t) => calls.add((r, t)),
        );
        expect(calls, isNotEmpty);
        expect(calls.last.$1, content.length);
      } finally {
        await UniversalModelManager.deleteModel(dest);
      }
    });

    test('total is -1 when no Content-Length', () async {
      const dest = '/tmp/__umm_nolen.gguf';
      final totals = <int>[];
      try {
        await UniversalModelManager.downloadFromUrl(
          url: '$baseUrl/no-length',
          destinationPath: dest,
          onProgress: (r, t) => totals.add(t),
        );
        expect(totals.every((t) => t == -1), isTrue);
      } finally {
        await UniversalModelManager.deleteModel(dest);
      }
    });

    test('throws ModelDownloadException on 401', () async {
      expect(
        () => UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/auth',
            destinationPath: '/tmp/__umm_401.gguf'),
        throwsA(isA<ModelDownloadException>()),
      );
    });

    test('401 error message mentions HF_TOKEN', () async {
      try {
        await UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/auth',
            destinationPath: '/tmp/__umm_401b.gguf');
        fail('should throw');
      } on ModelDownloadException catch (e) {
        expect(e.message, contains('HF_TOKEN'));
      }
    });

    test('throws ModelDownloadException on 403', () async {
      expect(
        () => UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/forbidden',
            destinationPath: '/tmp/__umm_403.gguf'),
        throwsA(isA<ModelDownloadException>()),
      );
    });

    test('403 error message mentions license', () async {
      try {
        await UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/forbidden',
            destinationPath: '/tmp/__umm_403b.gguf');
        fail('should throw');
      } on ModelDownloadException catch (e) {
        expect(e.message.toLowerCase(), contains('license'));
      }
    });

    test('explicit hfToken is attached for any domain', () async {
      const dest = '/tmp/__umm_token.gguf';
      try {
        await UniversalModelManager.downloadFromUrl(
          url: '$baseUrl/auth',
          destinationPath: dest,
          hfToken: 'mytoken',
        );
        expect(await File(dest).readAsString(), content);
      } finally {
        await UniversalModelManager.deleteModel(dest);
      }
    });

    test('creates parent directory automatically', () async {
      const dest = '/tmp/__umm_subdir/nested/model.gguf';
      try {
        await UniversalModelManager.downloadFromUrl(
            url: '$baseUrl/model.gguf', destinationPath: dest);
        expect(await File(dest).exists(), isTrue);
      } finally {
        await Directory('/tmp/__umm_subdir').delete(recursive: true);
      }
    });
  });
}
