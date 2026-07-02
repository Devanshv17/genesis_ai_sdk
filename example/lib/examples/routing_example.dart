/// Example 9 — Smart Routing
///
/// Demonstrates two routers:
///   • SmartRouter — tries primary provider, falls back to secondary on error.
///   • PrivacyRouter — rewrites sensitive fields before sending to the cloud,
///     keeping PII on-device.
library;

import 'package:flutter/material.dart';
import 'package:flutter_agents/flutter_agents.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY', defaultValue: '');
const _hfToken   = String.fromEnvironment('HF_TOKEN',   defaultValue: '');

class RoutingExample extends StatefulWidget {
  const RoutingExample({super.key});
  @override
  State<RoutingExample> createState() => _RoutingExampleState();
}

class _RoutingExampleState extends State<RoutingExample> {
  final _results = <_RoutingResult>[];

  // ── SmartRouter demo ───────────────────────────────────────────────────────
  //
  // Primary: Gemini (real key needed)
  // Secondary: HF featherless (works with free token or no token)
  //
  // When the primary key is empty, GeminiProvider will throw → SmartRouter
  // automatically retries on the secondary provider.

  Future<void> _testSmartRouter(String prompt) async {
    setState(() => _results.insert(0, _RoutingResult(
      type: 'SmartRouter',
      prompt: prompt,
      response: 'Loading…',
      note: '',
    )));

    try {
      final router = SmartRouter(
        primary: GeminiProvider(
          apiKey: _geminiKey.isEmpty ? 'INVALID_KEY' : _geminiKey,
        ),
        secondary: HFInferenceProvider(
          modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
          apiToken: _hfToken.isEmpty ? null : _hfToken,
          maxTokens: 64,
        ),
      );
      final agent = GenesisAgent(
        provider: router,
        systemPrompt: 'Reply in one sentence.',
      );
      final reply = await agent.chat(prompt);
      setState(() {
        _results[0] = _RoutingResult(
          type: 'SmartRouter',
          prompt: prompt,
          response: reply.toString(),
          note: _geminiKey.isEmpty
              ? 'Primary (Gemini) had invalid key → fell back to HF featherless'
              : 'Primary (Gemini) succeeded',
        );
      });
    } catch (e) {
      setState(() {
        _results[0] = _RoutingResult(
          type: 'SmartRouter',
          prompt: prompt,
          response: 'Error: $e',
          note: 'Both providers failed',
        );
      });
    }
  }

  // ── PrivacyRouter demo ─────────────────────────────────────────────────────
  //
  // PrivacyRouter replaces values of sensitive keys with placeholders before
  // sending the message to the cloud.  The model never sees real PII.

  Future<void> _testPrivacyRouter() async {
    const sensitivePrompt =
        'My name is John Smith, my email is john@example.com '
        'and my phone is 555-867-5309. Summarise my contact info.';

    setState(() => _results.insert(0, _RoutingResult(
      type: 'PrivacyRouter',
      prompt: sensitivePrompt,
      response: 'Loading…',
      note: '',
    )));

    try {
      // In production you would use a real cloud provider here.
      // For the demo, HF featherless works without a paid key.
      final router = PrivacyRouter(
        cloudProvider: HFInferenceProvider(
          modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
          apiToken: _hfToken.isEmpty ? null : _hfToken,
          maxTokens: 128,
        ),
        sensitiveKeys: ['email', 'phone', 'name'],
      );
      final agent = GenesisAgent(provider: router);
      final reply = await agent.chat(sensitivePrompt);
      setState(() {
        _results[0] = _RoutingResult(
          type: 'PrivacyRouter',
          prompt: sensitivePrompt,
          response: reply.toString(),
          note: 'Sensitive values anonymised before reaching the cloud model.',
        );
      });
    } catch (e) {
      setState(() {
        _results[0] = _RoutingResult(
          type: 'PrivacyRouter',
          prompt: sensitivePrompt,
          response: 'Error: $e',
          note: '',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('9 · Smart Routing')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionCard(
                  title: 'SmartRouter — fallback demo',
                  body:
                      'Primary: Gemini (${_geminiKey.isEmpty ? "❌ no key — will fail" : "✅ key set"})\n'
                      'Fallback: HF featherless (${_hfToken.isEmpty ? "no token" : "token set"})\n\n'
                      'If the primary fails, the request is automatically retried '
                      'on the secondary provider.',
                  buttonLabel: 'Try SmartRouter',
                  onPressed: () => _testSmartRouter('What is the tallest mountain on Earth?'),
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'PrivacyRouter — PII anonymisation',
                  body:
                      'Sensitive keys (name, email, phone) are replaced with '
                      'placeholders before the prompt leaves the device. '
                      'The cloud model never sees real PII.',
                  buttonLabel: 'Try PrivacyRouter',
                  onPressed: _testPrivacyRouter,
                ),
              ],
            ),
          ),

          // Results panel
          if (_results.isNotEmpty)
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _ResultCard(_results[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onPressed;
  const _SectionCard({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              FilledButton(onPressed: onPressed, child: Text(buttonLabel)),
            ],
          ),
        ),
      );
}

class _RoutingResult {
  final String type, prompt, response, note;
  const _RoutingResult(
      {required this.type,
      required this.prompt,
      required this.response,
      required this.note});
}

class _ResultCard extends StatelessWidget {
  final _RoutingResult r;
  const _ResultCard(this.r);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('[${r.type}]',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 12)),
            if (r.note.isNotEmpty)
              Text(r.note,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(r.response,
                style: const TextStyle(fontSize: 12),
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      );
}
