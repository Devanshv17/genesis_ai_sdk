# flutter_agentic — Build AI Agents in Flutter

One unified API for Gemini, OpenAI, Anthropic, HuggingFace, Ollama, on-device Gemma, and GGUF models — with tool calling, memory, per-call routing, multi-step flows, and safety guardrails built in.

---

## The Problem

Building AI agents in Flutter is fragmented. Every provider has a different API shape. There's no standard way to switch between cloud and on-device inference. Tool calling, persistent memory, and safety guardrails are always custom implementations.

The result: developers rebuild the same plumbing for every project.

---

## What It Is

**flutter_agentic** is a universal Flutter SDK for building AI agents that run locally and in the cloud. One clean API. Seven providers. Zero vendor lock-in.

Supports:
- **Gemini** (Google)
- **OpenAI** (GPT-4o)
- **Anthropic** (Claude)
- **HuggingFace** (any public model, no download needed)
- **Ollama** (local server, no API key)
- **On-device Gemma** (fully offline)
- **On-device GGUF** via llama.cpp (fully offline)

Switch providers by changing one line. Your agent code stays the same.

---

## Installation

```yaml
dependencies:
  flutter_agentic: ^1.0.0
```

---

## Quick Start — 10 Lines of Code

```dart
import 'package:flutter_agentic/flutter_agentic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AgenticAI.init(
    providers: {'gemini': GeminiProvider(apiKey: 'YOUR_KEY')},
    defaultProviderKey: 'gemini',
  );

  final agent = AgenticAgent(
    provider: AgenticAI.defaultProvider,
    systemPrompt: 'You are a helpful assistant.',
    tools: [AgenticTools.calculator, AgenticTools.dateTime],
  );

  final response = await agent.chat('What is 1337 * 42, and what day is it?');
  print(response);
}
```

The agent figures out which tool to call, executes it, and returns the answer. No prompt engineering needed.

---

## The Features That Actually Matter

### Real Tool Calling — Not Just Text

The ReAct loop is fully implemented. The agent reasons → calls tools → observes results → repeats until it has a complete answer. An `onStep` callback fires for every intermediate step — perfect for building a "thinking…" UI.

```dart
final response = await agent.chat(
  'What is the weather in Tokyo and what is 100^0.5?',
  onStep: (step) {
    switch (step) {
      case ThinkingStep(:final thought):
        print('💭 $thought');
      case ToolCallStep(:final toolName, :final arguments):
        print('🔧 $toolName($arguments)');
      case ToolResultStep(:final toolName, :final result):
        print('✅ $toolName → $result');
      case FinalResponseStep(:final text):
        print('🏁 $text');
      case ErrorStep(:final message):
        print('❌ $message');
    }
  },
);
```

Custom tools are five lines:

```dart
final weatherTool = AgenticTool.define(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  params: [
    ToolParam.string('city', 'City name, e.g. "Mumbai"'),
    ToolParam.stringEnum('unit', 'Temperature unit', ['celsius', 'fahrenheit']),
  ],
  execute: (args) async {
    final city = args['city'] as String;
    final unit = args['unit'] as String? ?? 'celsius';
    return (await fetchWeather(city, unit)).toJson(); // must return Map<String,dynamic>
  },
);
```

### Any HuggingFace Model — No Download

```dart
final agent = AgenticHub.fromHFCloud(
  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
  apiToken: 'hf_xxxx', // free at huggingface.co/settings/tokens
);
final reply = await agent.chat('Explain transformers in one sentence.');
```

The HF Inference Router supports virtually all public HuggingFace models via multiple GPU backends (featherless, nebius, together, sambanova). No model download, no conversion, no GPU on your end. Free tier available with any HF account.

### Fully Offline — On-Device Models

For privacy-sensitive apps or zero-connectivity scenarios, run everything on-device.

**For Gemma (Android, iOS, macOS, Windows):**

```dart
import 'package:flutter_agentic/src/providers/gemma_provider.dart';

final dir = await AgenticHub.platformModelsDir();
// Android:       /data/user/0/com.example.app/files/genesis_models
// iOS / macOS:   <NSApplicationSupport>/genesis_models
// Windows/Linux: <ApplicationSupport>/genesis_models

final provider = GemmaProvider(
  modelId: 'gemma-3-1b-it',
  modelPath: '$dir/gemma-3-1b-it.task',
);
```

**For GGUF via llama.cpp (Android, macOS, Windows, Linux):**

```dart
import 'package:flutter_agentic/src/providers/llama_cpp_provider.dart';

final provider = LlamaCppProvider(modelPath: '/path/to/model.gguf');
```

`AgenticHub.platformModelsDir()` returns the correct writable path on every platform automatically — no more hardcoded paths that break on Android.

### Memory That Survives App Restarts

**In-process memory (current session only):**

```dart
memory: InMemoryStore()
```

**Persistent memory backed by Hive — survives app restarts:**

```dart
// main.dart — call once at startup, before any agents
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveMemoryStore.initialize(); // ← required before use
  runApp(const MyApp());
}

// Then in your widget / service:
final agent = AgenticAgent(
  provider: myProvider,
  memory: HiveMemoryStore(),      // no constructor args
  sessionId: 'user_$userId',      // sessionId lives on the agent
);

await agent.clearHistory();
final history = await agent.getHistory();
```

### Streaming

```dart
await for (final chunk in agent.chatStream('Tell me a story.')) {
  stdout.write(chunk);
}
```

Token-by-token streaming for all cloud providers.

### Safety Layer Built In

**Block prompt injection before it reaches the model:**

```dart
final clean = InputGuard.withInjectionDetection().validate(userInput);
```

**Redact PII from model responses (emails, phones, credit cards):**

```dart
final safe = OutputGuard.withPiiRedaction().process(rawOutput);
```

**Rate limiting per user:**

```dart
RateLimiter(maxRequests: 20, windowDuration: Duration(minutes: 1)).check(userId);
```

**Concurrency cap:**

```dart
final concurrency = ConcurrencyLimiter(maxConcurrent: 3);
final response = await concurrency.run(userId, () => agent.chat(message));
```

---

## The AgenticHub — One Line for Everything

**From HuggingFace cloud (no download):**

```dart
AgenticHub.fromHFCloud(modelId: 'Qwen/Qwen2.5-0.5B-Instruct', apiToken: '...')
```

**From a local model file (auto-detects .gguf / .litertlm / .task):**

```dart
await AgenticHub.fromFile('/path/to/model.gguf')
```

**From Ollama:**

```dart
await AgenticHub.fromOllama(model: 'llama3.2')
```

**From HuggingFace with auto-download to device:**

```dart
await AgenticHub.fromHuggingFace(
  repoId: 'litert-community/Qwen3-0.6B',
  destinationDir: await AgenticHub.platformModelsDir(),
  onProgress: (received, total) =>
      print('${(received / total * 100).toStringAsFixed(1)}%'),
)
```

---

## Per-Call Routing — PolicyRouter

`SmartRouter` picks one backend at init time. `PolicyRouter` **re-decides on every call** — cheap / private / offline-friendly tasks stay on-device, hard reasoning goes to the cloud. Your agent call sites never change:

```dart
final router = PolicyRouter(
  providers: {
    'local': GemmaProvider(modelId: 'gemma-3-1b-it', modelPath: '...'),
    'cloud': GeminiProvider(apiKey: 'YOUR_KEY'),
  },
  defaultProvider: 'cloud',
  rules: [
    RouteRules.sensitive(useProvider: 'local'),   // PII never leaves the device
    RouteRules.shortInput(useProvider: 'local'),  // small tasks stay local & free
    RouteRules.needsTools(useProvider: 'cloud'),  // tool calls need cloud reasoning
  ],
  onRoute: (decision) => print(decision), // log it, or show a 🔒 badge in your UI
);

final agent = AgenticAgent(provider: router); // call sites are unchanged
final response = await agent.chat('My salary is 95k, help me budget');
// → automatically routed to local because "salary" is a sensitive keyword
```

Built-in rules: `sensitive()`, `shortInput()`, `longContext()`, `needsTools()`, `streaming()`, `custom()`.

Force a specific provider for one call:

```dart
await agent.chat('Summarise this in one line.', provider: localGemma);
```

This is the feature that makes on-device inference practical — you don't have to choose between privacy and capability; the SDK routes each call to the right backend automatically.

---

## AgenticFlow — Multi-Step AI Pipelines

Chain agent calls, tool runs, and transforms into one named, type-safe, observable pipeline:

```dart
final tripPlanner = AgenticFlow.start<String>('trip-planner')
    .then<String>('extract-city', (input, ctx) async {
      return (await extractor.chat('Extract the city from: $input')).text;
    })
    .then<String>('fetch-weather', (city, ctx) async {
      ctx.set('city', city);
      return await weatherApi.forecast(city);
    })
    .then<String>('write-plan', (weather, ctx) async {
      final city = ctx.get<String>('city');
      return (await planner.chat('Plan a day in $city. Weather: $weather')).text;
    });

final plan = await tripPlanner.run(
  'I want to visit Tokyo tomorrow',
  onEvent: (e) => print(e), // FlowStepStarted / Completed / Failed → live UI updates
);
```

Failures throw `FlowException(flowName, stepName, cause)` — logs point straight at the failing stage.

---

## Smart Routing and Fallback

**Automatic fallback if the primary provider fails:**

```dart
final router = SmartRouter(
  primary: GeminiProvider(apiKey: '...'),
  secondary: OllamaProvider(model: 'llama3.2'),
);
```

**Privacy-first routing — anonymise sensitive fields before they leave the device:**

```dart
final router = PrivacyRouter(
  cloudProvider: OpenAIProvider(apiKey: '...'),
  sensitiveKeys: ['email', 'phone', 'ssn'],
);
```

**Smart retry with exponential backoff:**

```dart
final resilient = RetryProvider(
  inner: GeminiProvider(apiKey: '...'),
  maxAttempts: 3,
  initialDelayMs: 500, // doubles each retry with ±25% jitter
);
```

---

## Platform Support

| Platform | Cloud (Gemini / OpenAI / Anthropic / HF) | Ollama | On-device Gemma | GGUF / llama.cpp |
|---|:---:|:---:|:---:|:---:|
| Android | ✅ | ✅ | ✅ | ✅ |
| iOS | ✅ | ✅ | ✅ | ⚠️ xcframework needed |
| macOS | ✅ | ✅ | ✅ | ✅ |
| Windows | ✅ | ✅ | ✅ | ✅ |
| Web | ✅ | ❌ | ❌ | ❌ |
| Linux | ✅ | ✅ | ❌ | ✅ |

See [PLATFORM_SETUP.md](PLATFORM_SETUP.md) for native setup instructions per platform.

---

## What's on the Roadmap

- More providers: Mistral, Groq, Cohere
- Local llama.cpp server provider
- Parallel graph branches (fan-out / fan-in)
- More device tools: location, camera, contacts

---

## Links

- **pub.dev:** https://pub.dev/packages/flutter_agentic
- **GitHub:** https://github.com/Devanshv17/flutter_agentic

If this saved you time, a star on GitHub or a like on pub.dev helps more people find it.

---

#flutter #dart #ai #llm #sdk #agents #opensource
