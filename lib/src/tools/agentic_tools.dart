import 'builtins/calculator_tool.dart';
import 'builtins/datetime_tool.dart';
import 'builtins/http_tool.dart';
import 'builtins/mock_weather_tool.dart';
import 'agentic_tool.dart';

export 'builtins/http_tool.dart' show HttpTool;

/// Pre-built tools included with the Genesis AI SDK.
///
/// All tools are zero-config unless noted. Just add them to your agent:
///
/// ```dart
/// final agent = AgenticAgent(
///   provider: myProvider,
///   tools: [
///     AgenticTools.calculator,
///     AgenticTools.dateTime,
///     AgenticTools.httpRequest,
///     AgenticTools.mockWeather,  // swap for a real weather tool in production
///   ],
/// );
/// ```
abstract final class AgenticTools {
  /// Evaluates arithmetic expressions: +, -, *, /, ^, %, sqrt(), trig, log.
  ///
  /// No API key. Works offline. All platforms.
  static AgenticTool get calculator => calculatorTool;

  /// Returns the current date, time, day of week, and timezone info.
  ///
  /// No API key. Works offline. All platforms.
  static AgenticTool get dateTime => dateTimeTool;

  /// Makes HTTP GET / POST requests to any URL.
  ///
  /// No API key required. Requires network access.
  /// For domain-restricted usage: `HttpTool(allowedDomains: ['...'])`
  static AgenticTool get httpRequest => httpRequestTool;

  /// Returns mock weather data for testing and development.
  ///
  /// No API key. Works offline. **Not for production use.**
  /// Replace with a real provider from the `flutter_agentic_tools` package.
  static AgenticTool get mockWeather => mockWeatherTool;

  /// All built-in tools as a list — useful for quick prototyping.
  ///
  /// ```dart
  /// tools: AgenticTools.all
  /// ```
  static List<AgenticTool> get all => [
        calculator,
        dateTime,
        httpRequest,
        mockWeather,
      ];
}
