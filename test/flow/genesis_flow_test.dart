import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_ai_sdk/genesis_ai_sdk.dart';

void main() {
  group('GenesisFlow', () {
    test('runs steps in order and returns final output', () async {
      final flow = GenesisFlow.start<int>('math')
          .then<int>('double', (n, ctx) async => n * 2)
          .then<String>('describe', (n, ctx) async => 'result: $n');

      final out = await flow.run(21);
      expect(out, 'result: 42');
    });

    test('map adds a synchronous step', () async {
      final flow = GenesisFlow.start<String>('parse')
          .map<int>('to-int', (s, ctx) => int.parse(s))
          .map<int>('inc', (n, ctx) => n + 1);

      expect(await flow.run('41'), 42);
    });

    test('FlowContext shares state between steps', () async {
      final flow = GenesisFlow.start<String>('ctx')
          .then<String>('store', (input, ctx) async {
            ctx.set('original', input);
            return input.toUpperCase();
          })
          .then<String>('recall', (upper, ctx) async {
            return '${ctx.get<String>('original')} → $upper';
          });

      expect(await flow.run('hi'), 'hi → HI');
    });

    test('emits start and complete events per step', () async {
      final events = <FlowEvent>[];
      final flow = GenesisFlow.start<int>('events')
          .then<int>('a', (n, ctx) async => n + 1)
          .then<int>('b', (n, ctx) async => n + 1);

      await flow.run(0, onEvent: events.add);

      expect(events, hasLength(4));
      expect(events[0], isA<FlowStepStarted>());
      expect(events[0].step, 'a');
      expect(events[1], isA<FlowStepCompleted>());
      expect((events[1] as FlowStepCompleted).output, 1);
      expect(events[2].step, 'b');
      expect((events[3] as FlowStepCompleted).output, 2);
    });

    test('failing step throws FlowException with step name', () async {
      final events = <FlowEvent>[];
      final flow = GenesisFlow.start<int>('boom')
          .then<int>('ok', (n, ctx) async => n)
          .then<int>('explode', (n, ctx) async => throw StateError('bad'));

      try {
        await flow.run(1, onEvent: events.add);
        fail('expected FlowException');
      } on FlowException catch (e) {
        expect(e.flowName, 'boom');
        expect(e.stepName, 'explode');
        expect(e.cause, isA<StateError>());
      }
      expect(events.last, isA<FlowStepFailed>());
      expect(events.last.step, 'explode');
    });

    test('flow with no steps returns input unchanged', () async {
      final flow = GenesisFlow.start<String>('identity');
      expect(await flow.run('same'), 'same');
    });
  });
}
