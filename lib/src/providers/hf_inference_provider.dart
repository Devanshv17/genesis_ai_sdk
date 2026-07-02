/// Cloud inference for any HuggingFace model via the HF Inference Router
/// (OpenAI-compatible `/v1/chat/completions` endpoint).
///
/// This provider requires no model download — inference runs on HF's
/// GPU fleet (or a third-party provider like Featherless, Nebius, Together).
///
/// ```dart
/// final provider = HFInferenceProvider(
///   modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
///   apiToken: 'hf_xxxx',  // or set HF_TOKEN env var
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

// ── Backend enum ─────────────────────────────────────────────────────────────

/// The inference backend used by [HFInferenceProvider] via the HF router.
///
/// The HF router (`router.huggingface.co`) proxies requests to multiple GPU
/// providers. Different backends support different sets of models.
///
/// | Backend | URL pattern | Best for |
/// |---------|-------------|---------|
/// | [featherless] | `…/featherless-ai/v1/…` | Most public HF models; **default** |
/// | [nebius] | `…/nebius/v1/…` | Larger / quantised models |
/// | [together] | `…/together/v1/…` | Llama, Mixtral, popular OSS |
/// | [sambanova] | `…/sambanova/v1/…` | Very fast Llama inference |
/// | [hfNative] | `…/hf-inference/models/{id}/v1/…` | HF's own servers (limited models) |
enum HFInferenceBackend {
  /// Featherless AI — broadest public-model coverage; **recommended default**.
  featherless,

  /// Nebius AI Studio — good for quantised / large models.
  nebius,

  /// Together AI — Llama, Mistral, Mixtral, and popular open-source models.
  together,

  /// SambaNova — extremely fast Llama family inference.
  sambanova,

  /// HF's own serverless inference — limited to a small curated model list.
  /// Use only when you know your model is on that list.
  hfNative,
}

// ── Provider ─────────────────────────────────────────────────────────────────

/// Cloud provider that runs any HuggingFace model via the HF Inference Router.
///
/// ## When to use
/// | Scenario | Recommendation |
/// |----------|---------------|
/// | SafeTensors model (no GGUF / litertlm conversion) | ✅ Use this |
/// | Try a model before downloading | ✅ Use this |
/// | Production with strict privacy requirements | ❌ Data leaves the device |
/// | No internet / airplane mode | ❌ Requires network |
///
/// ## Choosing a backend
/// The default backend is [HFInferenceBackend.featherless] which supports
/// virtually all public HF models. Switch to [HFInferenceBackend.hfNative]
/// only if you need HF's own GPU fleet and your model is in their curated list.
///
/// ## Quick start
/// ```dart
/// // Any model on HuggingFace — no download needed:
/// final provider = HFInferenceProvider(
///   modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
///   apiToken: 'hf_xxxx',
/// );
/// final agent = AgenticHub.fromProvider(provider: provider);
/// final reply = await agent.chat('Explain gravity in one sentence.');
/// ```
///
/// ## Free tier
/// All backends support free-tier usage with a valid HF token.
/// Rate limits apply; pass a Pro-tier token for higher throughput.
class HFInferenceProvider extends LlmProvider {
  /// The HuggingFace model ID, e.g. `"Qwen/Qwen2.5-0.5B-Instruct"`.
  final String modelId;

  /// HuggingFace API token. If null, reads from `HF_TOKEN` or
  /// `HUGGINGFACE_TOKEN` environment variable.
  final String? apiToken;

  /// Maximum tokens to generate per response.
  final int maxTokens;

  /// Request timeout. Default 120 s — large models may need more.
  final Duration timeout;

  /// Which inference backend to use. Defaults to [HFInferenceBackend.featherless]
  /// which has the broadest model support.
  final HFInferenceBackend backend;

  HFInferenceProvider({
    required this.modelId,
    this.apiToken,
    this.maxTokens = 1024,
    this.timeout = const Duration(seconds: 120),
    this.backend = HFInferenceBackend.featherless,
  });

  @override
  String get name => 'HFInference($modelId)';

  // ── complete ──────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final body = <String, dynamic>{
      'model': modelId,
      'messages': _convertMessages(messages),
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': false,
    };
    if (tools.isNotEmpty) body['tools'] = _convertTools(tools);

    final response = await http
        .post(
          Uri.parse(_endpointUrl()),
          headers: _headers(),
          body: jsonEncode(body),
        )
        .timeout(timeout);

    _checkStatus(response);

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return TextResult('');

    final choice = choices.first as Map<String, dynamic>;
    final msg = choice['message'] as Map<String, dynamic>?;

    // Tool call?
    final toolCalls = msg?['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      final tc = toolCalls.first as Map<String, dynamic>;
      final fn = tc['function'] as Map<String, dynamic>;
      final argsRaw = fn['arguments'];
      final args = argsRaw is String
          ? jsonDecode(argsRaw) as Map<String, dynamic>
          : (argsRaw as Map<String, dynamic>?) ?? {};
      return ToolCallResult(
          ToolCall(toolName: fn['name'] as String, arguments: args));
    }

    return TextResult((msg?['content'] as String? ?? '').trim());
  }

  // ── stream ────────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final body = jsonEncode({
      'model': modelId,
      'messages': _convertMessages(messages),
      'max_tokens': maxTokens,
      'temperature': temperature,
      'stream': true,
    });

    final request = http.Request('POST', Uri.parse(_endpointUrl()));
    request.headers.addAll(_headers());
    request.body = body;

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(timeout);
      _checkStreamedStatus(streamed);

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final delta =
              (json['choices'] as List?)?.firstOrNull as Map<String, dynamic>?;
          final content =
              (delta?['delta'] as Map<String, dynamic>?)?['content'] as String?;
          if (content != null && content.isNotEmpty) yield content;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// Build the correct `/v1/chat/completions` URL for the chosen backend.
  ///
  /// Most providers use `https://router.huggingface.co/{provider}/v1/…`
  /// and the model is specified in the JSON body.
  ///
  /// The legacy `hf-inference` provider uses a different path where the
  /// model ID is embedded in the URL.
  String _endpointUrl() {
    const base = 'https://router.huggingface.co';
    return switch (backend) {
      HFInferenceBackend.featherless =>
        '$base/featherless-ai/v1/chat/completions',
      HFInferenceBackend.nebius => '$base/nebius/v1/chat/completions',
      HFInferenceBackend.together => '$base/together/v1/chat/completions',
      HFInferenceBackend.sambanova => '$base/sambanova/v1/chat/completions',
      // hfNative embeds the model ID in the URL path
      HFInferenceBackend.hfNative =>
        '$base/hf-inference/models/$modelId/v1/chat/completions',
    };
  }

  Map<String, String> _headers() {
    final token = apiToken ?? _envToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static String? _envToken() {
    if (kIsWeb) return null;
    return Platform.environment['HF_TOKEN'] ??
        Platform.environment['HUGGINGFACE_TOKEN'];
  }

  List<Map<String, dynamic>> _convertMessages(List<Message> messages) =>
      messages
          .map((m) => {
                'role': switch (m.role) {
                  MessageRole.system => 'system',
                  MessageRole.user => 'user',
                  MessageRole.assistant => 'assistant',
                  MessageRole.tool => 'tool',
                },
                'content': m.content,
              })
          .toList();

  List<Map<String, dynamic>> _convertTools(List<AgenticTool> tools) =>
      tools
          .map((t) => {
                'type': 'function',
                'function': {
                  'name': t.name,
                  'description': t.description,
                  'parameters': t.parameters,
                },
              })
          .toList();

  void _checkStatus(http.Response res) {
    if (res.statusCode == 200) return;
    _throwForStatus(res.statusCode, res.body);
  }

  void _checkStreamedStatus(http.StreamedResponse res) {
    if (res.statusCode == 200) return;
    _throwForStatus(res.statusCode, 'stream start');
  }

  void _throwForStatus(int code, String body) {
    if (code == 401) {
      throw HFInferenceException(
        'HTTP 401: Missing or invalid HF token for "$modelId".\n'
        'Set HF_TOKEN env var or pass apiToken: "hf_xxxx".\n'
        'Get a free token at https://huggingface.co/settings/tokens',
      );
    }
    if (code == 403) {
      throw HFInferenceException(
        'HTTP 403: Access denied for "$modelId".\n'
        'Accept the model license on huggingface.co and use a valid token.',
      );
    }
    if (code == 422) {
      throw HFInferenceException(
        'HTTP 422: Model "$modelId" is not supported by the '
        '${backend.name} backend.\n'
        'Try a different HFInferenceBackend, e.g. HFInferenceBackend.featherless.',
      );
    }
    if (code == 503) {
      throw HFInferenceException(
        'HTTP 503: Model "$modelId" is loading on ${backend.name}. '
        'Wait ~20 s and retry.',
      );
    }
    throw HFInferenceException(
        'HTTP $code from HF Inference Router (${backend.name}): $body');
  }
}

/// Thrown when the HF Inference Router returns an error.
class HFInferenceException implements Exception {
  final String message;
  const HFInferenceException(this.message);
  @override
  String toString() => 'HFInferenceException: $message';
}
