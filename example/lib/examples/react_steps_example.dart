/// Example 5 — ReAct Step Callbacks
///
/// Watch the agent reason → call tools → observe → repeat in real time.
/// The onStep callback fires for every intermediate step before the
/// final answer, letting you build "thinking…" UIs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');

class ReactStepsExample extends StatefulWidget {
  const ReactStepsExample({super.key});
  @override
  State<ReactStepsExample> createState() => _ReactStepsExampleState();
}

class _ReactStepsExampleState extends State<ReactStepsExample> {
  final _controller = TextEditingController(
    text: 'What is the square root of 144, and what is today\'s date?',
  );
  final _steps = <AgentStep>[];
  String _finalAnswer = '';
  bool _loading = false;
  String? _error;

  late final AgenticAgent _agent = AgenticAgent(
    provider: GeminiProvider(apiKey: _geminiKey),
    systemPrompt: 'You are a helpful assistant.',
    tools: [AgenticTools.calculator, AgenticTools.dateTime],
  );

  Future<void> _run() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _steps.clear();
      _finalAnswer = '';
    });
    try {
      final reply = await _agent.chat(
        text,
        onStep: (step) {
          // Called for every intermediate step.
          setState(() => _steps.add(step));
        },
      );
      setState(() => _finalAnswer = reply.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('5 · ReAct Steps')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_geminiKey.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.shade100,
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
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _loading ? null : _run,
              child: Text(_loading ? 'Thinking…' : 'Run with step callbacks'),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            Expanded(
              child: ListView(
                children: [
                  ..._steps.asMap().entries.map((e) =>
                      _StepCard(index: e.key + 1, step: e.value)),
                  if (_finalAnswer.isNotEmpty)
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: ListTile(
                        leading: const Icon(Icons.check_circle),
                        title: const Text('Final Answer',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: SelectableText(_finalAnswer),
                      ),
                    ),
                  if (_loading && _steps.isEmpty)
                    const Center(
                        child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final int index;
  final AgentStep step;
  const _StepCard({required this.index, required this.step});

  @override
  Widget build(BuildContext context) {
    final (icon, title, body, color) = switch (step) {
      ThinkingStep(:final thought) => (
          Icons.psychology_outlined,
          'Thinking',
          thought,
          Colors.purple.shade700,
        ),
      ToolCallStep(:final toolName, :final arguments) => (
          Icons.build_outlined,
          'Tool call: $toolName',
          arguments.entries.map((e) => '  ${e.key}: ${e.value}').join('\n'),
          Colors.blue.shade700,
        ),
      ToolResultStep(:final toolName, :final result) => (
          Icons.output,
          'Result: $toolName',
          result.toString(),
          Colors.green.shade700,
        ),
      FinalResponseStep(:final text) => (
          Icons.done_all,
          'Final (from step)',
          text,
          Colors.teal.shade700,
        ),
      ErrorStep(:final message) => (
          Icons.error_outline,
          'Error',
          message,
          Colors.red.shade700,
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(30),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(title,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13)),
        subtitle: Text(body, style: const TextStyle(fontSize: 12)),
        dense: true,
      ),
    );
  }
}
