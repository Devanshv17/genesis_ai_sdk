import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// LLM provider for OpenAI (GPT-4o, GPT-4o-mini, etc.) via REST API.
/// Works on all platforms including web.
///
/// Example:
/// ```dart
/// final provider = OpenAIProvider(apiKey: 'YOUR_OPENAI_KEY');
/// ```
class OpenAIProvider extends LlmProvider {
  final String apiKey;
  final String model;
  final String baseUrl;

  OpenAIProvider({
    required this.apiKey,
    this.model = 'gpt-4o-mini',
    this.baseUrl = 'https://api.openai.com/v1',
  });

  @override
  String get name => 'OpenAI ($model)';

  Map<String, dynamic> _roleString(MessageRole role) => switch (role) {
        MessageRole.system => {'role': 'system'},
        MessageRole.user => {'role': 'user'},
        MessageRole.assistant => {'role': 'assistant'},
        MessageRole.tool => {'role': 'tool'},
      };

  List<Map<String, dynamic>> _buildMessages(List<Message> messages) {
    return messages.map((msg) {
      final base = _roleString(msg.role);
      if (msg.role == MessageRole.tool) {
        return {
          ...base,
          'tool_call_id': msg.toolName ?? 'unknown',
          'content': msg.content,
        };
      }
      return {...base, 'content': msg.content};
    }).toList();
  }

  List<Map<String, dynamic>> _buildTools(List<AgenticTool> tools) {
    return tools
        .map((t) => {
              'type': 'function',
              'function': {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            })
        .toList();
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      };

  // ─── complete ───────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'messages': _buildMessages(messages),
      'temperature': temperature,
    };
    if (tools.isNotEmpty) {
      body['tools'] = _buildTools(tools);
      body['tool_choice'] = 'auto';
    }

    final response = await http.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: _headers,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw OpenAIException(
          'OpenAI API error ${response.statusCode}: ${response.body}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choice = (json['choices'] as List).first as Map<String, dynamic>;
    final message = choice['message'] as Map<String, dynamic>;

    // Tool call?
    final toolCalls = message['tool_calls'] as List?;
    if (toolCalls != null && toolCalls.isNotEmpty) {
      final tc = toolCalls.first as Map<String, dynamic>;
      final fn = tc['function'] as Map<String, dynamic>;
      return ToolCallResult(
        ToolCall(
          toolName: fn['name'] as String,
          arguments: jsonDecode(fn['arguments'] as String)
              as Map<String, dynamic>,
        ),
      );
    }

    return TextResult((message['content'] as String? ?? '').trim());
  }

  // ─── stream ─────────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final body = jsonEncode({
      'model': model,
      'messages': _buildMessages(messages),
      'temperature': temperature,
      'stream': true,
    });

    final request = http.Request('POST', Uri.parse('$baseUrl/chat/completions'));
    request.headers.addAll(_headers);
    request.body = body;

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request);
      if (streamedResponse.statusCode != 200) {
        final err = await streamedResponse.stream.bytesToString();
        throw OpenAIException('Stream error ${streamedResponse.statusCode}: $err');
      }

      await for (final line in streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;

        final json = jsonDecode(data) as Map<String, dynamic>;
        final delta =
            (json['choices'] as List?)?.firstOrNull?['delta'] as Map?;
        final token = delta?['content'] as String?;
        if (token != null && token.isNotEmpty) yield token;
      }
    } finally {
      client.close();
    }
  }
}

class OpenAIException implements Exception {
  final String message;
  const OpenAIException(this.message);
  @override
  String toString() => 'OpenAIException: $message';
}
