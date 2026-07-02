import 'dart:convert';
import 'package:http/http.dart' as http;
import '../agentic_tool.dart';
import '../tool_param.dart';

/// Makes HTTP GET or POST requests and returns the response body.
///
/// Useful for agents that need to fetch live data from any REST API.
/// Response body is auto-parsed as JSON if the Content-Type is application/json.
///
/// **Security note:** Only use this tool with trusted agents.
/// Consider an allowlist of permitted domains via [HttpTool.allowedDomains].
///
/// Usage:
/// ```dart
/// tools: [AgenticTools.httpGet]
///
/// // With domain restriction:
/// tools: [HttpTool(allowedDomains: ['api.openweathermap.org', 'api.github.com'])]
/// ```
class HttpTool {
  /// Restricts requests to these domains only.
  /// If empty, all domains are permitted.
  final List<String> allowedDomains;

  /// Maximum response body size in bytes. Default 512KB.
  final int maxResponseBytes;

  /// Request timeout. Default 10 seconds.
  final Duration timeout;

  const HttpTool({
    this.allowedDomains = const [],
    this.maxResponseBytes = 524288,
    this.timeout = const Duration(seconds: 10),
  });

  AgenticTool get tool => AgenticTool.define(
        name: 'http_request',
        description:
            'Makes an HTTP GET or POST request to a URL and returns the response. '
            'Use for fetching live data from APIs, web pages, or services.',
        params: {
          'url': ToolParam.string(
            description: 'The full URL to request, including query params.',
            required: true,
          ),
          'method': ToolParam.stringEnum(
            ['GET', 'POST'],
            description: 'HTTP method. Defaults to GET.',
          ),
          'body': ToolParam.string(
            description: 'Request body for POST requests (JSON string).',
          ),
          'headers': ToolParam.string(
            description:
                'Optional JSON object of request headers, '
                'e.g. {"Authorization": "Bearer TOKEN"}',
          ),
        },
        execute: _execute,
      );

  Future<Map<String, dynamic>> _execute(Map<String, dynamic> args) async {
    final rawUrl = args['url'] as String;
    final method = (args['method'] as String? ?? 'GET').toUpperCase();

    // Domain allowlist check
    if (allowedDomains.isNotEmpty) {
      final uri = Uri.tryParse(rawUrl);
      if (uri == null ||
          !allowedDomains.any((d) => uri.host == d || uri.host.endsWith('.$d'))) {
        return {
          'error': 'Domain not permitted. '
              'Allowed: ${allowedDomains.join(', ')}',
        };
      }
    }

    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return {'error': 'Invalid URL: $rawUrl'};

    Map<String, String> headers = {'Accept': 'application/json'};
    if (args['headers'] != null) {
      try {
        final parsed = jsonDecode(args['headers'] as String) as Map;
        headers.addAll(parsed.cast<String, String>());
      } catch (_) {}
    }

    try {
      final response = await (method == 'POST'
              ? http.post(uri,
                  headers: headers, body: args['body'] as String? ?? '')
              : http.get(uri, headers: headers))
          .timeout(timeout);

      final bodyBytes = response.bodyBytes;
      if (bodyBytes.length > maxResponseBytes) {
        return {
          'status': response.statusCode,
          'error': 'Response too large (${bodyBytes.length} bytes). '
              'Max allowed: $maxResponseBytes bytes.',
        };
      }

      final bodyText = utf8.decode(bodyBytes, allowMalformed: true);
      final contentType = response.headers['content-type'] ?? '';

      if (contentType.contains('application/json')) {
        try {
          final parsed = jsonDecode(bodyText);
          return {
            'status': response.statusCode,
            'body': parsed,
            'content_type': 'json',
          };
        } catch (_) {}
      }

      return {
        'status': response.statusCode,
        'body': bodyText.length > 2000
            ? '${bodyText.substring(0, 2000)}… [truncated]'
            : bodyText,
        'content_type': 'text',
      };
    } on Exception catch (e) {
      return {'error': 'Request failed: $e'};
    }
  }
}

/// Default [HttpTool] instance with no domain restrictions.
final AgenticTool httpRequestTool = const HttpTool().tool;
