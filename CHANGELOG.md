# Changelog

All notable changes to `flutter_agents` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] — 2026-06-12

### Changed
- **Package renamed** from `genesis_ai_sdk` to `flutter_agents` — new import:
  `import 'package:flutter_agents/flutter_agents.dart';`
- Version bumped to 1.0.0 to reflect production-ready stability (311 tests, 160/160 pub.dev score)

### Roadmap (upcoming packages under the flutter_agents umbrella)
- `flutter_agents_graph` — LangGraph-style stateful agent graphs with cycles and checkpointing
- `flutter_agents_ui` — Flutter widgets for agent step visualisation and human-in-the-loop gates
- `flutter_agents_tools` — Pre-built real-world tools (location, camera, clipboard, contacts)
- `flutter_agents_memory` — Semantic / vector memory for long-running agents

---

## [0.2.0] — 2026-06-06

### Added

#### Per-Call Routing
- `PolicyRouter` — routes **every call independently** across any number of
  providers using ordered, user-defined rules. The call site never changes;
  each task is served by whichever provider the rules choose (cheap/private
  tasks on-device, hard reasoning in the cloud).
- `RouteRules` — ready-made rules: `sensitive()` (PII keywords stay local),
  `shortInput()`, `longContext()`, `needsTools()`, `streaming()`, `custom()`.
- `RouteContext` — per-call info exposed to rules (messages, tools,
  latest user message, total context length, streaming flag).
- `RouteDecision` + `onRoute` callback — observe every routing decision for
  logging, cost dashboards, or a "running locally 🔒 / cloud ☁️" UI badge.
- Automatic fallback to the default provider when a routed provider fails.
- `GenesisAgent.chat()` / `chatStream()` now accept an optional `provider`
  override to force a specific provider **for that call only**.

#### Flows (Genkit-inspired)
- `GenesisFlow` — chain multi-step AI pipelines with named, typed, observable
  steps: `GenesisFlow.start<String>('trip-planner').then(...).map(...)`.
- `FlowContext` — shared state between steps (`ctx.set()` / `ctx.get()`).
- `FlowEvent` (`FlowStepStarted` / `FlowStepCompleted` / `FlowStepFailed`) —
  live progress events for step-by-step UI.
- `FlowException` — failures carry the flow + step name for fast debugging.

### Improved
- `SmartRouter.stream()` now falls back to the secondary provider when the
  primary stream fails before emitting output (previously: no fallback).

---

## [0.1.1] — 2026-05-29

### Fixed

- Shortened pubspec description to meet pub.dev requirements (improves pub score from 150 to 160)

---

## [0.1.0] — 2026-05-25

### Added

#### Core
- `GenesisAgent` — unified agent API with `chat()`, `stream()`, tool calling,
  and multi-turn memory.
- `GenesisHub` — one-stop factory: `fromHuggingFace()`, `fromUrl()`,
  `fromOllama()`, `fromHFCloud()`, `fromFile()`, `fromProvider()`.
- `GenesisHubPlatformPaths.platformModelsDir()` — returns the correct writable
  model directory on every platform (uses `path_provider`).

#### Providers
- `GemmaProvider` — on-device inference via `flutter_gemma` 0.16.x; supports
  `.litertlm` (all platforms), `.task` (mobile), `.tflite`, `.bin`.
- `LlamaCppProvider` — on-device GGUF inference via `llama_cpp_dart` 0.2.x;
  supports macOS, Windows, Linux, Android.
- `HFInferenceProvider` — cloud inference via the HF Inference Router with
  multi-backend support: `featherless` (default), `nebius`, `together`,
  `sambanova`, `hfNative`.
- `OllamaProvider` — local Ollama server with `pull()`, `listModels()`,
  and `checkStatus()`.
- `GeminiProvider` — Google Gemini API (cloud).
- `OpenAIProvider` — OpenAI API (cloud, any OpenAI-compatible endpoint).
- `AnthropicProvider` — Anthropic Claude API (cloud).

#### Hub / Model Management
- `ModelFormat` — enum covering all formats: `litertlm`, `task`, `gguf`,
  `tflite`, `binary`, `safetensors`, `onnx`, `ollama`, `hfInference`, with
  auto-detection via `ModelFormat.detect()`.
- `HFHub` — HuggingFace Hub client: `modelInfo()`, `listFiles()`,
  `downloadUrl()`, `parseUrl()`, `inferenceUrl()`.
- `UniversalModelManager` — `downloadFromUrl()`, `downloadFromHF()`,
  `pullOllamaModel()`, `providerForFile()`, `isDownloaded()`, `deleteModel()`.

#### Tools & ReAct
- `GenesisTool` / `ToolParam` — define callable tools with typed parameters.
- ReAct loop with configurable max steps and graceful fallback.

#### Memory
- `InMemoryStore` — lightweight in-process message history.
- `HiveMemoryStore` — persistent cross-session memory backed by Hive.

#### Safety
- `InputGuard` — block / rewrite prompts before they reach the model.
- `OutputGuard` — validate / sanitize model responses.
- `RateLimiter` — token-bucket rate limiting.
- `ConcurrencyLimiter` — cap parallel requests.

#### Routing
- `SmartRouter` — latency/quality-based provider selection.
- `PrivacyRouter` — route sensitive prompts to on-device providers
  automatically.

#### Platform
- Full platform support table (`litertlm` on all platforms, `task` on mobile
  only, `gguf` on all except iOS pending xcframework build).
- `PLATFORM_SETUP.md` — step-by-step setup guide for macOS, iOS, Android,
  Windows, Linux.

[0.1.0]: https://github.com/Devanshv17/genesis_ai/releases/tag/v0.1.0
