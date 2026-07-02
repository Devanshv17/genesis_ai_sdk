/// Example 1 — Quick Start
///
/// Basic single-turn chat with a cloud provider (Gemini by default).
/// Swap the provider for any other — the agent API is identical.
library;

import 'package:flutter/material.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

// Pass your key via --dart-define=GEMINI_KEY=your_key
const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');

class QuickStartExample extends StatefulWidget {
  const QuickStartExample({super.key});
  @override
  State<QuickStartExample> createState() => _QuickStartExampleState();
}

class _QuickStartExampleState extends State<QuickStartExample> {
  final _controller = TextEditingController();
  String _response = '';
  bool _loading = false;
  String? _error;

  late final AgenticAgent _agent = AgenticAgent(
    provider: GeminiProvider(
      apiKey: _geminiKey,
      model: 'gemini-2.0-flash',
    ),
    systemPrompt: 'You are a helpful assistant. Be concise.',
  );

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() { _loading = true; _error = null; _response = ''; });
    try {
      final reply = await _agent.chat(text);
      setState(() => _response = reply.toString());
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('1 · Quick Start')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_geminiKey.isEmpty)
              const _KeyWarning('Run with --dart-define=GEMINI_KEY=your_key'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Ask anything…',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _loading ? null : _send, child: const Text('Send')),
            ]),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            if (_error != null) _ErrorBox(_error!),
            if (_response.isNotEmpty) _ResponseBox(_response),
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets used across examples ─────────────────────────────────────

class _KeyWarning extends StatelessWidget {
  final String message;
  const _KeyWarning(this.message);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 12))),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox(this.message);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          border: Border.all(color: Colors.red.shade200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message, style: TextStyle(color: Colors.red.shade800)),
      );
}

class _ResponseBox extends StatelessWidget {
  final String text;
  const _ResponseBox(this.text);
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(text),
      );
}
