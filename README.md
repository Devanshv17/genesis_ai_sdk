# flutter_agentic — Flutter AI Agent SDK

[![pub package](https://img.shields.io/pub/v/flutter_agentic.svg)](https://pub.dev/packages/flutter_agentic)
[![pub points](https://img.shields.io/pub/points/flutter_agentic)](https://pub.dev/packages/flutter_agentic/score)
[![likes](https://img.shields.io/pub/likes/flutter_agentic)](https://pub.dev/packages/flutter_agentic)
[![Platform](https://img.shields.io/badge/platform-android%20%7C%20ios%20%7C%20macos%20%7C%20windows%20%7C%20linux%20%7C%20web-blue)](https://pub.dev/packages/flutter_agentic)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**The Flutter AI agent SDK — build tool-calling AI agents, multi-step LLM pipelines, and on-device / cloud hybrid apps in Flutter.**

flutter_agentic gives Flutter developers a single, clean API across 7 AI providers — Gemini, OpenAI, Anthropic, HuggingFace, Ollama, on-device Gemma, and GGUF (llama.cpp). ReAct reasoning loop, per-call routing, observable multi-step flows, persistent memory, and a full safety layer — all Flutter-first, no backend required.

👉 **[View on pub.dev](https://pub.dev/packages/flutter_agentic)** · [GitHub](https://github.com/Devanshv17/flutter_agentic) · [PLATFORM_SETUP.md](PLATFORM_SETUP.md)

---

## Why use this Flutter AI SDK?

- **One API, every provider** — swap Gemini for Ollama for on-device Gemma with one line
- **True ReAct agent loop** — the agent reasons, calls tools, observes results, and repeats
- **Per-call routing** — `PolicyRouter` routes each request cloud/on-device by your rules
- **Multi-step flows** — `AgenticFlow` chains LLM calls into named, observable pipelines
- **Production-ready safety** — PII redaction, rate limiting, input/output guards built-in
- **Full offline support** — run Gemma or any GGUF model entirely on-device, no internet

---

## Features

| Feature | Description |
|---|---|
| 🧠 **ReAct agent loop** | Reasons → calls tools → observes → repeats until done |
| 🔌 **7 AI providers** | Gemini, OpenAI, Anthropic, HuggingFace (cloud), Ollama (local server), on-device Gemma, on-device GGUF (llama.cpp) |
| 🧭 **Per-call routing** | `PolicyRouter` — route each call cloud/on-device by your own rules *(NEW in 0.2.0)* |
| 🔗 **AI flows** | `AgenticFlow` — chain multi-step AI pipelines with named, observable steps *(NEW in 0.2.0)* |
| 🛠️ **Built-in tools** | Calculator, date/time, HTTP fetch, mock weather — zero config |
| 🔧 **Custom tools** | Type-safe `AgenticTool.define()` with auto JSON Schema |
| 💾 **Persistent memory** | `HiveMemoryStore` — history survives app restarts |
| 🔁 **Smart retry** | Exponential backoff on 429 / 5xx with `RetryProvider` |
| 🚦 **Safety layer** | Input guard, PII redaction, rate limiter, concurrency limiter |
| 🗺️ **Model registry** | Pre-configured context windows & costs for 20+ models |
| 📡 **Streaming** | Token-by-token streaming for all cloud providers |
| 🌐 **Web safe** | Cloud providers work on web; on-device excluded automatically |

---

## Installation

```yaml
dependencies:
  flutter_agentic: ^1.0.0
```

Or directly from source:

```yaml
dependencies:
  flutter_agentic:
    git:
      url: https://github.com/Devanshv17/flutter_agentic
```

---

## Quick start — Flutter AI agent in 10 lines

```dart
import 'package:flutter_agentic/flutter_agentic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AgenticAI.init(
    providers: {
      'gemini': GeminiProvider(apiKey: 'YOUR_GEMINI_API_KEY'),
    },
    defaultProviderKey: 'gemini',
  );

  final agent = AgenticAgent(
    provider: AgenticAI.defaultProvider,
    systemPrompt: 'You are a helpful Flutter AI assistant.',
    tools: AgenticTools.all,   // calculator + dateTime + httpRequest + mockWeather
  );

  final response = await agent.chat('What is 1337 * 42?');
  print(response.text); // → "The answer is 56154."
}
```

---

## AI Providers

### Gemini (Google)

```dart
GeminiProvider(
  apiKey: 'YOUR_KEY',
  model: 'gemini-2.0-flash',   // default
)
```

Get a free key at [aistudio.google.com](https://aistudio.google.com).

### OpenAI

```dart
OpenAIProvider(
  apiKey: 'YOUR_KEY',
  model: 'gpt-4o-mini',   // default
)
```

### Anthropic (Claude)

```dart
AnthropicProvider(
  apiKey: 'YOUR_KEY',
  model: 'claude-haiku-4-5',   // default — fast & cheap
)
```

### Ollama (local server — desktop / LAN)

```dart
OllamaProvider(model: 'llama3.2')    // localhost:11434

final status = await OllamaProvider(model: 'phi4').checkStatus();
if (!status.isReady) print(status.reason);
```

1. Install: <https://ollama.ai>
2. Pull: `ollama pull llama3.2`
3. Ollama starts automatically — no extra config needed.

### On-device Gemma (Android / iOS / macOS / Windows)

```dart
import 'package:flutter_agentic/src/providers/gemma_provider.dart';

final path = '/data/user/0/com.example.app/files/gemma-3n.task';
if (await GemmaModelManager.isDownloaded(path)) {
  final provider = GemmaProvider(
    modelId: 'gemma-3n-e2b-it',
    modelPath: path,
    supportImage: true,
  );
}

final url = GemmaModelManager.downloadUrl('gemma-3n-e2b-it');
final sizeMb = GemmaModelManager.approximateSizeMb('gemma-3n-e2b-it'); // 1100
```

Supported model IDs: `gemma-3n-e2b-it`, `gemma-3n-e4b-it`, `gemma-3-1b-it`,
`function-gemma-270m`, `phi-4-mini`, `qwen3-0.6b`, `smollm-135m`.

> `GemmaProvider` uses `dart:ffi` — import it directly and guard with `if (!kIsWeb)`.

### HuggingFace Inference (cloud — any HF model, no download)

```dart
final provider = HFInferenceProvider(
  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
  apiToken: 'hf_xxxx',   // free at huggingface.co/settings/tokens
);

final agent = AgenticHub.fromHFCloud(
  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
  apiToken: 'hf_xxxx',
  systemPrompt: 'You are a helpful assistant.',
);
```

| Backend | Best for |
|---|---|
| `featherless` (default) | Virtually all public HF models |
| `nebius` | Large / quantised models |
| `together` | Llama, Mixtral, popular OSS |
| `sambanova` | Very fast Llama inference |
| `hfNative` | HF's own GPU fleet |

### On-device GGUF / llama.cpp (Android / macOS / Windows / Linux)

```dart
import 'package:flutter_agentic/src/providers/llama_cpp_provider.dart';

final provider = LlamaCppProvider(
  modelPath: '/path/to/model.gguf',
  nCtx: 2048,
  nThreads: 4,
);

// Or auto-detect via AgenticHub:
final agent = await AgenticHub.fromFile('/path/to/model.gguf');
final reply = await agent.chat('What is the capital of France?');
```

```dart
final modelsDir = await AgenticHub.platformModelsDir();
// Android: /data/user/0/com.example.app/files/genesis_models
// iOS/macOS: <NSApplicationSupport>/genesis_models
// Windows/Linux: <ApplicationSupport>/genesis_models
```

> `LlamaCppProvider` requires `dart:ffi`. Import it directly. GGUF on iOS needs `llama.cpp` as an xcframework — see `PLATFORM_SETUP.md`.

---

## Custom tools

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
    return (await fetchWeather(city, unit)).toJson();
  },
);

final agent = AgenticAgent(
  provider: myProvider,
  tools: [weatherTool, AgenticTools.calculator],
);
```

### ToolParam types

| Constructor | JSON Schema type |
|---|---|
| `ToolParam.string(name, desc)` | `string` |
| `ToolParam.number(name, desc)` | `number` (double) |
| `ToolParam.integer(name, desc)` | `integer` |
| `ToolParam.boolean(name, desc)` | `boolean` |
| `ToolParam.stringEnum(name, desc, values)` | `string` + `enum` |
| `ToolParam.array(name, desc, items)` | `array` |
| `ToolParam.object(name, desc, props)` | `object` |

---

## Persistent memory

```dart
await HiveMemoryStore.initialize();

final agent = AgenticAgent(
  provider: myProvider,
  memory: HiveMemoryStore(),
  sessionId: 'user_${userId}',
);

await agent.clearHistory();
final history = await agent.getHistory();
```

Use `InMemoryStore()` (default) for ephemeral memory.

---

## Streaming

```dart
final agent = AgenticAgent(provider: myProvider);

await for (final chunk in agent.chatStream('Tell me a story.')) {
  stdout.write(chunk);
}
```

---

## ReAct step callbacks

```dart
final response = await agent.chat(
  'What is the weather in Tokyo and what is 100^0.5?',
  onStep: (step) {
    switch (step) {
      case ThinkingStep(:final thought):
        print('💭 $thought');
      case ToolCallStep(:final toolName, :final arguments):
        print('🔧 calling $toolName($arguments)');
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

---

## Safety layer

```dart
// Input guard — blocks empty, too-long, and injected inputs
final guard = InputGuard();
final clean = guard.validate(userInput);
final strict = InputGuard.withInjectionDetection();

// Output guard — PII redaction, truncation, blocklists
final safe = OutputGuard.withPiiRedaction();
final text = safe.process(rawLlmText);

// Rate limiter + concurrency cap
final limiter = RateLimiter(maxRequests: 20, windowDuration: Duration(minutes: 1));
limiter.check(sessionId);

final concurrency = ConcurrencyLimiter(maxConcurrent: 3);
final response = await concurrency.run(userId, () => agent.chat(message));
```

---

## Smart routing & fallback

```dart
// Fallback to secondary if primary fails
final router = SmartRouter(
  primary: GeminiProvider(apiKey: '...'),
  secondary: OllamaProvider(model: 'llama3.2'),
);

// Strip PII before sending to the cloud
final privacyRouter = PrivacyRouter(
  cloudProvider: OpenAIProvider(apiKey: '...'),
  sensitiveKeys: ['email', 'phone', 'ssn'],
);
```

---

## Per-call routing — PolicyRouter *(NEW in 0.2.0)*

`SmartRouter` picks one backend at init; `PolicyRouter` re-decides **on every call** — cheap / private / offline-friendly tasks stay on-device, hard reasoning goes to the cloud. Your agent call sites never change:

```dart
final router = PolicyRouter(
  providers: {
    'local': GemmaProvider(...),          // private, free, offline
    'cloud': GeminiProvider(apiKey: ''),  // smart, paid
  },
  defaultProvider: 'cloud',
  rules: [
    RouteRules.sensitive(useProvider: 'local'),   // PII stays on-device
    RouteRules.shortInput(useProvider: 'local'),  // small tasks stay local
    RouteRules.needsTools(useProvider: 'cloud'),  // tool calls need cloud
  ],
  onRoute: (d) => print(d), // log / show a "🔒 local" badge in your UI
);

final agent = AgenticAgent(provider: router); // call sites never change
```

Built-in rules: `sensitive()`, `shortInput()`, `longContext()`, `needsTools()`, `streaming()`, `custom()`.

Need a one-off override? Force a provider per call:

```dart
await agent.chat('My salary is 95k, plan my budget', provider: localGemma);
```

---

## AgenticFlow — multi-step AI pipelines *(NEW in 0.2.0)*

Chain agent calls, tool runs, and transforms into one named, type-safe, observable pipeline (inspired by Genkit flows, built Flutter-first):

```dart
final tripPlanner = AgenticFlow.start<String>('trip-planner')
    .then<String>('extract-city', (input, ctx) async {
      return (await extractor.chat('Extract the city: $input')).text;
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
  onEvent: (e) => print(e),  // FlowStepStarted / Completed / Failed → live UI
);
```

Failures throw `FlowException(flowName, stepName, cause)` — logs point straight at the failing stage.

---

## Retry on failures

```dart
final resilient = RetryProvider(
  inner: GeminiProvider(apiKey: '...'),
  maxAttempts: 3,
  initialDelayMs: 500,   // doubles each retry with ±25% jitter
);
```

---

## Model registry

```dart
final config = ModelRegistry.get('gemini-2.0-flash');
print(config.contextWindow);          // 1048576
print(config.inputCostPer1MTokens);  // 0.075

final manager = ContextManager.forModel('gemini-2.0-flash');
final fitted = manager.fit(messages);
```

---

## Logging

```dart
await AgenticAI.init(
  providers: { ... },
  logLevel: LogLevel.debug,
);

AgenticLogger.setHandler((level, message, [error]) {
  Crashlytics.instance.log('[$level] $message');
});
```

Default: `LogLevel.none` — silent in production.

---

## Platform support

| Platform | Cloud (Gemini / OpenAI / Anthropic / HF) | Ollama | On-device Gemma | On-device GGUF |
|---|:---:|:---:|:---:|:---:|
| Android | ✅ | ✅ | ✅ | ✅ |
| iOS | ✅ | ✅ | ✅ | ⚠️ xcframework needed |
| macOS | ✅ | ✅ | ✅ | ✅ |
| Windows | ✅ | ✅ | ✅ | ✅ |
| Web | ✅ | ❌ | ❌ | ❌ |
| Linux | ✅ | ✅ | ❌ | ✅ |

See [PLATFORM_SETUP.md](PLATFORM_SETUP.md) for native setup instructions per platform.

---

## The flutter_agentic family

flutter_agentic is an umbrella — companion packages extend the core SDK:

| Package | What it adds |
|---|---|
| [flutter_agentic_graph](https://pub.dev/packages/flutter_agentic_graph) | LangGraph-style stateful agent graphs — cycles, checkpointing, human-in-the-loop |
| [flutter_agentic_ui](https://pub.dev/packages/flutter_agentic_ui) | Drop-in chat UI — streaming bubbles, ReAct step visualizer, input bar |
| [flutter_agentic_tools](https://pub.dev/packages/flutter_agentic_tools) | Device tools — clipboard, sandboxed files, guarded HTTP, system info |
| [flutter_agentic_memory](https://pub.dev/packages/flutter_agentic_memory) | Semantic memory — embeddings, on-device vector search, long-term recall |

## Roadmap

- More providers: Mistral, Groq, Cohere, local llama.cpp server
- Parallel graph branches (fan-out / fan-in) in flutter_agentic_graph
- More device tools: location, camera, contacts

---

## License

MIT — see [LICENSE](LICENSE).
