/// Example 10 — GenesisHub
///
/// GenesisHub is a one-line factory for creating agents from any source:
///   • fromHFCloud()  — any HuggingFace model, no download
///   • fromUrl()      — download a model file and run it
///   • fromOllama()   — connect to a running Ollama server
///   • fromFile()     — load a local .gguf / .litertlm / .task file
///   • fromProvider() — wrap any custom provider
///
/// GenesisHub.platformModelsDir() returns the correct writable directory
/// for model storage on every platform (uses path_provider internally).
library;

import 'package:flutter/material.dart';
import 'package:flutter_agents/flutter_agents.dart';
// ignore: implementation_imports
import 'package:flutter_agents/src/hub/genesis_hub.dart';

const _hfToken = String.fromEnvironment('HF_TOKEN', defaultValue: '');

class GenesisHubExample extends StatefulWidget {
  const GenesisHubExample({super.key});
  @override
  State<GenesisHubExample> createState() => _GenesisHubExampleState();
}

class _GenesisHubExampleState extends State<GenesisHubExample> {
  final _results = <_DemoResult>[];

  // ── Demo 1: fromHFCloud ────────────────────────────────────────────────────

  Future<void> _demoFromHFCloud() async {
    _add(_DemoResult(method: 'fromHFCloud()', status: 'Running…'));
    try {
      final agent = GenesisHub.fromHFCloud(
        modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
        apiToken: _hfToken.isEmpty ? null : _hfToken,
        maxTokens: 64,
        systemPrompt: 'Reply in one sentence.',
      );
      final reply = await agent.chat('What is 7 multiplied by 8?');
      _update(_DemoResult(method: 'fromHFCloud()', status: 'OK', output: reply.toString()));
    } catch (e) {
      _update(_DemoResult(method: 'fromHFCloud()', status: 'Error', output: e.toString()));
    }
  }

  // ── Demo 2: fromOllama ─────────────────────────────────────────────────────

  Future<void> _demoFromOllama() async {
    _add(_DemoResult(method: 'fromOllama()', status: 'Running…'));
    try {
      final agent = await GenesisHub.fromOllama(
        model: 'llama3.2',
        baseUrl: 'http://localhost:11434',
        systemPrompt: 'Reply in one sentence.',
      );
      final reply = await agent.chat('Name the closest planet to the Sun.');
      _update(_DemoResult(method: 'fromOllama()', status: 'OK', output: reply.toString()));
    } catch (e) {
      _update(_DemoResult(method: 'fromOllama()', status: 'Error (Ollama not running?)', output: e.toString()));
    }
  }

  // ── Demo 3: fromProvider ───────────────────────────────────────────────────

  Future<void> _demoFromProvider() async {
    _add(_DemoResult(method: 'fromProvider()', status: 'Running…'));
    try {
      final provider = HFInferenceProvider(
        modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
        apiToken: _hfToken.isEmpty ? null : _hfToken,
        maxTokens: 64,
      );
      final agent = GenesisHub.fromProvider(
        provider: provider,
        systemPrompt: 'You are a helpful assistant.',
      );
      final reply = await agent.chat('What is the boiling point of water in Celsius?');
      _update(_DemoResult(method: 'fromProvider()', status: 'OK', output: reply.toString()));
    } catch (e) {
      _update(_DemoResult(method: 'fromProvider()', status: 'Error', output: e.toString()));
    }
  }

  // ── Demo 4: platformModelsDir ──────────────────────────────────────────────

  Future<void> _demoPlatformModelsDir() async {
    _add(_DemoResult(method: 'platformModelsDir()', status: 'Running…'));
    try {
      final dir = await GenesisHubPlatformPaths.platformModelsDir();
      _update(_DemoResult(method: 'platformModelsDir()', status: 'OK', output: dir));
    } catch (e) {
      _update(_DemoResult(method: 'platformModelsDir()', status: 'Error', output: e.toString()));
    }
  }

  void _add(_DemoResult r) => setState(() => _results.insert(0, r));
  void _update(_DemoResult r) => setState(() => _results[0] = r);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('10 · GenesisHub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            onPressed: () => setState(() => _results.clear()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_hfToken.isEmpty)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Tip: pass --dart-define=HF_TOKEN=hf_xxxx for higher HF rate limits.',
                style: TextStyle(fontSize: 12),
              ),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DemoTile(
                  icon: '🤗',
                  title: 'GenesisHub.fromHFCloud()',
                  subtitle: 'Run any HF model — no download needed.',
                  code: "GenesisHub.fromHFCloud(\n"
                      "  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',\n"
                      "  apiToken: 'hf_xxxx',\n"
                      ")",
                  onTap: _demoFromHFCloud,
                ),
                _DemoTile(
                  icon: '🦙',
                  title: 'GenesisHub.fromOllama()',
                  subtitle: 'Connect to a local Ollama server.',
                  code: "GenesisHub.fromOllama(\n"
                      "  model: 'llama3.2',\n"
                      ")",
                  onTap: _demoFromOllama,
                ),
                _DemoTile(
                  icon: '🔌',
                  title: 'GenesisHub.fromProvider()',
                  subtitle: 'Wrap any custom provider.',
                  code: "GenesisHub.fromProvider(\n"
                      "  provider: HFInferenceProvider(...),\n"
                      ")",
                  onTap: _demoFromProvider,
                ),
                _DemoTile(
                  icon: '📁',
                  title: 'GenesisHub.platformModelsDir()',
                  subtitle: 'Get the writable model directory for this platform.',
                  code: "final dir = await GenesisHub.platformModelsDir();\n"
                      "// Android: /data/user/0/<package>/files/genesis_models\n"
                      "// iOS/macOS: <NSApplicationSupport>/genesis_models",
                  onTap: _demoPlatformModelsDir,
                ),
              ],
            ),
          ),

          // Results panel
          if (_results.isNotEmpty)
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(r.method,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                    subtitle: Text(
                      '${r.status}${r.output.isNotEmpty ? "\n${r.output}" : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: r.status.startsWith('Error')
                            ? Colors.red.shade700
                            : r.status == 'OK'
                                ? Colors.green.shade700
                                : null,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _DemoTile extends StatelessWidget {
  final String icon, title, subtitle, code;
  final VoidCallback onTap;
  const _DemoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.code,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(icon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const Icon(Icons.play_arrow, size: 18),
                ]),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DemoResult {
  final String method, status, output;
  const _DemoResult(
      {required this.method, required this.status, this.output = ''});
}
