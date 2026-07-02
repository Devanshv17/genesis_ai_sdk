import '../agentic_tool.dart';
import '../tool_param.dart';

/// A mock weather tool for testing and development.
///
/// Returns realistic but fake weather data — no API key, no network call,
/// works offline. Perfect for demoing the ReAct loop without any setup.
///
/// **Replace with a real weather tool in production.**
///
/// Usage:
/// ```dart
/// tools: [AgenticTools.mockWeather]  // testing
/// tools: [WeatherTool(apiKey: '...')]  // production (flutter_agentic_tools package)
/// ```
final AgenticTool mockWeatherTool = AgenticTool.define(
  name: 'get_weather',
  description:
      'Gets the current weather for a city. Returns temperature, '
      'conditions, humidity, and wind speed.',
  params: {
    'location': ToolParam.string(
      description: 'City name, e.g. "Mumbai" or "London, UK"',
      required: true,
    ),
    'unit': ToolParam.stringEnum(
      ['celsius', 'fahrenheit'],
      description: 'Temperature unit. Defaults to celsius.',
      defaultValue: 'celsius',
    ),
  },
  execute: (args) async {
    final location = (args['location'] as String).trim();
    final unit = args['unit'] as String? ?? 'celsius';

    // Deterministic mock based on city name (so same city always same result)
    final seed = location.toLowerCase().codeUnits.fold(0, (a, b) => a + b);
    final tempC = 10 + (seed % 35); // 10–44 °C
    final humidity = 30 + (seed % 60); // 30–89 %
    final windKph = 5 + (seed % 40); // 5–44 kph
    final conditions = [
      'Sunny', 'Partly cloudy', 'Cloudy', 'Overcast',
      'Light rain', 'Heavy rain', 'Thunderstorm', 'Foggy',
      'Windy', 'Hot and humid', 'Clear skies',
    ];
    final condition = conditions[seed % conditions.length];

    final displayTemp =
        unit == 'fahrenheit' ? (tempC * 9 / 5 + 32).round() : tempC;
    final unitSymbol = unit == 'fahrenheit' ? '°F' : '°C';

    // Simulate a small network delay for realism
    await Future.delayed(const Duration(milliseconds: 400));

    return {
      'location': location,
      'temperature': '$displayTemp $unitSymbol',
      'condition': condition,
      'humidity': '$humidity%',
      'wind': '$windKph kph',
      'note': 'Mock data — for testing only',
    };
  },
);
