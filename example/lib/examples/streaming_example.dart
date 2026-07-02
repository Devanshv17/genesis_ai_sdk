/// Example 2 — Streaming
///
/// Shows token-by-token streaming output from any provider.
/// The UI updates in real time as the model generates each word.
library;

import 'package:flutter/material.dart';
import 'package:flutter_agents/flutter_agents.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');

class StreamingExample extends StatefulWidget {
  const StreamingExample({super.key});
  @override
  State<StreamingExample> createState() => _StreamingExampleState();
}

class _StreamingExampleState extends State<StreamingExample> {
  final _controller = TextEditingController(text: 'Write a short poem about the ocean.');
  final StringBuffer _buffer = StringBuffer();
  bool _streaming = false;
  String? _error;

  late final GenesisAgent _agent = GenesisAgent(
    provider: GeminiProvider(apiKey: _geminiKey),
    systemPrompt: 'You are a creative assistant.',
  );

  Future<void> _stream() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _buffer.clear();
    setState(() { _streaming = true; _error = null; });
    try {
      await for (final token in _agent.chatStream(text)) {
        _buffer.write(token);
        setState(() {}); // rebuild to show latest token
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2 · Streaming')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_geminiKey.isEmpty)
              const _Warning('Run with --dart-define=GEMINI_KEY=your_key'),
            const SizedBox(height: 8),
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
              onPressed: _streaming ? null : _stream,
              child: Text(_streaming ? 'Streaming…' : 'Stream response'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              _ErrorBox(_error!),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SelectableText(_buffer.toString())),
                      if (_streaming)
                        const SizedBox(
                          width: 12, height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  final String msg;
  const _Warning(this.msg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
        child: Text(msg, style: const TextStyle(fontSize: 12)),
      );
}

class _ErrorBox extends StatelessWidget {
  final String msg;
  const _ErrorBox(this.msg);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text(msg, style: TextStyle(color: Colors.red.shade800)),
      );
}
