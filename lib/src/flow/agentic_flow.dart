/// Genkit-inspired flows: chain multi-step AI pipelines with named,
/// observable, type-safe steps.
library;

/// Shared state available to every step in a flow run.
///
/// Use [set]/[get] to pass side-channel data between steps without
/// threading it through every return value.
class FlowContext {
  final Map<String, dynamic> _state = {};

  /// Name of the flow this run belongs to.
  final String flowName;

  FlowContext._(this.flowName);

  /// Stores [value] under [key] for later steps.
  void set(String key, dynamic value) => _state[key] = value;

  /// Reads a value stored by an earlier step, or `null`.
  T? get<T>(String key) => _state[key] as T?;
}

/// Lifecycle event emitted as a flow runs — feed these straight into a
/// progress UI ("Extracting… ✓  Planning… ⏳").
sealed class FlowEvent {
  /// Name of the step this event refers to.
  final String step;
  const FlowEvent(this.step);
}

/// A step has started.
class FlowStepStarted extends FlowEvent {
  const FlowStepStarted(super.step);
}

/// A step finished successfully with [output].
class FlowStepCompleted extends FlowEvent {
  final dynamic output;
  final Duration elapsed;
  const FlowStepCompleted(super.step, this.output, this.elapsed);
}

/// A step threw [error]; the flow stops here.
class FlowStepFailed extends FlowEvent {
  final Object error;
  const FlowStepFailed(super.step, this.error);
}

class _FlowStep {
  final String name;
  final Future<dynamic> Function(dynamic input, FlowContext ctx) run;
  const _FlowStep(this.name, this.run);
}

/// A typed, named pipeline of async steps — chain agent calls, tool runs,
/// parsing, and validation into one observable unit.
///
/// Inspired by Genkit's flows, adapted for Flutter apps: each step is named
/// (for logging/UI), typed (the compiler checks step N's output feeds
/// step N+1's input), and observable via [run]'s `onEvent`.
///
/// ```dart
/// final tripPlanner = AgenticFlow.start<String>('trip-planner')
///     .then<String>('extract-city', (input, ctx) async {
///       final r = await extractorAgent.chat('Extract the city: $input');
///       return r.text;
///     })
///     .then<String>('fetch-weather', (city, ctx) async {
///       ctx.set('city', city);
///       return await weatherApi.forecast(city);
///     })
///     .then<String>('write-plan', (weather, ctx) async {
///       final city = ctx.get<String>('city');
///       final r = await plannerAgent.chat(
///           'Plan a day in $city. Weather: $weather');
///       return r.text;
///     });
///
/// final plan = await tripPlanner.run(
///   'I want to visit Tokyo tomorrow',
///   onEvent: (e) => print(e), // live progress for the UI
/// );
/// ```
class AgenticFlow<I, O> {
  /// Flow name, used in events and error messages.
  final String name;
  final List<_FlowStep> _steps;

  AgenticFlow._(this.name, this._steps);

  /// Begins a new flow whose input type is `T`.
  static AgenticFlow<T, T> start<T>(String name) =>
      AgenticFlow<T, T>._(name, const []);

  /// Appends a step that transforms this flow's output [O] into [T].
  ///
  /// Steps run strictly in order; each receives the previous step's output
  /// and the shared [FlowContext].
  AgenticFlow<I, T> then<T>(
    String stepName,
    Future<T> Function(O input, FlowContext ctx) fn,
  ) =>
      AgenticFlow<I, T>._(name, [
        ..._steps,
        _FlowStep(stepName, (input, ctx) async => await fn(input as O, ctx)),
      ]);

  /// Appends a synchronous transform — handy for parsing and validation.
  AgenticFlow<I, T> map<T>(
    String stepName,
    T Function(O input, FlowContext ctx) fn,
  ) =>
      then<T>(stepName, (input, ctx) async => fn(input, ctx));

  /// Runs the flow with [input], returning the final step's output.
  ///
  /// [onEvent] fires on every step start/finish/failure so the app can show
  /// live progress. A failing step stops the flow and rethrows its error
  /// wrapped in [FlowException] (with the step name for debugging).
  Future<O> run(
    I input, {
    void Function(FlowEvent event)? onEvent,
  }) async {
    final ctx = FlowContext._(name);
    dynamic current = input;

    for (final step in _steps) {
      onEvent?.call(FlowStepStarted(step.name));
      final stopwatch = Stopwatch()..start();
      try {
        current = await step.run(current, ctx);
        onEvent?.call(
            FlowStepCompleted(step.name, current, stopwatch.elapsed));
      } catch (e) {
        onEvent?.call(FlowStepFailed(step.name, e));
        throw FlowException(flowName: name, stepName: step.name, cause: e);
      }
    }
    return current as O;
  }
}

/// Thrown when a flow step fails; carries the flow and step names so logs
/// point straight at the failing stage.
class FlowException implements Exception {
  final String flowName;
  final String stepName;
  final Object cause;

  const FlowException({
    required this.flowName,
    required this.stepName,
    required this.cause,
  });

  @override
  String toString() =>
      'FlowException(flow: $flowName, step: $stepName): $cause';
}
