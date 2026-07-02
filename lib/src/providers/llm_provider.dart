import '../core/message.dart';
import '../tools/agentic_tool.dart';

/// A tool call requested by the model.
class ToolCall {
  final String toolName;
  final Map<String, dynamic> arguments;

  const ToolCall({required this.toolName, required this.arguments});
}

/// Result from a provider completion: either a text response OR a tool call request.
sealed class ProviderResult {}

class TextResult extends ProviderResult {
  final String text;
  TextResult(this.text);
}

class ToolCallResult extends ProviderResult {
  final ToolCall call;
  ToolCallResult(this.call);
}

/// Abstract base for all LLM providers (Gemini, OpenAI, local models, etc.).
///
/// Implement this to add a new provider to the SDK.
abstract class LlmProvider {
  /// Human-readable name of this provider, e.g. "Gemini 2.0 Flash".
  String get name;

  /// Returns either a text response or a tool call request.
  /// Pass [tools] to enable function calling.
  Future<ProviderResult> complete({
    required List<Message> messages,
    List<AgenticTool> tools = const [],
    double temperature = 0.7,
  });

  /// Streaming version — yields text tokens one by one.
  /// Tool calls are NOT streamed; use [complete] for those.
  Stream<String> stream({
    required List<Message> messages,
    double temperature = 0.7,
  });
}
