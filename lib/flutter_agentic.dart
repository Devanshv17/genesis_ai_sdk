/// flutter_agentic — Build AI agents in Flutter. Local and cloud, one API.
///
/// ## Quick start
/// ```dart
/// import 'package:flutter_agentic/flutter_agentic.dart';
///
/// // 1. Register your providers (once at startup)
/// await AgenticAI.init(
///   providers: {
///     'gemini': GeminiProvider(apiKey: 'YOUR_GEMINI_KEY'),
///     'claude': AnthropicProvider(apiKey: 'YOUR_ANTHROPIC_KEY'),
///   },
///   defaultProviderKey: 'gemini',
/// );
///
/// // 2. Create an agent
/// final agent = AgenticAgent(
///   provider: AgenticAI.defaultProvider,
///   systemPrompt: 'You are a helpful assistant.',
///   tools: AgenticTools.all,
/// );
///
/// // 3. Chat
/// final response = await agent.chat('What is 25 * 4?');
/// print(response.text);
/// ```
library;

// ── Core ─────────────────────────────────────────────────────────────────────
export 'src/core/message.dart';
export 'src/core/agent_response.dart';
export 'src/core/agent_step.dart';
export 'src/core/context_manager.dart';
export 'src/core/model_config.dart';
export 'src/core/agentic_logger.dart';
export 'src/core/agentic_ai.dart';

// ── Tools ────────────────────────────────────────────────────────────────────
export 'src/tools/tool_param.dart';
export 'src/tools/tool_args.dart';
export 'src/tools/tool_context.dart';
export 'src/tools/tool_result.dart';
export 'src/tools/agentic_tool.dart';
export 'src/tools/agentic_tools.dart';

// ── Providers ────────────────────────────────────────────────────────────────
export 'src/providers/llm_provider.dart';
export 'src/providers/gemini_provider.dart';
export 'src/providers/openai_provider.dart';
export 'src/providers/anthropic_provider.dart';
export 'src/providers/ollama_provider.dart';
export 'src/providers/retry_provider.dart';
// GemmaProvider / GemmaModelManager / ModelDownloadException are excluded from
// the web-safe barrel because flutter_gemma pulls in dart:ffi which breaks
// web builds.  Import them directly on native targets:
//   import 'package:flutter_agentic/src/providers/gemma_provider.dart';
//
// LlamaCppProvider is similarly excluded (requires llama_cpp_dart + FFI):
//   import 'package:flutter_agentic/src/providers/llama_cpp_provider.dart';

// ── Memory ───────────────────────────────────────────────────────────────────
export 'src/memory/memory_store.dart';
export 'src/memory/in_memory_store.dart';
export 'src/memory/hive_memory_store.dart';

// ── Executor ─────────────────────────────────────────────────────────────────
export 'src/executor/react_executor.dart';

// ── Router ───────────────────────────────────────────────────────────────────
export 'src/router/smart_router.dart';
export 'src/router/policy_router.dart'; // per-call routing: PolicyRouter, RouteRules

// ── Flow — Genkit-style step chaining ────────────────────────────────────────
export 'src/flow/agentic_flow.dart'; // AgenticFlow, FlowContext, FlowEvent

// ── Safety ───────────────────────────────────────────────────────────────────
export 'src/safety/input_guard.dart';
export 'src/safety/output_guard.dart';
export 'src/safety/rate_limiter.dart';

// ── Agent — main public API ───────────────────────────────────────────────────
export 'src/agent/agentic_agent.dart';

// ── Hub — universal model download + routing ──────────────────────────────────
// ModelFormat and HFHub are web-safe (pure Dart / http).
// UniversalModelManager and AgenticHub use dart:io so they are excluded from
// web builds — import them directly when targeting native:
//   import 'package:flutter_agentic/src/hub/agentic_hub.dart';
//   import 'package:flutter_agentic/src/hub/universal_model_manager.dart';
export 'src/hub/model_format.dart';   // ModelFormat enum + UnsupportedFormatException
export 'src/hub/hf_hub.dart';         // HFHub, HFFile, HFModelInfo, HFException
export 'src/providers/hf_inference_provider.dart'; // HFInferenceProvider (cloud)
