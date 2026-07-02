/// genesis_ai_sdk — Comprehensive Example App
///
/// This app demonstrates every major feature of genesis_ai_sdk:
///   1.  Quick start — basic single-turn chat
///   2.  Streaming — token-by-token output
///   3.  Multi-turn memory — conversation history
///   4.  Tool calling — calculator + custom tools
///   5.  ReAct step callbacks — watch the agent think
///   6.  HuggingFace cloud inference — any HF model, no download
///   7.  Ollama local server — on-device LAN inference
///   8.  On-device Gemma — fully offline, dart:ffi
///   9.  On-device GGUF (llama.cpp) — fully offline GGUF models
///  10.  Safety layer — input guard, output guard, rate limiter
///  11.  Smart routing — primary/fallback + privacy router
///  12.  AgenticHub — one-line model loading from any source
///
/// Run with:
///   flutter run -d macos   # or android, ios, windows, linux
///
/// Set your API keys in the const block at the top of each example file,
/// or pass them via --dart-define:
///   flutter run --dart-define=GEMINI_KEY=your_key ...
library;

import 'package:flutter/material.dart';

import 'examples/quick_start_example.dart';
import 'examples/streaming_example.dart';
import 'examples/tool_calling_example.dart';
import 'examples/memory_example.dart';
import 'examples/react_steps_example.dart';
import 'examples/hf_inference_example.dart';
import 'examples/ollama_example.dart';
import 'examples/safety_example.dart';
import 'examples/routing_example.dart';
import 'examples/agentic_hub_example.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgenticExampleApp());
}

class AgenticExampleApp extends StatelessWidget {
  const AgenticExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'genesis_ai_sdk Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const ExampleHome(),
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  static const _examples = <(String, String, Widget)>[
    ('Quick Start', '🚀  Basic single-turn chat with Gemini', QuickStartExample()),
    ('Streaming', '📡  Token-by-token streaming output', StreamingExample()),
    ('Tool Calling', '🔧  Calculator + custom weather tool', ToolCallingExample()),
    ('Memory', '💾  Multi-turn conversation with history', MemoryExample()),
    ('ReAct Steps', '🧠  Watch the agent think step by step', ReactStepsExample()),
    ('HF Inference', '🤗  Any HF model — no download needed', HFInferenceExample()),
    ('Ollama', '🦙  Local Ollama server inference', OllamaExample()),
    ('Safety', '🛡️  Input guard, output guard, rate limiter', SafetyExample()),
    ('Smart Routing', '🗺️  Fallback + privacy-aware routing', RoutingExample()),
    ('AgenticHub', '🏠  One-line model loading from any source', AgenticHubExample()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('genesis_ai_sdk'),
        centerTitle: true,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _examples.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final (title, subtitle, page) = _examples[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => page),
              ),
            ),
          );
        },
      ),
    );
  }
}
