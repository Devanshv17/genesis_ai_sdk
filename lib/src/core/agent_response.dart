import 'agent_step.dart';

/// The final result returned by a AgenticAgent after completing its work.
sealed class AgentResponse {
  /// All steps the agent took to arrive at this response.
  final List<AgentStep> steps;
  const AgentResponse(this.steps);
}

/// A plain text response from the agent.
class TextAgentResponse extends AgentResponse {
  final String text;
  const TextAgentResponse(this.text, List<AgentStep> steps) : super(steps);

  @override
  String toString() => text;
}

/// The agent hit max iterations without producing a final answer.
class MaxIterationsResponse extends AgentResponse {
  const MaxIterationsResponse(super.steps);
}

/// An error response — something went wrong during execution.
class ErrorAgentResponse extends AgentResponse {
  final String message;
  final Object? error;
  const ErrorAgentResponse(this.message, List<AgentStep> steps, [this.error])
      : super(steps);
}
