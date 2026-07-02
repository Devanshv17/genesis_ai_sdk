import 'dart:convert';

import '../core/agent_response.dart';
import '../core/agent_step.dart';
import '../core/message.dart';
import '../providers/llm_provider.dart';
import '../tools/agentic_tool.dart';

/// Runs the ReAct (Reasoning + Acting) loop:
///   Think → (optionally) call a tool → observe result → repeat → final answer.
///
/// The loop continues until:
///   - The model returns a plain text response (done), or
///   - [maxIterations] is reached (safety limit).
class ReActExecutor {
  final LlmProvider provider;
  final List<AgenticTool> tools;
  final int maxIterations;

  const ReActExecutor({
    required this.provider,
    this.tools = const [],
    this.maxIterations = 8,
  });

  /// Runs the agent loop for the given [messages] history.
  ///
  /// [onStep] is called after every step so the UI can show live progress
  /// (e.g. "Calling weather tool...", "Got result...").
  Future<AgentResponse> run({
    required List<Message> messages,
    void Function(AgentStep step)? onStep,
  }) async {
    // Work on a local copy so we don't mutate the caller's list.
    final history = List<Message>.of(messages);
    final steps = <AgentStep>[];

    for (int i = 0; i < maxIterations; i++) {
      try {
        final result = await provider.complete(
          messages: history,
          tools: tools,
        );

        if (result is TextResult) {
          final step = FinalResponseStep(result.text);
          steps.add(step);
          onStep?.call(step);
          return TextAgentResponse(result.text, steps);
        }

        if (result is ToolCallResult) {
          final call = result.call;

          // 1. Emit the tool-call step for the UI.
          final callStep = ToolCallStep(call.toolName, call.arguments);
          steps.add(callStep);
          onStep?.call(callStep);

          // 2. Find the tool.
          final tool = tools.cast<AgenticTool?>().firstWhere(
                (t) => t?.name == call.toolName,
                orElse: () => null,
              );

          Map<String, dynamic> toolResult;
          if (tool == null) {
            toolResult = {'error': 'Unknown tool: ${call.toolName}'};
          } else {
            try {
              toolResult = await tool.execute(call.arguments);
            } catch (e) {
              toolResult = {'error': 'Tool execution failed: $e'};
            }
          }

          // 3. Emit the result step.
          final resultStep = ToolResultStep(call.toolName, toolResult);
          steps.add(resultStep);
          onStep?.call(resultStep);

          // 4. Add both sides of the exchange to history so the model sees
          //    what it called and what it got back.
          history.add(Message.assistant(
            jsonEncode({'function_call': call.toolName, 'args': call.arguments}),
          ));
          history.add(Message.tool(call.toolName, jsonEncode(toolResult)));
        }
      } catch (e) {
        final step = ErrorStep('Provider error: $e', e);
        steps.add(step);
        onStep?.call(step);
        return ErrorAgentResponse('Provider error: $e', steps, e);
      }
    }

    return MaxIterationsResponse(steps);
  }
}
