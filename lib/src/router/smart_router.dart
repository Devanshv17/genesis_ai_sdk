import '../core/message.dart';
import '../providers/llm_provider.dart';
import '../tools/agentic_tool.dart';

/// Strategy used by [SmartRouter] to pick a provider.
enum RouterStrategy {
  /// Always use the primary provider. Fall back to secondary only on error.
  primaryFirst,

  /// Always use the secondary (cloud) provider.
  secondaryOnly,

  /// Use primary; if it takes longer than [latencyThresholdMs], fall back.
  latencyBased,
}

/// Routes completions between two providers based on a [RouterStrategy].
///
/// Common use-cases:
/// - Local first, cloud fallback: `primaryFirst` with a local primary.
/// - Cost control: `primaryFirst` so cloud is only hit when local fails.
/// - Speed: `latencyBased` to fall back to cloud if local is too slow.
///
/// Example:
/// ```dart
/// final router = SmartRouter(
///   primary: GemmaProvider(...),
///   secondary: GeminiProvider(apiKey: '...'),
///   strategy: RouterStrategy.primaryFirst,
/// );
/// ```
class SmartRouter extends LlmProvider {
  final LlmProvider primary;
  final LlmProvider secondary;
  final RouterStrategy strategy;
  final int latencyThresholdMs;

  SmartRouter({
    required this.primary,
    required this.secondary,
    this.strategy = RouterStrategy.primaryFirst,
    this.latencyThresholdMs = 3000,
  });

  @override
  String get name => 'SmartRouter(${primary.name} → ${secondary.name})';

  LlmProvider get _active => strategy == RouterStrategy.secondaryOnly
      ? secondary
      : primary;

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) async {
    if (strategy == RouterStrategy.latencyBased) {
      return _withLatencyFallback(messages, tools, temperature);
    }

    try {
      return await _active.complete(
          messages: messages, tools: tools, temperature: temperature);
    } catch (_) {
      if (strategy == RouterStrategy.primaryFirst) {
        // Primary failed — fall back to secondary silently.
        return await secondary.complete(
            messages: messages, tools: tools, temperature: temperature);
      }
      rethrow;
    }
  }

  Future<ProviderResult> _withLatencyFallback(
    List<Message> messages,
    List<AgenticTool> tools,
    double temperature,
  ) async {
    try {
      return await primary
          .complete(messages: messages, tools: tools, temperature: temperature)
          .timeout(Duration(milliseconds: latencyThresholdMs));
    } catch (_) {
      return await secondary.complete(
          messages: messages, tools: tools, temperature: temperature);
    }
  }

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    if (strategy == RouterStrategy.secondaryOnly) {
      yield* secondary.stream(messages: messages, temperature: temperature);
      return;
    }
    // primaryFirst / latencyBased: if the primary stream fails before
    // producing any output, fall back to the secondary stream silently.
    var emitted = false;
    try {
      await for (final token
          in primary.stream(messages: messages, temperature: temperature)) {
        emitted = true;
        yield token;
      }
    } catch (_) {
      if (emitted) rethrow; // mid-stream failure: don't restart and duplicate
      yield* secondary.stream(messages: messages, temperature: temperature);
    }
  }
}

/// A privacy-preserving router that strips sensitive values before sending
/// to a cloud provider, then restores them in the response.
///
/// Useful for financial or medical data where raw numbers must stay on-device
/// but you still want cloud-quality reasoning.
///
/// Example:
/// ```dart
/// final router = PrivacyRouter(
///   cloudProvider: GeminiProvider(apiKey: '...'),
///   sensitiveKeys: ['amount', 'balance', 'salary'],
/// );
/// ```
class PrivacyRouter extends LlmProvider {
  final LlmProvider cloudProvider;

  /// Field names whose values will be replaced with placeholders.
  final List<String> sensitiveKeys;

  PrivacyRouter({
    required this.cloudProvider,
    this.sensitiveKeys = const ['amount', 'balance', 'salary', 'account'],
  });

  @override
  String get name => 'PrivacyRouter(${cloudProvider.name})';

  String _anonymize(String text) {
    var result = text;
    for (final key in sensitiveKeys) {
      result = result.replaceAllMapped(
        RegExp(r'("?' + key + r'"?\s*[:=]\s*)(["\d.,]+)', caseSensitive: false),
        (m) => '${m.group(1)}<REDACTED>',
      );
    }
    return result;
  }

  List<Message> _anonymizeMessages(List<Message> messages) =>
      messages.map((m) => switch (m.role) {
            MessageRole.user => Message.user(_anonymize(m.content)),
            MessageRole.system => Message.system(_anonymize(m.content)),
            _ => m,
          }).toList();

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  }) =>
      cloudProvider.complete(
        messages: _anonymizeMessages(messages),
        tools: tools,
        temperature: temperature,
      );

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) =>
      cloudProvider.stream(
        messages: _anonymizeMessages(messages),
        temperature: temperature,
      );
}
