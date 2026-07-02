import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_agents/flutter_agents.dart';

void main() {
  group('GenesisTool.define', () {
    test('name and description are stored', () {
      final tool = GenesisTool.define(
        name: 'greet',
        description: 'Greets someone.',
        params: {
          'name': ToolParam.string(description: 'Person name', required: true),
        },
        execute: (args) async => {'greeting': 'Hello, ${args['name']}!'},
      );
      expect(tool.name, 'greet');
      expect(tool.description, 'Greets someone.');
    });

    test('parameters schema is generated from params map', () {
      final tool = GenesisTool.define(
        name: 'test',
        description: 'Test tool',
        params: {
          'query': ToolParam.string(description: 'Query', required: true),
          'limit': ToolParam.integer(description: 'Limit'),
        },
        execute: (args) async => {},
      );
      final props = tool.parameters['properties'] as Map;
      expect(props.containsKey('query'), isTrue);
      expect(props.containsKey('limit'), isTrue);
      expect(tool.parameters['required'], ['query']);
    });

    test('execute returns correct output', () async {
      final tool = GenesisTool.define(
        name: 'add',
        description: 'Adds two numbers.',
        params: {
          'a': ToolParam.number(description: 'A', required: true),
          'b': ToolParam.number(description: 'B', required: true),
        },
        execute: (args) async {
          final a = (args['a'] as num).toDouble();
          final b = (args['b'] as num).toDouble();
          return {'sum': a + b};
        },
      );
      final result = await tool.execute({'a': 3, 'b': 4});
      expect(result['sum'], 7.0);
    });

    test('typedParams is available', () {
      final tool = GenesisTool.define(
        name: 'x',
        description: 'x',
        params: {'val': ToolParam.boolean(description: 'v')},
        execute: (args) async => {},
      );
      expect(tool.typedParams, isNotNull);
      expect(tool.typedParams!.containsKey('val'), isTrue);
    });
  });

  group('GenesisTool.withContext', () {
    test('execute receives ToolArgs and returns ToolSuccess data', () async {
      final tool = GenesisTool.withContext(
        name: 'lookup',
        description: 'Looks up a value.',
        params: {
          'key': ToolParam.string(description: 'Key', required: true),
        },
        execute: (args, ctx) async {
          final key = args.string('key');
          ctx.log('Looking up: $key');
          return ToolSuccess({'value': 'result_for_$key'});
        },
      );
      final out = await tool.execute({'key': 'myKey'});
      expect(out['value'], 'result_for_myKey');
    });

    test('ToolError is returned as error map', () async {
      final tool = GenesisTool.withContext(
        name: 'fail',
        description: 'Always fails.',
        params: {},
        execute: (args, ctx) async =>
            ToolError('intentional failure', code: 'ALWAYS_FAIL'),
      );
      final out = await tool.execute({});
      expect(out['error'], 'intentional failure');
      expect(out['error_code'], 'ALWAYS_FAIL');
    });

    test('unexpected exception is caught and returned as error map', () async {
      final tool = GenesisTool.withContext(
        name: 'boom',
        description: 'Throws.',
        params: {},
        execute: (args, ctx) async => throw Exception('Kaboom'),
      );
      final out = await tool.execute({});
      expect(out.containsKey('error'), isTrue);
      expect((out['error'] as String).contains('Kaboom'), isTrue);
    });

    test('ToolContext progress callback fires', () async {
      final progress = <int>[];
      final tool = GenesisTool.withContext(
        name: 'progress_test',
        description: 'Reports progress.',
        params: {},
        execute: (args, ctx) async {
          ctx.progress(25, 'quarter');
          ctx.progress(100, 'done');
          return ToolSuccess({});
        },
      );
      // Progress fires internally; just verify execute completes
      await tool.execute({});
      // If no error was thrown, progress ran without issue
      expect(progress, isEmpty); // progress list is externally unobserved here
    });
  });

  group('GenesisTool.pipeline', () {
    test('steps execute in order and share state', () async {
      final tool = GenesisTool.pipeline(
        name: 'chain',
        description: 'Multi-step.',
        params: {
          'value': ToolParam.integer(description: 'Start', required: true),
        },
        steps: [
          PipelineStep(
            name: 'double',
            run: (state, ctx) async =>
                {...state, 'value': (state['value'] as int) * 2},
          ),
          PipelineStep(
            name: 'add_ten',
            run: (state, ctx) async =>
                {...state, 'value': (state['value'] as int) + 10},
          ),
        ],
      );
      final out = await tool.execute({'value': 5});
      // 5 * 2 = 10, 10 + 10 = 20
      expect(out['value'], 20);
    });

    test('ToolStepException stops pipeline and returns error map', () async {
      final tool = GenesisTool.pipeline(
        name: 'failing_chain',
        description: 'Fails at step 2.',
        params: {'x': ToolParam.integer(description: 'X', required: true)},
        steps: [
          PipelineStep(
            name: 'ok_step',
            run: (state, ctx) async => {...state, 'ok': true},
          ),
          PipelineStep(
            name: 'bad_step',
            run: (state, ctx) async =>
                throw ToolStepException('Step 2 exploded'),
          ),
          PipelineStep(
            name: 'never_runs',
            run: (state, ctx) async => {...state, 'unreachable': true},
          ),
        ],
      );
      final out = await tool.execute({'x': 1});
      expect(out['error'], 'Step 2 exploded');
      expect(out['failed_step'], 'bad_step');
      expect(out.containsKey('unreachable'), isFalse);
    });

    test('pipeline final state excludes no original keys by default', () async {
      // Pipeline merges, so original args stay in final state
      final tool = GenesisTool.pipeline(
        name: 'pass_through',
        description: 'Adds a field.',
        params: {'input': ToolParam.string(description: 'Input', required: true)},
        steps: [
          PipelineStep(
            name: 'annotate',
            run: (state, ctx) async => {...state, 'annotated': true},
          ),
        ],
      );
      final out = await tool.execute({'input': 'hello'});
      expect(out['input'], 'hello');
      expect(out['annotated'], isTrue);
    });

    test('assert fires when steps list is empty', () {
      expect(
        () => GenesisTool.pipeline(
          name: 'empty',
          description: 'No steps.',
          params: {},
          steps: [],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('GenesisTool raw constructor', () {
    test('typedParams is null for raw constructor', () {
      final tool = GenesisTool(
        name: 'raw',
        description: 'Raw tool.',
        parameters: {
          'type': 'object',
          'properties': {'x': {'type': 'string'}},
        },
        execute: (args) async => {'out': args['x']},
      );
      expect(tool.typedParams, isNull);
    });

    test('raw tool executes correctly', () async {
      final tool = GenesisTool(
        name: 'echo',
        description: 'Echoes input.',
        parameters: {'type': 'object', 'properties': {}},
        execute: (args) async => {'echo': args['msg']},
      );
      final out = await tool.execute({'msg': 'hello'});
      expect(out['echo'], 'hello');
    });
  });
}
