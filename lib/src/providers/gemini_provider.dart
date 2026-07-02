import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// LLM provider for Google Gemini via REST API.
/// Works on all platforms including web.
///
/// Example:
/// ```dart
/// final provider = GeminiProvider(apiKey: 'YOUR_GEMINI_KEY');
/// ```
class GeminiProvider extends LlmProvider {
  final String apiKey;
  final String model;

  static const _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  GeminiProvider({
    required this.apiKey,
    this.model = 'gemini-2.0-flash',
  });

  @override
  String get name => 'Gemini ($model)';

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Convert our Message list to Gemini's `contents` + optional `systemInstruction`.
  Map<String, dynamic> _buildRequestBody(
    List<Message> messages, {
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) {
    String? systemText;
    final contents = <Map<String, dynamic>>[];

    for (final msg in messages) {
      switch (msg.role) {
        case MessageRole.system:
          systemText = msg.content;
        case MessageRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': msg.content}
            ],
          });
        case MessageRole.assistant:
          contents.add({
            'role': 'model',
            'parts': [
              {'text': msg.content}
            ],
          });
        case MessageRole.tool:
          // Tool response goes back as a user turn with functionResponse part
          contents.add({
            'role': 'user',
            'parts': [
              {
                'functionResponse': {
                  'name': msg.toolName,
                  'response': {'result': msg.content},
                }
              }
            ],
          });
      }
    }

    final body = <String, dynamic>{
      'contents': contents,
      'generationConfig': {
        'temperature': temperature,
      },
    };

    if (systemText != null) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemText}
        ]
      };
    }

    if (tools.isNotEmpty) {
      body['tools'] = [
        {
          'function_declarations': tools
              .map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'parameters': t.parameters,
                  })
              .toList(),
        }
      ];
      body['tool_config'] = {
        'function_calling_config': {'mode': 'AUTO'},
      };
    }

    return body;
  }

  Uri _uri(String endpoint) =>
      Uri.parse('$_baseUrl/$model:$endpoint?key=$apiKey');

  // ─── complete ───────────────────────────────────────────────────────────────

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final body = _buildRequestBody(messages, tools: tools, temperature: temperature);

    final response = await http.post(
      _uri('generateContent'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw GeminiException(
        'Gemini API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseResponse(json);
  }

  ProviderResult _parseResponse(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final blocked = json['promptFeedback']?['blockReason'];
      throw GeminiException('No candidates returned. Blocked: $blocked');
    }

    final parts = candidates[0]['content']['parts'] as List;

    // Check for function call
    for (final part in parts) {
      if (part is Map && part.containsKey('functionCall')) {
        final fc = part['functionCall'] as Map<String, dynamic>;
        return ToolCallResult(
          ToolCall(
            toolName: fc['name'] as String,
            arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
          ),
        );
      }
    }

    // Plain text response
    final text = parts
        .where((p) => p is Map && p.containsKey('text'))
        .map((p) => p['text'] as String)
        .join();

    return TextResult(text.trim());
  }

  // ─── stream ─────────────────────────────────────────────────────────────────

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final body = _buildRequestBody(messages, temperature: temperature);

    final request = http.Request('POST', _uri('streamGenerateContent'));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);

    final client = http.Client();
    try {
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw GeminiException(
            'Stream error ${streamedResponse.statusCode}: $errorBody');
      }

      // Gemini streams as a JSON array. We accumulate the full response and
      // track how far we've already scanned so that tokens split across HTTP
      // data events are never lost or double-counted.
      final buffer = StringBuffer();
      int offset = 0;
      final tokenRe = RegExp(r'"text":\s*"((?:[^"\\]|\\.)*)"');

      await for (final chunk
          in streamedResponse.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        final raw = buffer.toString();
        final matches = tokenRe.allMatches(raw, offset);
        for (final m in matches) {
          final token = m.group(1)!
              .replaceAll(r'\n', '\n')
              .replaceAll(r'\"', '"')
              .replaceAll(r'\\', '\\');
          if (token.isNotEmpty) yield token;
          offset = m.end;
        }
      }
    } finally {
      client.close();
    }
  }
}

class GeminiException implements Exception {
  final String message;
  const GeminiException(this.message);
  @override
  String toString() => 'GeminiException: $message';
}
