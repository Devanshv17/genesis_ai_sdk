import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// LLM provider for Anthropic Claude models via REST API.
///
/// Supports Claude Haiku, Sonnet, and Opus families.
/// Works on all platforms including web.
///
/// ```dart
/// final provider = AnthropicProvider(
///   apiKey: 'YOUR_ANTHROPIC_KEY',
///   model: 'claude-haiku-4-5',  // fast + cheap
/// );
/// ```
///
/// Available models: claude-opus-4-5, claude-sonnet-4-5, claude-haiku-4-5
class AnthropicProvider extends LlmProvider {
  final String apiKey;
  final String model;
  final int maxTokens;

  static const _baseUrl = 'https://api.anthropic.com/v1';
  static const _anthropicVersion = '2023-06-01';

  AnthropicProvider({
    required this.apiKey,
    this.model = 'claude-haiku-4-5',
    this.maxTokens = 4096,
  });

  @override
  String get name => 'Anthropic ($model)';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _anthropicVersion,
      };

  // ── Message conversion ──────────────────────────────────────────────────

  /// Anthropic separates system prompt from messages and
  /// uses 'user' / 'assistant' roles only (no 'system' in messages array).
  Map<String, dynamic> _buildBody(
    List<Message> messages, {
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
    bool stream = false,
  }) {
    String? systemText;
    final converted = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case MessageRole.system:
          systemText = (systemText ?? '') + msg.content;
        case MessageRole.user:
          converted.add({'role': 'user', 'content': msg.content});
        case MessageRole.assistant:
          converted.add({'role': 'assistant', 'content': msg.content});
        case MessageRole.tool:
          // Tool results go as user messages with tool_result content blocks
          converted.add({
            'role': 'user',
            'content': [
              {
                'type': 'tool_result',
                'tool_use_id': msg.toolName ?? 'unknown',
                'content': msg.content,
              }
            ],
          });
      }
    }

    // Anthropic requires alternating user/assistant turns.
    // Merge consecutive same-role messages.
    final merged = _mergeConsecutive(converted);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'messages': merged,
      'temperature': temperature,
      if (stream) 'stream': true,
    };

    if (systemText != null) body['system'] = systemText;

    if (tools.isNotEmpty) {
      body['tools'] = tools
          .map((t) => {
                'name': t.name,
                'description': t.description,
                'input_schema': t.parameters,
              })
          .toList();
    }

    return body;
  }

  List<Map<String, dynamic>> _mergeConsecutive(
      List<Map<String, dynamic>> msgs) {
    if (msgs.isEmpty) return msgs;
    final result = <Map<String, dynamic>>[msgs.first];
    for (int i = 1; i < msgs.length; i++) {
      if (msgs[i]['role'] == result.last['role']) {
        // Same role — merge content
        final prev = result.last['content'];
        final curr = msgs[i]['content'];
        result.last['content'] =
            '${prev is String ? prev : prev.toString()}\n${curr is String ? curr : curr.toString()}';
      } else {
        result.add(msgs[i]);
      }
    }
    return result;
  }

  // ── complete ────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final body = _buildBody(messages, tools: tools, temperature: temperature);

    final response = await http.post(
      Uri.parse('$_baseUrl/messages'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw AnthropicException(
          'Anthropic API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseResponse(json);
  }

  ProviderResult _parseResponse(Map<String, dynamic> json) {
    final content = json['content'] as List?;
    if (content == null || content.isEmpty) {
      throw AnthropicException('Empty response from Anthropic');
    }

    for (final block in content) {
      if (block is Map && block['type'] == 'tool_use') {
        return ToolCallResult(ToolCall(
          toolName: block['name'] as String,
          arguments: (block['input'] as Map<String, dynamic>?) ?? {},
        ));
      }
    }

    final text = content
        .where((b) => b is Map && b['type'] == 'text')
        .map((b) => (b as Map)['text'] as String)
        .join();

    return TextResult(text.trim());
  }

  // ── stream ──────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final body =
        _buildBody(messages, temperature: temperature, stream: true);

    final request =
        http.Request('POST', Uri.parse('$_baseUrl/messages'));
    request.headers.addAll(_headers);
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) {
        final err = await streamed.stream.bytesToString();
        throw AnthropicException(
            'Stream error ${streamed.statusCode}: $err');
      }

      await for (final line in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]' || data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (json['type'] == 'content_block_delta') {
            final delta = json['delta'] as Map<String, dynamic>?;
            final token = delta?['text'] as String?;
            if (token != null && token.isNotEmpty) yield token;
          }
        } catch (_) {
          // Skip malformed SSE lines
        }
      }
    } finally {
      client.close();
    }
  }
}

class AnthropicException implements Exception {
  final String message;
  const AnthropicException(this.message);
  @override
  String toString() => 'AnthropicException: $message';
}
