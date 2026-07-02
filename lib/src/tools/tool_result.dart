/// Typed return value for [AgenticTool] executors.
///
/// Tools return either a success with structured data or a typed error that
/// the agent can reason about.
///
/// ```dart
/// execute: (args, ctx) async {
///   try {
///     final data = await myApi.fetch(args.string('query'));
///     return ToolSuccess({'result': data.text, 'count': data.items.length});
///   } on ApiException catch (e) {
///     return ToolError('API unavailable: ${e.message}', code: 'API_UNAVAILABLE');
///   }
/// }
/// ```
library;

/// Base class for tool execution results.
sealed class ToolResult {
  const ToolResult();

  /// Returns true when the tool executed successfully.
  bool get isSuccess => this is ToolSuccess;

  /// Returns true when the tool returned an error.
  bool get isError => this is ToolError;

  /// Converts this result to the raw map the agent receives.
  Map<String, dynamic> toMap();
}

/// A successful tool result carrying structured data.
class ToolSuccess extends ToolResult {
  /// Output data the LLM will read as the tool's response.
  /// Keep keys descriptive — the LLM reads them too.
  final Map<String, dynamic> data;

  const ToolSuccess(this.data);

  @override
  Map<String, dynamic> toMap() => data;
}

/// A tool error that the agent can reason about and handle gracefully.
///
/// Returning a [ToolError] is preferred over throwing an exception when
/// the error is something the user or agent can act on (e.g., "city not found",
/// "rate limit exceeded"). Use exceptions for truly unexpected failures.
class ToolError extends ToolResult {
  /// Human-readable error description sent back to the LLM.
  final String message;

  /// Optional machine-readable error code (e.g. `'NOT_FOUND'`, `'RATE_LIMITED'`).
  final String? code;

  /// Original exception / cause, for logging. Not sent to the LLM.
  final Object? cause;

  const ToolError(
    this.message, {
    this.code,
    this.cause,
  });

  @override
  Map<String, dynamic> toMap() => {
        'error': message,
        if (code != null) 'error_code': code,
      };
}
