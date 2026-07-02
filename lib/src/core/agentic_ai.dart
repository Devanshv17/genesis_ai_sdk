import '../providers/llm_provider.dart';
import 'agentic_logger.dart';
import 'model_config.dart';

/// Global configuration for the Genesis AI SDK.
///
/// Call [AgenticAI.init] once at app startup before creating any agents.
///
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///
///   await AgenticAI.init(
///     providers: {
///       'gemini': GeminiProvider(apiKey: Env.geminiKey),
///       'openai': OpenAIProvider(apiKey: Env.openAiKey),
///     },
///     defaultProviderKey: 'gemini',
///     logLevel: LogLevel.info, // use LogLevel.none in production
///   );
///
///   runApp(const MyApp());
/// }
/// ```
class AgenticAI {
  AgenticAI._();

  static final Map<String, LlmProvider> _providers = {};
  static String? _defaultKey;
  static bool _initialized = false;

  /// Initialises the SDK with a map of named providers.
  ///
  /// [providers] — map of key → provider, e.g. `{'gemini': GeminiProvider(...)}`.
  /// [defaultProviderKey] — which key to use when no provider is specified.
  ///   Defaults to the first entry if omitted.
  /// [logLevel] — logging verbosity. Use [LogLevel.none] in production.
  static Future<void> init({
    required Map<String, LlmProvider> providers,
    String? defaultProviderKey,
    LogLevel logLevel = LogLevel.none,
  }) async {
    assert(providers.isNotEmpty, 'Provide at least one LlmProvider.');

    AgenticLogger.level = logLevel;
    _providers
      ..clear()
      ..addAll(providers);
    _defaultKey = defaultProviderKey ?? providers.keys.first;
    _initialized = true;

    AgenticLogger.info('AgenticAI', 'Initialized with providers: '
        '${providers.keys.join(', ')} | default: $_defaultKey');
  }

  /// Returns the provider registered under [key].
  ///
  /// Throws if [AgenticAI.init] has not been called or the key is unknown.
  static LlmProvider provider(String key) {
    _assertInitialized();
    final p = _providers[key];
    if (p == null) {
      throw AgenticException(
        'No provider registered under key "$key". '
        'Available: ${_providers.keys.join(', ')}',
      );
    }
    return p;
  }

  /// Returns the default provider (set via [defaultProviderKey] in [init]).
  static LlmProvider get defaultProvider {
    _assertInitialized();
    return _providers[_defaultKey]!;
  }

  /// Returns true if [AgenticAI.init] has been called.
  static bool get isInitialized => _initialized;

  /// Returns all registered provider keys.
  static List<String> get providerKeys => _providers.keys.toList();

  static void _assertInitialized() {
    if (!_initialized) {
      throw const AgenticException(
        'AgenticAI is not initialized. Call AgenticAI.init() at app startup.',
      );
    }
  }
}

/// Thrown when the SDK is misconfigured or used incorrectly.
class AgenticException implements Exception {
  final String message;
  const AgenticException(this.message);

  @override
  String toString() => 'AgenticException: $message';
}

/// Convenience accessor to [ModelRegistry].
/// `AgenticModels.get('gpt-4o-mini')` returns the config for GPT-4o Mini.
typedef AgenticModels = ModelRegistry;
