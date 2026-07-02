/// Example 6 — HuggingFace Cloud Inference
///
/// Run any public model on HuggingFace without downloading it.
/// The HF Inference Router proxies requests to GPU fleets (featherless,
/// nebius, together, sambanova, or HF's own servers).
///
/// Free tier: get a token at https://huggingface.co/settings/tokens
library;

import 'package:flutter/material.dart';
import 'package:flutter_agentic/flutter_agentic.dart';

// Pass via --dart-define=HF_TOKEN=hf_xxxx
const _hfToken = String.fromEnvironment('HF_TOKEN', defaultValue: '');

// Any public model on HuggingFace:
const _models = [
  'Qwen/Qwen2.5-0.5B-Instruct',
  'Qwen/Qwen2.5-1.5B-Instruct',
  'microsoft/Phi-3.5-mini-instruct',
  'meta-llama/Meta-Llama-3.1-8B-Instruct',
  'mistralai/Mistral-7B-Instruct-v0.3',
];

class HFInferenceExample extends StatefulWidget {
  const HFInferenceExample({super.key});
  @override
  State<HFInferenceExample> createState() => _HFInferenceExampleState();
}

class _HFInferenceExampleState extends State<HFInferenceExample> {
  final _promptController = TextEditingController(
    text: 'Explain what a transformer model is in 2 sentences.',
  );
  String _selectedModel = _models.first;
  HFInferenceBackend _selectedBackend = HFInferenceBackend.featherless;
  bool _streaming = false;
  final StringBuffer _responseBuffer = StringBuffer();
  String? _error;

  Future<void> _run() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;
    _responseBuffer.clear();
    setState(() { _streaming = true; _error = null; });

    try {
      // Use AgenticHub.fromHFCloud for a one-liner, or build the provider
      // directly for full control over backend / maxTokens / timeout.
      final provider = HFInferenceProvider(
        modelId: _selectedModel,
        apiToken: _hfToken.isEmpty ? null : _hfToken,
        maxTokens: 256,
        backend: _selectedBackend,
      );
      final agent = AgenticAgent(
        provider: provider,
        systemPrompt: 'You are a helpful assistant. Be concise.',
      );

      await for (final token in agent.chatStream(prompt)) {
        _responseBuffer.write(token);
        setState(() {});
      }
    } on HFInferenceException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _streaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('6 · HF Inference')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hfToken.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Add --dart-define=HF_TOKEN=hf_xxxx for higher rate limits.\n'
                  'Free (unauthenticated) requests may be rate-limited.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            // Model picker
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedModel,
              decoration: const InputDecoration(
                labelText: 'Model',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _models
                  .map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setState(() => _selectedModel = v!),
            ),
            const SizedBox(height: 8),
            // Backend picker
            DropdownButtonFormField<HFInferenceBackend>(
              // ignore: deprecated_member_use
              value: _selectedBackend,
              decoration: const InputDecoration(
                labelText: 'Backend',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: HFInferenceBackend.values
                  .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedBackend = v!),
            ),
            const SizedBox(height: 8),
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
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12)),
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
