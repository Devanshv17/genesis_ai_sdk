import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// LLM provider for [Ollama](https://ollama.ai) — a local model server.
///
/// Ollama runs on the same machine (or LAN) and exposes an OpenAI-compatible
/// REST API. Best for **desktop apps** (macOS, Windows, Linux) where the dev
/// or user already has Ollama installed.
///
/// ## Setup for developers
/// 1. Install Ollama: https://ollama.ai
/// 2. Pull a model: `ollama pull llama3.2` or `ollama pull phi4`
/// 3. Ollama starts automatically — no extra config.
///
/// ```dart
/// final provider = OllamaProvider(model: 'llama3.2');
/// // or on a different host:
/// final provider = OllamaProvider(
///   model: 'phi4',
///   baseUrl: 'http://192.168.1.5:11434',  // LAN machine
/// );
/// ```
///
/// Popular models: llama3.2, llama3.2:1b, phi4, phi4-mini,
///                 mistral, gemma3, deepseek-r1, qwen3
class OllamaProvider extends LlmProvider {
  final String model;
  final String baseUrl;
  final Duration timeout;

  OllamaProvider({
    this.model = 'llama3.2',
    this.baseUrl = 'http://localhost:11434',
    this.timeout = const Duration(seconds: 120),
  });

  @override
  String get name => 'Ollama ($model)';

  // Ollama's /api/chat uses OpenAI-style messages + tools
  List<Map<String, dynamic>> _convertMessages(List<Message> messages) =>
      messages.map((m) {
        if (m.role == MessageRole.tool) {
          return {
            'role': 'tool',
            'content': m.content,
            'tool_call_id': m.toolName ?? 'unknown',
          };
        }
        return {
          'role': switch (m.role) {
            MessageRole.system => 'system',
            MessageRole.user => 'user',
            MessageRole.assistant => 'assistant',
            MessageRole.tool => 'tool',
          },
          'content': m.content,
        };
      }).toList();

  List<Map<String, dynamic>> _convertTools(List<AgenticTool> tools) =>
      tools.map((t) => {
            'type': 'function',
            'function': {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            },
          }).toList();

  // ── complete ────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': _convertMessages(messages),
      'stream': false,
      'options': {'temperature': temperature},
    };
    if (tools.isNotEmpty) body['tools'] = _convertTools(tools);

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$baseUrl/api/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on Exception catch (e) {
      throw OllamaException(
          'Could not reach Ollama at $baseUrl. '
          'Is Ollama running? ($e)');
    }

    if (response.statusCode != 200) {
      throw OllamaException(
          'Ollama error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final message = json['message'] as Map<String, dynamic>?;

    // Tool call?
    final toolCalls = message?['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      final tc = toolCalls.first as Map<String, dynamic>;
      final fn = tc['function'] as Map<String, dynamic>;
      final argsRaw = fn['arguments'];
      final args = argsRaw is String
          ? jsonDecode(argsRaw) as Map<String, dynamic>
          : (argsRaw as Map<String, dynamic>?) ?? {};
      return ToolCallResult(ToolCall(toolName: fn['name'] as String, arguments: args));
    }

    return TextResult((message?['content'] as String? ?? '').trim());
  }

  // ── stream ──────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final body = jsonEncode({
      'model': model,
      'messages': _convertMessages(messages),
      'stream': true,
      'options': {'temperature': temperature},
    });

    final request = http.Request('POST', Uri.parse('$baseUrl/api/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(timeout);
      if (streamed.statusCode != 200) {
        final err = await streamed.stream.bytesToString();
        throw OllamaException('Stream error ${streamed.statusCode}: $err');
      }

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final token =
              (json['message'] as Map<String, dynamic>?)?['content'] as String?;
          if (token != null && token.isNotEmpty) yield token;
          if (json['done'] == true) break;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  /// Pull (download) the model from the Ollama registry if not yet present.
  ///
  /// Equivalent to running `ollama pull <model>` on the command line.
  /// [onProgress] fires with `(downloadedBytes, totalBytes)`.
  ///
  /// Throws [OllamaException] if the server is unreachable or the pull fails.
  Future<void> pull({
    void Function(int received, int total)? onProgress,
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
        throw OllamaException('Pull failed (HTTP ${streamed.statusCode}): $body');
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

  /// List all models currently available in this Ollama instance.
  Future<List<String>> listModels() async {
    try {
      final res = await http
          .get(Uri.parse('$baseUrl/api/tags'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return const [];
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return (json['models'] as List? ?? [])
          .map((m) => (m as Map)['name'] as String)
          .toList();
    } on Exception {
      return const [];
    }
  }

  /// Checks whether the Ollama server is reachable and the model is available.
  ///
  /// Returns a [OllamaStatus] with details.
  Future<OllamaStatus> checkStatus() async {
    try {
      final res =
          await http.get(Uri.parse('$baseUrl/api/tags')).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        return OllamaStatus(reachable: false, reason: 'HTTP ${res.statusCode}');
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final models = (json['models'] as List?)
              ?.map((m) => (m as Map)['name'] as String)
              .toList() ??
          [];
      final modelPulled = models.any((m) => m.startsWith(model));
      return OllamaStatus(
        reachable: true,
        modelAvailable: modelPulled,
        availableModels: models,
        reason: modelPulled
            ? 'Ready'
            : 'Model "$model" not found. Run: ollama pull $model',
      );
    } on Exception catch (e) {
      return OllamaStatus(
        reachable: false,
        reason: 'Cannot connect to Ollama at $baseUrl. '
            'Install from https://ollama.ai and run: ollama serve\n($e)',
      );
    }
  }
}

class OllamaStatus {
  final bool reachable;
  final bool modelAvailable;
  final List<String> availableModels;
  final String reason;

  const OllamaStatus({
    required this.reachable,
    this.modelAvailable = false,
    this.availableModels = const [],
    required this.reason,
  });

  bool get isReady => reachable && modelAvailable;
}

class OllamaException implements Exception {
  final String message;
  const OllamaException(this.message);
  @override
  String toString() => 'OllamaException: $message';
}
