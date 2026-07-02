/// Example 3 — Tool Calling
///
/// Demonstrates:
///   • Built-in calculator tool — the agent auto-invokes it for maths.
///   • Custom weather tool — shows how to define any tool with typed params.
///   • Tool result display — you can see which tools were called.
library;

import 'package:flutter/material.dart';
import 'package:flutter_agents/flutter_agents.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');

/// Fake weather tool — replace `_fetchWeather` with a real API call.
final _weatherTool = GenesisTool.define(
  name: 'get_weather',
  description: 'Returns current weather conditions for a city.',
  params: {
    'city': ToolParam.string(description: 'City name, e.g. "Tokyo"'),
    'unit': ToolParam.stringEnum(
      ['celsius', 'fahrenheit'],
      description: 'Temperature unit.',
    ),
  },
  execute: (args) async {
    final city = args['city'] as String;
    final unit = args['unit'] as String? ?? 'celsius';
    return _fetchWeather(city, unit);
  },
);

Map<String, dynamic> _fetchWeather(String city, String unit) {
  // Simulate an API response.
  final temp = unit == 'celsius' ? 22 : 71;
  return {
    'city': city,
    'temperature': '$temp°${unit == 'celsius' ? 'C' : 'F'}',
    'condition': 'Partly cloudy',
    'humidity': '65%',
    'wind': '14 km/h NW',
  };
}

class ToolCallingExample extends StatefulWidget {
  const ToolCallingExample({super.key});
  @override
  State<ToolCallingExample> createState() => _ToolCallingExampleState();
}

class _ToolCallingExampleState extends State<ToolCallingExample> {
  final _controller = TextEditingController(
    text: 'What is 1337 * 42 and what is the weather in Tokyo?',
  );
  String _response = '';
  List<AgentStep> _steps = [];
  bool _loading = false;
  String? _error;

  late final GenesisAgent _agent = GenesisAgent(
    provider: GeminiProvider(apiKey: _geminiKey),
    systemPrompt: 'You are a helpful assistant. Use tools when needed.',
    tools: [
      GenesisTools.calculator, // built-in
      _weatherTool,            // custom
    ],
  );

  Future<void> _ask() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _loading = true; _error = null; _steps = []; _response = ''; });
    try {
      final reply = await _agent.chat(text);
      setState(() {
        _response = reply.toString();
        _steps = reply.steps;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('3 · Tool Calling')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_geminiKey.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Run with --dart-define=GEMINI_KEY=your_key',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            TextField(
              controller: _controller,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Ask something that needs tools',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _ask,
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Ask'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.red.shade50,
                child: Text(_error!, style: TextStyle(color: Colors.red.shade800)),
              ),
            if (_steps.isNotEmpty) ...[
              const Text('Steps taken:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ..._steps.map((s) => _StepTile(s)),
              const Divider(),
            ],
            if (_response.isNotEmpty) ...[
              const Text('Final answer:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(_response),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final AgentStep step;
  const _StepTile(this.step);

  @override
  Widget build(BuildContext context) {
    final (icon, label, color) = switch (step) {
      ThinkingStep()      => (Icons.psychology, 'Thinking', Colors.purple),
      ToolCallStep()      => (Icons.build, 'Tool call', Colors.blue),
      ToolResultStep()    => (Icons.check_circle, 'Tool result', Colors.green),
      FinalResponseStep() => (Icons.done_all, 'Final', Colors.teal),
      ErrorStep()         => (Icons.error, 'Error', Colors.red),
    };

    final detail = switch (step) {
      ThinkingStep(:final thought)      => thought,
      ToolCallStep(:final toolName, :final arguments) =>
          '$toolName(${arguments.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
      ToolResultStep(:final toolName, :final result) =>
          '$toolName → $result',
      FinalResponseStep(:final text)    => text,
      ErrorStep(:final message)         => message,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '[$label] $detail',
              style: TextStyle(fontSize: 12, color: color),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
