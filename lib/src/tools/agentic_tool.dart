import '../core/agentic_logger.dart';
import 'tool_args.dart';
import 'tool_context.dart';
import 'tool_param.dart';
import 'tool_result.dart';

/// Simple executor — takes raw args, returns raw map.
/// Compatible with all providers.
typedef ToolExecutorFn = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

/// Rich executor — receives [ToolArgs] and [ToolContext], returns [ToolResult].
/// Used with [AgenticTool.withContext].
typedef ToolExecutorWithContextFn = Future<ToolResult> Function(
    ToolArgs args, ToolContext ctx);

/// Defines a callable function the LLM agent can invoke.
///
/// ---
/// ## Three ways to define a tool
///
/// ### 1 — Simple (basic use cases)
/// ```dart
/// final greet = AgenticTool.define(
///   name: 'greet',
///   description: 'Greets a person by name.',
///   params: {
///     'name': ToolParam.string(description: 'The person to greet', required: true),
///   },
///   execute: (args) async => {'greeting': 'Hello, ${args['name']}!'},
/// );
/// ```
///
/// ### 2 — Rich context (recommended for real tools)
/// Gets typed arg access, structured error returns, and logging.
/// ```dart
/// final searchTool = AgenticTool.withContext(
///   name: 'search_products',
///   description: 'Searches the product catalogue.',
///   params: {
///     'query':    ToolParam.string(description: 'Search query', required: true),
///     'limit':    ToolParam.integer(description: 'Max results', required: false),
///     'category': ToolParam.stringEnum(
///       ['electronics', 'clothing', 'books'],
///       description: 'Filter by category',
///     ),
///   },
///   execute: (args, ctx) async {
///     ctx.log('Searching: ${args.string("query")}');
///     ctx.progress(0, 'Querying database...');
///
///     try {
///       final results = await db.search(
///         args.string('query'),
///         limit: args.integer('limit', fallback: 10),
///         category: args.optional<String>('category'),
///       );
///       ctx.progress(100, 'Found ${results.length} items');
///       return ToolSuccess({'results': results, 'count': results.length});
///     } on DatabaseException catch (e) {
///       ctx.warn('DB error: $e');
///       return ToolError('Search failed: ${e.message}', code: 'DB_ERROR', cause: e);
///     }
///   },
/// );
/// ```
///
/// ### 3 — Pipeline (multi-step sequential processes)
/// Each step receives the output of the previous step.
/// ```dart
/// final analysisTool = AgenticTool.pipeline(
///   name: 'analyse_document',
///   description: 'Fetches, extracts, and summarises a document.',
///   params: {
///     'url': ToolParam.string(description: 'Document URL', required: true),
///   },
///   steps: [
///     PipelineStep(
///       name: 'fetch',
///       description: 'Downloads the document',
///       run: (state, ctx) async {
///         ctx.progress(0, 'Downloading...');
///         final html = await http.read(Uri.parse(state['url'] as String));
///         return {...state, 'raw_html': html};
///       },
///     ),
///     PipelineStep(
///       name: 'extract',
///       description: 'Strips HTML tags',
///       run: (state, ctx) async {
///         ctx.progress(50, 'Extracting text...');
///         final text = stripHtml(state['raw_html'] as String);
///         return {...state, 'text': text};
///       },
///     ),
///     PipelineStep(
///       name: 'summarise',
///       description: 'Returns final output',
///       run: (state, ctx) async {
///         ctx.progress(100, 'Done');
///         return {'summary': (state['text'] as String).substring(0, 500)};
///       },
///     ),
///   ],
/// );
/// ```
class AgenticTool {
  /// Snake_case name. Must be unique within an agent. The LLM uses this.
  final String name;

  /// What this tool does and **when** to call it. The LLM reads this to decide.
  /// Be specific: "Call this when the user asks about X" is better than "Does X".
  final String description;

  /// JSON Schema `parameters` object sent to the LLM API.
  final Map<String, dynamic> parameters;

  /// Internal executor — always returns `Future<Map<String, dynamic>>`.
  final ToolExecutorFn execute;

  /// Typed param map (available when constructed via [define] or [withContext]).
  final Map<String, ToolParam>? _typedParams;

  // ── Constructors ──────────────────────────────────────────────────────────

  /// Raw constructor — full control over JSON Schema.
  ///
  /// Use this when you need schema features not covered by [ToolParam], or when
  /// migrating existing JSON Schema definitions.
  const AgenticTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  }) : _typedParams = null;

  AgenticTool._typed({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
    required Map<String, ToolParam> typedParams,
  }) : _typedParams = typedParams;

  // ── Factory: define (simple) ──────────────────────────────────────────────

  /// Creates a tool with type-safe [ToolParam] definitions and a simple executor.
  ///
  /// The JSON Schema is auto-generated — no manual map writing needed.
  ///
  /// ```dart
  /// AgenticTool.define(
  ///   name: 'get_stock_price',
  ///   description: 'Returns the current stock price for a ticker symbol.',
  ///   params: {
  ///     'ticker': ToolParam.string(description: 'e.g. AAPL, GOOG', required: true),
  ///     'currency': ToolParam.stringEnum(['USD','EUR','GBP'], description: 'Currency'),
  ///   },
  ///   execute: (args) async {
  ///     final price = await stockApi.getPrice(args['ticker'] as String);
  ///     return {'price': price, 'currency': args['currency'] ?? 'USD'};
  ///   },
  /// );
  /// ```
  factory AgenticTool.define({
    required String name,
    required String description,
    required Map<String, ToolParam> params,
    required ToolExecutorFn execute,
  }) {
    return AgenticTool._typed(
      name: name,
      description: description,
      parameters: buildParametersSchema(params),
      execute: execute,
      typedParams: params,
    );
  }

  // ── Factory: withContext (recommended for production) ─────────────────────

  /// Creates a tool with typed argument access, structured error returns, and
  /// execution context (logging + progress).
  ///
  /// The executor receives a [ToolArgs] accessor (no manual casting) and a
  /// [ToolContext] for logging and progress reporting.
  ///
  /// **Prefer this over [define] for any non-trivial tool.**
  ///
  /// ```dart
  /// AgenticTool.withContext(
  ///   name: 'send_message',
  ///   description: 'Sends a message to a user in the system.',
  ///   params: {
  ///     'recipient_id': ToolParam.string(description: 'User ID', required: true),
  ///     'message':      ToolParam.string(description: 'Text to send', required: true),
  ///     'priority':     ToolParam.stringEnum(['normal','high'], description: 'Priority'),
  ///   },
  ///   execute: (args, ctx) async {
  ///     final id  = args.string('recipient_id');
  ///     final msg = args.string('message');
  ///     ctx.log('Sending to $id: "$msg"');
  ///
  ///     if (id.isEmpty) return ToolError('recipient_id is required', code: 'MISSING_ARG');
  ///
  ///     try {
  ///       await messaging.send(id, msg, priority: args.oneOf('priority', ['normal','high'], fallback: 'normal'));
  ///       return ToolSuccess({'status': 'sent', 'recipient': id});
  ///     } on MessagingException catch (e) {
  ///       return ToolError(e.message, code: 'SEND_FAILED', cause: e);
  ///     }
  ///   },
  /// );
  /// ```
  factory AgenticTool.withContext({
    required String name,
    required String description,
    required Map<String, ToolParam> params,
    required ToolExecutorWithContextFn execute,
    String? sessionId,
  }) {
    return AgenticTool._typed(
      name: name,
      description: description,
      parameters: buildParametersSchema(params),
      typedParams: params,
      execute: (rawArgs) async {
        final args = ToolArgs(rawArgs);
        final ctx = ToolContext(
          toolName: name,
          sessionId: sessionId,
          logger: (lvl, message) {
              switch (lvl) {
                case 'debug':   AgenticLogger.debug('Tool:$name', message);
                case 'warn':    AgenticLogger.warning('Tool:$name', message);
                case 'error':   AgenticLogger.error('Tool:$name', message);
                default:        AgenticLogger.info('Tool:$name', message);
              }
            },
        );
        try {
          final result = await execute(args, ctx);
          return result.toMap();
        } catch (e, st) {
          AgenticLogger.error('Tool:$name', 'Unexpected error: $e\n$st');
          return {'error': 'Tool execution failed: $e'};
        }
      },
    );
  }

  // ── Factory: pipeline ────────────────────────────────────────────────────

  /// Creates a multi-step sequential tool.
  ///
  /// Steps are executed in order. Each step receives the combined state from
  /// all previous steps plus the original args. Returning from any step merges
  /// its output into the shared state map.
  ///
  /// If any step throws, the pipeline stops and returns the error.
  ///
  /// ```dart
  /// AgenticTool.pipeline(
  ///   name: 'process_order',
  ///   description: 'Validates, charges, and confirms an order.',
  ///   params: {
  ///     'order_id': ToolParam.string(description: 'Order ID', required: true),
  ///   },
  ///   steps: [
  ///     PipelineStep(
  ///       name: 'validate',
  ///       run: (state, ctx) async {
  ///         ctx.progress(10, 'Validating order...');
  ///         final order = await orders.get(state['order_id'] as String);
  ///         if (order == null) throw ToolStepException('Order not found');
  ///         return {...state, 'order': order.toMap()};
  ///       },
  ///     ),
  ///     PipelineStep(
  ///       name: 'charge',
  ///       run: (state, ctx) async {
  ///         ctx.progress(50, 'Processing payment...');
  ///         final chargeId = await payments.charge(state['order'] as Map);
  ///         return {...state, 'charge_id': chargeId};
  ///       },
  ///     ),
  ///     PipelineStep(
  ///       name: 'confirm',
  ///       run: (state, ctx) async {
  ///         ctx.progress(100, 'Confirmed');
  ///         return {'status': 'confirmed', 'charge_id': state['charge_id']};
  ///       },
  ///     ),
  ///   ],
  /// );
  /// ```
  factory AgenticTool.pipeline({
    required String name,
    required String description,
    required Map<String, ToolParam> params,
    required List<PipelineStep> steps,
  }) {
    assert(steps.isNotEmpty, 'Pipeline "$name" must have at least one step.');
    return AgenticTool._typed(
      name: name,
      description: description,
      parameters: buildParametersSchema(params),
      typedParams: params,
      execute: (rawArgs) async {
        Map<String, dynamic> state = Map<String, dynamic>.from(rawArgs);
        final ctx = ToolContext(
          toolName: name,
          logger: (lvl, message) {
              switch (lvl) {
                case 'debug':   AgenticLogger.debug('Pipeline:$name', message);
                case 'warn':    AgenticLogger.warning('Pipeline:$name', message);
                case 'error':   AgenticLogger.error('Pipeline:$name', message);
                default:        AgenticLogger.info('Pipeline:$name', message);
              }
            },
        );

        for (int i = 0; i < steps.length; i++) {
          final step = steps[i];
          try {
            AgenticLogger.debug('Pipeline:$name',
                'step ${i + 1}/${steps.length}: ${step.name}');
            final output = await step.run(state, ctx);
            // Merge step output into shared state
            state = {...state, ...output};
          } on ToolStepException catch (e) {
            AgenticLogger.warning('Pipeline:$name',
                'step "${step.name}" failed: ${e.message}');
            return {'error': e.message, 'failed_step': step.name};
          } catch (e, st) {
            AgenticLogger.error('Pipeline:$name',
                'step "${step.name}" threw unexpectedly: $e\n$st');
            return {'error': 'Step "${step.name}" failed: $e', 'failed_step': step.name};
          }
        }
        // Return only the final state keys (strip original args)
        return state;
      },
    );
  }

  // ── Accessors ─────────────────────────────────────────────────────────────

  /// The typed param map, if this tool was built with [define], [withContext],
  /// or [pipeline]. Null if raw JSON Schema was used.
  Map<String, ToolParam>? get typedParams => _typedParams;
}

// ── Pipeline helpers ──────────────────────────────────────────────────────────

/// A single step in a [AgenticTool.pipeline].
class PipelineStep {
  /// Short name for logging (e.g. `'fetch'`, `'validate'`, `'summarise'`).
  final String name;

  /// Executes this step.
  ///
  /// [state] contains original tool args + all outputs from previous steps.
  /// Return a map of new/updated values to merge into the shared state.
  final Future<Map<String, dynamic>> Function(
    Map<String, dynamic> state,
    ToolContext ctx,
  ) run;

  const PipelineStep({
    required this.name,
    required this.run,
  });
}

/// Throw inside a [PipelineStep] to stop the pipeline with a user-readable error.
class ToolStepException implements Exception {
  final String message;
  const ToolStepException(this.message);
  @override
  String toString() => 'ToolStepException: $message';
}
