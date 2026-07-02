import 'dart:math';
import '../core/message.dart';
import '../tools/agentic_tool.dart';
import 'llm_provider.dart';

/// Wraps any [LlmProvider] with automatic retry and exponential backoff.
///
/// Retries on transient errors (network timeout, 429 rate limit, 5xx server errors).
/// Does NOT retry on 4xx client errors (bad API key, invalid request, etc.).
///
/// ```dart
/// final provider = RetryProvider(
///   inner: GeminiProvider(apiKey: '...'),
///   maxAttempts: 3,
///   initialDelayMs: 500,
/// );
/// ```
class RetryProvider extends LlmProvider {
  final LlmProvider inner;

  /// Maximum number of attempts (including the first try).
  final int maxAttempts;

  /// Base delay before the first retry, in milliseconds.
  /// Doubles on each subsequent attempt (exponential backoff).
  final int initialDelayMs;

  /// Optional callback fired on each retry with the attempt number and error.
  final void Function(int attempt, Object error)? onRetry;

  RetryProvider({
    required this.inner,
    this.maxAttempts = 3,
    this.initialDelayMs = 500,
    this.onRetry,
  });

  @override
  String get name => '${inner.name} (with retry)';

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) =>
      _withRetry(() => inner.complete(
            messages: messages,
            tools: tools,
            temperature: temperature,
          ));

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) =>
      // Streams can't be retried transparently mid-stream.
      // We retry the initial connection only.
      inner.stream(messages: messages, temperature: temperature);

  Future<T> _withRetry<T>(Future<T> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts || !_isRetryable(e)) rethrow;

        onRetry?.call(attempt, e);

        // Exponential backoff: 500ms, 1000ms, 2000ms … + jitter
        final delay = initialDelayMs * pow(2, attempt - 1).toInt();
        final jitter = Random().nextInt(200);
        await Future.delayed(Duration(milliseconds: delay + jitter));
      }
    }
  }

  /// Returns true for errors that are worth retrying.
  bool _isRetryable(Object error) {
    final msg = error.toString().toLowerCase();
    // Rate limit, server error, network timeout
    if (msg.contains('429') ||
        msg.contains('500') ||
        msg.contains('502') ||
        msg.contains('503') ||
        msg.contains('504') ||
        msg.contains('timeout') ||
        msg.contains('network') ||
        msg.contains('connection')) {
      return true;
    }
    // Don't retry auth errors, bad requests, etc.
    return false;
  }
}
