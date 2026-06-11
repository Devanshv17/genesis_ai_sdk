import '../core/message.dart';
import '../providers/llm_provider.dart';
import '../tools/genesis_tool.dart';

/// Everything a routing rule can inspect about a single call.
///
/// A fresh [RouteContext] is built for every `complete()` / `stream()` call,
/// so rules can route each task independently — short prompts on-device,
/// sensitive data locally, tool-heavy reasoning in the cloud, and so on.
class RouteContext {
  /// Full conversation history for this call (system + memory + new message).
  final List<Message> messages;

  /// Tools available for this call. Empty for plain chat / streaming.
  final List<GenesisTool> tools;

  /// True when this call came from `stream()` rather than `complete()`.
  final bool isStreaming;

  const RouteContext({
    required this.messages,
    this.tools = const [],
    this.isStreaming = false,
  });

  /// The newest user message, or `''` when there is none.
  String get latestUserMessage {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == MessageRole.user) return messages[i].content;
    }
    return '';
  }

  /// Total characters across all messages — a cheap proxy for context size.
  int get totalLength =>
      messages.fold(0, (sum, m) => sum + m.content.length);

  /// True if any tools were passed with this call.
  bool get wantsTools => tools.isNotEmpty;
}

/// A single routing rule: when [when] matches, the call goes to [useProvider].
///
/// Rules are evaluated in order; the first match wins. Create rules with
/// [RouteRules] helpers or build your own with any predicate.
class RouteRule {
  /// Key of the provider (in [PolicyRouter.providers]) this rule routes to.
  final String useProvider;

  /// Predicate evaluated against each call.
  final bool Function(RouteContext context) when;

  /// Human-readable label, surfaced in [RouteDecision] for logging/UI.
  final String description;

  const RouteRule({
    required this.useProvider,
    required this.when,
    this.description = '',
  });
}

/// Ready-made rules for the most common routing policies.
///
/// ```dart
/// final router = PolicyRouter(
///   providers: {
///     'local': GemmaProvider(...),
///     'cloud': GeminiProvider(apiKey: '...'),
///   },
///   defaultProvider: 'cloud',
///   rules: [
///     RouteRules.sensitive(useProvider: 'local'),
///     RouteRules.shortInput(useProvider: 'local', maxChars: 200),
///     RouteRules.needsTools(useProvider: 'cloud'),
///   ],
/// );
/// ```
class RouteRules {
  RouteRules._();

  /// Route to [useProvider] when the latest user message contains any of
  /// [keywords] (case-insensitive). Defaults cover common PII triggers.
  ///
  /// Typical use: keep prompts mentioning passwords, salaries, or medical
  /// details on-device.
  static RouteRule sensitive({
    required String useProvider,
    List<String> keywords = const [
      'password', 'ssn', 'salary', 'medical', 'diagnosis',
      'bank', 'account number', 'credit card', 'address',
    ],
  }) =>
      RouteRule(
        useProvider: useProvider,
        description: 'sensitive-content → $useProvider',
        when: (ctx) {
          final text = ctx.latestUserMessage.toLowerCase();
          return keywords.any((k) => text.contains(k.toLowerCase()));
        },
      );

  /// Route to [useProvider] when the latest user message is at most
  /// [maxChars] characters — small tasks rarely need a frontier model.
  static RouteRule shortInput({
    required String useProvider,
    int maxChars = 200,
  }) =>
      RouteRule(
        useProvider: useProvider,
        description: 'short-input(≤$maxChars) → $useProvider',
        when: (ctx) => ctx.latestUserMessage.length <= maxChars,
      );

  /// Route to [useProvider] when the total context exceeds [minChars] —
  /// long contexts usually want a large cloud model.
  static RouteRule longContext({
    required String useProvider,
    int minChars = 8000,
  }) =>
      RouteRule(
        useProvider: useProvider,
        description: 'long-context(≥$minChars) → $useProvider',
        when: (ctx) => ctx.totalLength >= minChars,
      );

  /// Route to [useProvider] whenever tools are in play — smaller local
  /// models are often unreliable at function calling.
  static RouteRule needsTools({required String useProvider}) => RouteRule(
        useProvider: useProvider,
        description: 'needs-tools → $useProvider',
        when: (ctx) => ctx.wantsTools,
      );

  /// Route streaming calls to [useProvider] (e.g. a low-latency local model
  /// for live typing indicators).
  static RouteRule streaming({required String useProvider}) => RouteRule(
        useProvider: useProvider,
        description: 'streaming → $useProvider',
        when: (ctx) => ctx.isStreaming,
      );

  /// Fully custom rule with a readable [description] for logs.
  static RouteRule custom({
    required String useProvider,
    required bool Function(RouteContext) when,
    String description = 'custom',
  }) =>
      RouteRule(
        useProvider: useProvider,
        when: when,
        description: '$description → $useProvider',
      );
}

/// The outcome of one routing evaluation — which provider won and why.
///
/// Delivered to [PolicyRouter.onRoute] so apps can log decisions, show a
/// "running locally 🔒 / in cloud ☁️" badge, or build cost dashboards.
class RouteDecision {
  /// Key of the chosen provider.
  final String providerKey;

  /// Display name of the chosen provider.
  final String providerName;

  /// The rule that matched, or `null` when the default provider was used.
  final RouteRule? matchedRule;

  const RouteDecision({
    required this.providerKey,
    required this.providerName,
    this.matchedRule,
  });

  @override
  String toString() => matchedRule == null
      ? 'RouteDecision(default → $providerKey)'
      : 'RouteDecision(${matchedRule!.description})';
}

/// Routes **every call independently** across any number of providers,
/// driven by user-defined [rules] — the user stays in control of the policy.
///
/// This is the difference between picking a backend once at init and having
/// a real cost/privacy lever: the call site never changes, but each task is
/// served by whichever provider the rules choose — cheap/private tasks
/// on-device, hard reasoning in the cloud.
///
/// ```dart
/// final router = PolicyRouter(
///   providers: {
///     'local': GemmaProvider(...),         // private, free
///     'cloud': GeminiProvider(apiKey: ''), // smart, paid
///   },
///   defaultProvider: 'cloud',
///   rules: [
///     RouteRules.sensitive(useProvider: 'local'),
///     RouteRules.shortInput(useProvider: 'local'),
///   ],
///   onRoute: (d) => debugPrint('routed: $d'),
/// );
///
/// // The agent never knows or cares which backend serves each turn.
/// final agent = GenesisAgent(provider: router);
/// ```
///
/// Rules are evaluated in order; first match wins; no match falls through to
/// [defaultProvider]. If the chosen provider throws, the call falls back to
/// [defaultProvider] automatically (unless it already was the default).
class PolicyRouter extends LlmProvider {
  /// All available providers, keyed by a short name used in rules.
  final Map<String, LlmProvider> providers;

  /// Key of the provider used when no rule matches (must be in [providers]).
  final String defaultProvider;

  /// Ordered routing rules — first match wins.
  final List<RouteRule> rules;

  /// Called with every [RouteDecision]; ideal for logging and UI badges.
  final void Function(RouteDecision decision)? onRoute;

  /// When true (default), a failing routed provider falls back to
  /// [defaultProvider] instead of surfacing the error.
  final bool fallbackToDefault;

  PolicyRouter({
    required this.providers,
    required this.defaultProvider,
    this.rules = const [],
    this.onRoute,
    this.fallbackToDefault = true,
  })  : assert(providers.isNotEmpty, 'providers must not be empty') {
    if (!providers.containsKey(defaultProvider)) {
      throw ArgumentError(
          'defaultProvider "$defaultProvider" not found in providers '
          '(${providers.keys.join(', ')})');
    }
    for (final rule in rules) {
      if (!providers.containsKey(rule.useProvider)) {
        throw ArgumentError(
            'Rule "${rule.description}" routes to unknown provider '
            '"${rule.useProvider}" (${providers.keys.join(', ')})');
      }
    }
  }

  @override
  String get name => 'PolicyRouter(${providers.keys.join(' | ')})';

  /// Evaluates [rules] for [context] and returns the winning decision.
  /// Exposed so apps can preview routing without making a call.
  RouteDecision decide(RouteContext context) {
    for (final rule in rules) {
      if (rule.when(context)) {
        return RouteDecision(
          providerKey: rule.useProvider,
          providerName: providers[rule.useProvider]!.name,
          matchedRule: rule,
        );
      }
    }
    return RouteDecision(
      providerKey: defaultProvider,
      providerName: providers[defaultProvider]!.name,
    );
  }

  @override
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<GenesisTool> tools = const [],
    double temperature = 0.7,
  }) async {
    final decision = decide(RouteContext(messages: messages, tools: tools));
    onRoute?.call(decision);
    final chosen = providers[decision.providerKey]!;
    try {
      return await chosen.complete(
          messages: messages, tools: tools, temperature: temperature);
    } catch (_) {
      if (fallbackToDefault && decision.providerKey != defaultProvider) {
        return await providers[defaultProvider]!.complete(
            messages: messages, tools: tools, temperature: temperature);
      }
      rethrow;
    }
  }

  @override
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  }) async* {
    final decision =
        decide(RouteContext(messages: messages, isStreaming: true));
    onRoute?.call(decision);
    final chosen = providers[decision.providerKey]!;
    // `await for` (not `yield*`) so inner-stream errors hit our try/catch.
    // Only fall back if nothing was emitted — restarting mid-stream would
    // duplicate output.
    var emitted = false;
    try {
      await for (final token
          in chosen.stream(messages: messages, temperature: temperature)) {
        emitted = true;
        yield token;
      }
    } catch (_) {
      if (!emitted &&
          fallbackToDefault &&
          decision.providerKey != defaultProvider) {
        yield* providers[defaultProvider]!
            .stream(messages: messages, temperature: temperature);
      } else {
        rethrow;
      }
    }
  }
}
