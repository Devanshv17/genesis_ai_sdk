# genesis_ai_sdk

**A universal Flutter SDK for building AI agents — local and cloud.**

Add intelligent, tool-calling AI to any Flutter app in minutes. One clean API works across Gemini, OpenAI, Anthropic, Ollama (local server), and on-device Gemma models.

---

## Features

| Feature | Description |
|---|---|
| 🧠 **ReAct loop** | Agent reasons → calls tools → observes results → repeats until done |
| 🔌 **7 providers** | Gemini, OpenAI, Anthropic, HuggingFace (cloud), Ollama (local), on-device Gemma, on-device GGUF (llama.cpp) |
| 🧭 **Per-call routing** | `PolicyRouter` — route each call cloud/on-device by your own rules (NEW in 0.2.0) |
| 🔗 **Flows** | `GenesisFlow` — chain multi-step AI pipelines with named, observable steps (NEW in 0.2.0) |
| 🛠️ **Built-in tools** | Calculator, date/time, HTTP fetch, mock weather — zero config |
| 🔧 **Custom tools** | Type-safe `GenesisTool.define()` with auto JSON Schema |
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
  genesis_ai_sdk: ^0.2.0
```

Or, to use directly from source:

```yaml
dependencies:
  genesis_ai_sdk:
    git:
      url: https://github.com/Devanshv17/genesis_ai
      path: packages/genesis_ai
```

---

## Quick start

```dart
import 'package:genesis_ai_sdk/genesis_ai_sdk.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1 — Register providers once
  await GenesisAI.init(
    providers: {
      'gemini': GeminiProvider(apiKey: 'YOUR_GEMINI_API_KEY'),
    },
    defaultProviderKey: 'gemini',
  );

  // 2 — Create an agent
  final agent = GenesisAgent(
    provider: GenesisAI.defaultProvider,
    systemPrompt: 'You are a helpful assistant.',
    tools: GenesisTools.all,   // calculator + dateTime + httpRequest + mockWeather
  );

  // 3 — Chat
  final response = await agent.chat('What is 1337 * 42?');
  print(response.text); // → "The answer is 56154."
}
```

---

## Providers

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

// Check if Ollama is up and the model is pulled:
final status = await OllamaProvider(model: 'phi4').checkStatus();
if (!status.isReady) print(status.reason);
```

1. Install Ollama: <https://ollama.ai>
2. Pull a model: `ollama pull llama3.2`
3. Ollama starts automatically — no extra config needed.

### On-device Gemma (Android / iOS / macOS / Windows)

```dart
import 'package:genesis_ai_sdk/src/providers/gemma_provider.dart';

// Check the model exists on disk first
final path = '/data/user/0/com.example.app/files/gemma-3n.task';
if (await GemmaModelManager.isDownloaded(path)) {
  final provider = GemmaProvider(
    modelId: 'gemma-3n-e2b-it',
    modelPath: path,
    supportImage: true,
  );
}

// Download URL helper
final url = GemmaModelManager.downloadUrl('gemma-3n-e2b-it');
final sizeMb = GemmaModelManager.approximateSizeMb('gemma-3n-e2b-it'); // 1100
```

Supported model IDs: `gemma-3n-e2b-it`, `gemma-3n-e4b-it`, `gemma-3-1b-it`,
`function-gemma-270m`, `phi-4-mini`, `qwen3-0.6b`, `smollm-135m`.

> **Note:** `GemmaProvider` is not exported from the main barrel because
> `flutter_gemma` uses `dart:ffi` which breaks web builds. Import it directly
> from `package:genesis_ai_sdk/src/providers/gemma_provider.dart` and guard
> the usage with `if (!kIsWeb)`.

### HuggingFace Inference (cloud — any HF model, no download)

```dart
// Any public model on HuggingFace — no download or conversion needed:
final provider = HFInferenceProvider(
  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
  apiToken: 'hf_xxxx',   // free token at huggingface.co/settings/tokens
);

final agent = GenesisHub.fromHFCloud(
  modelId: 'Qwen/Qwen2.5-0.5B-Instruct',
  apiToken: 'hf_xxxx',
  systemPrompt: 'You are a helpful assistant.',
);
final reply = await agent.chat('Explain gravity in one sentence.');
```

**Backends** (set via `backend:` parameter):

| Backend | Best for |
|---|---|
| `featherless` (default) | Virtually all public HF models |
| `nebius` | Large / quantised models |
| `together` | Llama, Mixtral, popular OSS |
| `sambanova` | Very fast Llama inference |
| `hfNative` | HF's own GPU fleet (small curated list) |

### On-device GGUF / llama.cpp (Android / macOS / Windows / Linux)

```dart
import 'package:genesis_ai_sdk/src/providers/llama_cpp_provider.dart';

// Load a local .gguf model file:
final provider = LlamaCppProvider(
  modelPath: '/path/to/model.gguf',
  nCtx: 2048,    // context window
  nThreads: 4,   // CPU threads
);

// Or via GenesisHub — detects .gguf automatically:
final agent = await GenesisHub.fromFile('/path/to/model.gguf');
final reply = await agent.chat('What is the capital of France?');
```

Get the correct writable model directory on every platform:

```dart
final modelsDir = await GenesisHub.platformModelsDir();
// Android: /data/user/0/com.example.app/files/genesis_models
// iOS/macOS: <NSApplicationSupport>/genesis_models
// Windows/Linux: <ApplicationSupport>/genesis_models
```

> **Note:** `LlamaCppProvider` requires `dart:ffi` and is not in the main barrel.
> Import it directly: `import 'package:genesis_ai_sdk/src/providers/llama_cpp_provider.dart';`
> GGUF on iOS requires building `llama.cpp` as an xcframework — see `PLATFORM_SETUP.md`.

---

## Custom tools

```dart
final weatherTool = GenesisTool.define(
  name: 'get_weather',
  description: 'Returns current weather for a city.',
  params: [
    ToolParam.string('city', 'City name, e.g. "Mumbai"'),
    ToolParam.stringEnum('unit', 'Temperature unit', ['celsius', 'fahrenheit']),
  ],
  execute: (args) async {
    final city = args['city'] as String;
    final unit = args['unit'] as String? ?? 'celsius';
    final data = await fetchWeather(city, unit);   // your implementation
    return data.toJson();
  },
);

final agent = GenesisAgent(
  provider: myProvider,
  tools: [weatherTool, GenesisTools.calculator],
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

All constructors accept an optional `required` flag (default `true`).

---

## Memory (persistent history)

```dart
// Once at app startup
await HiveMemoryStore.initialize();

// Per agent
final agent = GenesisAgent(
  provider: myProvider,
  memory: HiveMemoryStore(),
  sessionId: 'user_${userId}',   // each user gets their own history
);

// Later
await agent.clearHistory();
final history = await agent.getHistory();
```

For ephemeral (in-process) memory, use the default `InMemoryStore()`.

---

## Streaming

```dart
final agent = GenesisAgent(provider: myProvider);

await for (final chunk in agent.chatStream('Tell me a story.')) {
  stdout.write(chunk);
}
```

---

## ReAct step callbacks

Watch the agent think in real time — great for showing a "thinking…" UI:

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

### Input guard

```dart
// Default: blocks empty messages and messages > 8 000 chars,
// strips control characters.
final guard = InputGuard();
final clean = guard.validate(userInput);   // throws InputGuardException if invalid

// Add prompt-injection detection (higher false-positive risk):
final strict = InputGuard.withInjectionDetection();
```

### Output guard

```dart
// Default: truncates at 32 000 chars.
final guard = OutputGuard();

// With PII redaction (emails, phones, credit cards, SSNs):
final safe = OutputGuard.withPiiRedaction();
final text = safe.process(rawLlmText);

// With a custom blocklist:
final branded = OutputGuard(extraRules: [
  BlocklistOutputRule(blocklist: ['competitor_name']),
]);
```

### Rate limiter

```dart
final limiter = RateLimiter(maxRequests: 20, windowDuration: Duration(minutes: 1));

// Throws RateLimitException if exceeded:
limiter.check(sessionId);
final response = await agent.chat(message);

// Concurrency limiter — cap parallel requests per user
final concurrency = ConcurrencyLimiter(maxConcurrent: 3);
final response = await concurrency.run(userId, () => agent.chat(message));
```

---

## Smart routing & fallback

```dart
// Falls back to secondary if primary fails:
final router = SmartRouter(
  primary: GeminiProvider(apiKey: '...'),
  secondary: OllamaProvider(model: 'llama3.2'),
);

// Anonymise sensitive fields before sending to the cloud:
final privacyRouter = PrivacyRouter(
  cloudProvider: OpenAIProvider(apiKey: '...'),
  sensitiveKeys: ['email', 'phone', 'ssn'],
);
```

---

## Per-call routing (NEW in 0.2.0)

`SmartRouter` picks a backend once; `PolicyRouter` decides **per call** —
so cheap/private/offline-friendly tasks run on-device and only the hard
ones hit the cloud. You define the policy; the agent code never changes:

```dart
final router = PolicyRouter(
  providers: {
    'local': GemmaProvider(...),          // private, free
    'cloud': GeminiProvider(apiKey: ''),  // smart, paid
  },
  defaultProvider: 'cloud',
  rules: [
    RouteRules.sensitive(useProvider: 'local'),   // PII stays on-device
    RouteRules.shortInput(useProvider: 'local'),  // small tasks stay local
    RouteRules.needsTools(useProvider: 'cloud'),  // tool calls need cloud
  ],
  onRoute: (d) => print(d), // log/badge every decision
);

final agent = GenesisAgent(provider: router); // call sites never change
```

Built-in rules: `sensitive()`, `shortInput()`, `longContext()`,
`needsTools()`, `streaming()`, `custom()` — or write any predicate over
`RouteContext`. A failing routed provider falls back to the default
automatically.

Need a one-off override instead of a policy? Force a provider per call:

```dart
await agent.chat('My salary is 95k, plan my budget', provider: localGemma);
```

---

## Flows — multi-step pipelines (NEW in 0.2.0)

Chain agent calls, tool runs, and parsing into one named, observable,
type-safe pipeline (inspired by Genkit's flows):

```dart
final tripPlanner = GenesisFlow.start<String>('trip-planner')
    .then<String>('extract-city', (input, ctx) async {
      final r = await extractor.chat('Extract the city: $input');
      return r.text;
    })
    .then<String>('fetch-weather', (city, ctx) async {
      ctx.set('city', city);                  // share state between steps
      return await weatherApi.forecast(city);
    })
    .then<String>('write-plan', (weather, ctx) async {
      final city = ctx.get<String>('city');
      final r = await planner.chat('Plan a day in $city. Weather: $weather');
      return r.text;
    });

final plan = await tripPlanner.run(
  'I want to visit Tokyo tomorrow',
  onEvent: (e) => print(e),  // FlowStepStarted / Completed / Failed → live UI
);
```

Failures throw `FlowException` carrying the flow + step name, so logs point
straight at the failing stage.

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
print(config.contextWindow);   // 1048576
print(config.inputCostPer1MTokens);  // 0.075

// Fit conversation history to a model's context window:
final manager = ContextManager.forModel('gemini-2.0-flash');
final fitted = manager.fit(messages);
```

---

## Logging

```dart
await GenesisAI.init(
  providers: { ... },
  logLevel: LogLevel.debug,   // verbose during development
);

// Or custom handler (send to Crashlytics, etc.):
GenesisLogger.setHandler((level, message, [error]) {
  Crashlytics.instance.log('[$level] $message');
});
```

Default log level is `LogLevel.none` — completely silent in production.

---

## Platform support

| Platform | Cloud (Gemini/OpenAI/Anthropic/HF) | Ollama | On-device Gemma (`.litertlm` / `.task`) | On-device GGUF (llama.cpp) |
|---|:---:|:---:|:---:|:---:|
| Android | ✅ | ✅ | ✅ | ✅ |
| iOS | ✅ | ✅ | ✅ | ⚠️ xcframework needed |
| macOS | ✅ | ✅ | ✅ | ✅ |
| Windows | ✅ | ✅ | ✅ | ✅ |
| Web | ✅ | ❌ | ❌ | ❌ |
| Linux | ✅ | ✅ | ❌ | ✅ |

> See `PLATFORM_SETUP.md` in the repo for per-platform native setup instructions.

---

## Roadmap

- `genesis_ai_ui` — dynamic Flutter UI renderer driven by AI responses (A2UI)
- `genesis_ai_tools` — real-world tools: device location, camera, clipboard, contacts
- More providers: Mistral, Groq, Cohere, local llama.cpp server
- Semantic memory with vector search

---

## License

MIT
