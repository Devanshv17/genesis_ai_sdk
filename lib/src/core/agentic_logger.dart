/// Log levels for [AgenticLogger].
enum LogLevel { debug, info, warning, error, none }

/// Structured logger for the Genesis AI SDK.
///
/// By default, nothing is logged. Enable during development:
/// ```dart
/// AgenticLogger.level = LogLevel.debug;
/// ```
///
/// Supply a custom handler to integrate with your own logging:
/// ```dart
/// AgenticLogger.handler = (level, tag, message) {
///   FirebaseCrashlytics.instance.log('[$tag] $message');
/// };
/// ```
class AgenticLogger {
  AgenticLogger._();

  /// Minimum level to log. Messages below this level are silently dropped.
  /// Defaults to [LogLevel.none] (silent) for production safety.
  static LogLevel level = LogLevel.none;

  /// Custom log handler. If null, prints to stdout in debug mode.
  static void Function(LogLevel level, String tag, String message)? handler;

  static void debug(String tag, String message) =>
      _log(LogLevel.debug, tag, message);

  static void info(String tag, String message) =>
      _log(LogLevel.info, tag, message);

  static void warning(String tag, String message) =>
      _log(LogLevel.warning, tag, message);

  static void error(String tag, String message) =>
      _log(LogLevel.error, tag, message);

  static void _log(LogLevel l, String tag, String message) {
    if (l.index < level.index) return;
    if (handler != null) {
      handler!(l, tag, message);
    } else {
      final prefix = switch (l) {
        LogLevel.debug => '🔍',
        LogLevel.info => 'ℹ️ ',
        LogLevel.warning => '⚠️ ',
        LogLevel.error => '❌',
        LogLevel.none => '',
      };
      // ignore: avoid_print
      print('$prefix [flutter_agentic/$tag] $message');
    }
  }
}
