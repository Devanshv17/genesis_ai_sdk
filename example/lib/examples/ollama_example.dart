/// Example 7 — Ollama (local server)
///
/// Runs models on a local Ollama server (desktop or LAN).
/// No API key required — inference stays on your machine.
///
/// Setup:
///   1. Install Ollama: https://ollama.ai
///   2. Pull a model: ollama pull llama3.2
///   3. Ollama starts automatically on localhost:11434
library;

import 'package:flutter/material.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

class OllamaExample extends StatefulWidget {
  const OllamaExample({super.key});
  @override
  State<OllamaExample> createState() => _OllamaExampleState();
}

class _OllamaExampleState extends State<OllamaExample> {
  final _modelController = TextEditingController(text: 'llama3.2');
  final _baseUrlController =
      TextEditingController(text: 'http://localhost:11434');
  final _promptController = TextEditingController(
    text: 'What is the capital of Japan?',
  );
  OllamaStatus? _status;
  bool _checkingStatus = false;
  final StringBuffer _responseBuffer = StringBuffer();
  bool _streaming = false;
  String? _error;

  Future<void> _checkStatus() async {
    setState(() { _checkingStatus = true; _status = null; _error = null; });
    try {
      final provider = OllamaProvider(
        model: _modelController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );
      final s = await provider.checkStatus();
      setState(() => _status = s);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _checkingStatus = false);
    }
  }

  Future<void> _run() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    _responseBuffer.clear();
    setState(() { _streaming = true; _error = null; });
    try {
      final provider = OllamaProvider(
        model: _modelController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
      );
      final agent = AgenticAgent(
        provider: provider,
        systemPrompt: 'You are a helpful assistant.',
      );
      await for (final token in agent.chatStream(prompt)) {
        _responseBuffer.write(token);
        setState(() {});
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
      appBar: AppBar(title: const Text('7 · Ollama')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Setup', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              '1. Install Ollama at https://ollama.ai\n'
              '2. Run: ollama pull llama3.2\n'
              '3. Ollama starts automatically on localhost:11434',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _baseUrlController,
              decoration: const InputDecoration(
                labelText: 'Ollama base URL',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(
                    labelText: 'Model (e.g. llama3.2)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _checkingStatus ? null : _checkStatus,
                child: _checkingStatus
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Check'),
              ),
            ]),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Icon(
                    _status!.isReady ? Icons.check_circle : Icons.cancel,
                    color: _status!.isReady ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _status!.isReady
                        ? 'Ollama is ready'
                        : 'Not ready: ${_status!.reason}',
                    style: TextStyle(
                      color: _status!.isReady ? Colors.green : Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _streaming ? null : _run,
              child: Text(_streaming ? 'Generating…' : 'Run'),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(_error!,
                    style: TextStyle(color: Colors.red.shade800)),
              ),
            if (_responseBuffer.isNotEmpty || _streaming)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  _responseBuffer.toString() + (_streaming ? '▌' : ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
