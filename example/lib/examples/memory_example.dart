/// Example 4 — Memory (multi-turn conversation)
///
/// Demonstrates InMemoryStore for ephemeral history within a session.
/// The agent remembers everything said in this conversation.
///
/// For persistent history that survives app restarts, swap InMemoryStore
/// for HiveMemoryStore (see commented code below).
library;

import 'package:flutter/material.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');

class MemoryExample extends StatefulWidget {
  const MemoryExample({super.key});
  @override
  State<MemoryExample> createState() => _MemoryExampleState();
}

class _MemoryExampleState extends State<MemoryExample> {
  final _controller = TextEditingController();
  final _messages = <({bool isUser, String text})>[];
  bool _loading = false;

  // For persistent memory across app restarts, use:
  //   memory: HiveMemoryStore()
  // and call HiveMemoryStore.initialize() in main() first.
  late final AgenticAgent _agent = AgenticAgent(
    provider: GeminiProvider(apiKey: _geminiKey),
    systemPrompt:
        'You are a friendly assistant. Remember details the user tells you.',
    memory: InMemoryStore(), // ephemeral — history lives for this session only
  );

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    setState(() {
      _messages.add((isUser: true, text: text));
      _loading = true;
    });
    try {
      final reply = await _agent.chat(text);
      setState(() => _messages.add((isUser: false, text: reply.toString())));
    } catch (e) {
      setState(() =>
          _messages.add((isUser: false, text: '⚠️ Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    await _agent.clearHistory();
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('4 · Memory'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear history',
            onPressed: _clear,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_geminiKey.isEmpty)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Run with --dart-define=GEMINI_KEY=your_key',
                style: TextStyle(fontSize: 12),
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Align(
                  alignment:
                      m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: m.isUser
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      m.text,
                      style: TextStyle(
                        color: m.isUser
                            ? Theme.of(context).colorScheme.onPrimary
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Type a message…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send),
                onPressed: _loading ? null : _send,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
