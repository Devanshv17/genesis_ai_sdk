/// Execution context injected into tool executors.
///
/// Provides logging, progress reporting, and metadata about the current
/// agent session. Available in tools defined with [AgenticTool.withContext].
///
/// ```dart
/// execute: (args, ctx) async {
///   ctx.log('Starting search for: ${args.string("query")}');
///   ctx.progress(0, 'Querying database...');
///   final results = await db.search(args.string('query'));
///   ctx.progress(50, 'Processing ${results.length} results...');
///   final processed = await process(results);
///   ctx.progress(100, 'Done');
///   return ToolSuccess({'results': processed});
/// }
/// ```
library;

/// Provides logging and progress feedback to tool executors.
class ToolContext {
  /// The name of the tool being executed.
  final String toolName;

  /// The session ID of the calling agent, if available.
  final String? sessionId;

  final void Function(String level, String message) _logger;
  final void Function(int percent, String status)? _onProgress;

  ToolContext({
    required this.toolName,
    this.sessionId,
    required void Function(String level, String message) logger,
    void Function(int percent, String status)? onProgress,
  })  : _logger = logger,
        _onProgress = onProgress;

  /// Creates a no-op [ToolContext] for testing.
  factory ToolContext.silent({String toolName = 'test'}) => ToolContext(
        toolName: toolName,
        logger: (_, __) {},
      );

  // ── Logging ───────────────────────────────────────────────────────────────

  /// Logs an informational message.
  void log(String message) => _logger('info', '[$toolName] $message');

  /// Logs a debug message (lower severity than [log]).
  void debug(String message) => _logger('debug', '[$toolName] $message');

  /// Logs a warning.
  void warn(String message) => _logger('warn', '[$toolName] $message');

  // ── Progress ──────────────────────────────────────────────────────────────

  /// Reports progress to the calling agent.
  ///
  /// [percent] should be 0–100.
  /// [status] is a short human-readable description of what's happening.
  ///
  /// Progress updates are forwarded to the agent's `onStep` callback as
  /// [ThinkingStep] entries, so the UI can show a live progress indicator.
  void progress(int percent, String status) {
    _onProgress?.call(percent.clamp(0, 100), status);
    debug('progress $percent%: $status');
  }
}
