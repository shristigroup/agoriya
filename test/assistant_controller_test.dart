import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:agoriya/features/assistant/assistant_config.dart';
import 'package:agoriya/features/assistant/assistant_controller.dart';
import 'package:agoriya/features/assistant/assistant_models.dart';
import 'package:agoriya/features/assistant/credit_store.dart';
import 'package:agoriya/features/assistant/llm_client.dart';

/// A model that plays back scripted turns (or runs a function for each call).
class FakeLlm implements LlmClient {
  final List<Future<Turn> Function(List<Turn> history)> script;
  int calls = 0;
  bool cancelled = false;
  List<List<Turn>> seen = [];
  FakeLlm(this.script);

  @override
  Future<Turn> generate(List<Turn> history,
      {required String systemPrompt,
      required String model,
      required List<ToolSpec> tools}) {
    seen.add(List.of(history));
    final i = calls++;
    return script[i < script.length ? i : script.length - 1](history);
  }

  @override
  void cancel() => cancelled = true;
}

Future<Turn> say(String t) async => Turn.model(text: t);
Future<Turn> call(String name, [Map<String, dynamic> args = const {}]) async =>
    Turn.model(calls: [ToolCall(name, args)]);

class FakeCredits implements CreditStore {
  int used;
  final List<Map<String, dynamic>> entries = [];
  FakeCredits([this.used = 0]);
  @override
  Future<int> usedToday() async => used;
  @override
  Future<bool> tryUse(int limit) async {
    if (used >= limit) return false;
    used++;
    return true;
  }

  @override
  Future<void> log(Map<String, dynamic> entry) async => entries.add(entry);
}

AssistantController make(
  FakeLlm llm, {
  FakeCredits? credits,
  AssistantConfig config = const AssistantConfig(),
  List<AssistantAction> actions = const [],
  DateTime Function()? now,
}) =>
    AssistantController(
      llm: llm,
      credits: credits ?? FakeCredits(),
      config: config,
      actions: actions,
      now: now,
    );

AssistantAction readAction(String name, Map<String, dynamic> data) =>
    AssistantAction(
        name: name,
        description: 'reads $name',
        run: (_) async => ActionOutcome.data(data));

String lastText(AssistantController c) =>
    c.messages.lastWhere((m) => m.role == ChatRole.assistant && m.text.isNotEmpty).text;

void main() {
  test('a plain answer costs one credit', () async {
    final credits = FakeCredits();
    final c = make(FakeLlm([(_) => say('Hello owner')]), credits: credits);
    await c.init();
    await c.send('hi');
    expect(lastText(c), 'Hello owner');
    expect(credits.used, 1);
    expect(c.creditsLeft, 99);
    expect(c.messages.last.text, 'Used 1 credit · 99 left today');
  });

  test('an action runs, its result goes back to the model, each call costs a credit', () async {
    final credits = FakeCredits();
    final llm = FakeLlm([
      (_) => call('list_shifts'),
      (h) {
        final tool = h.lastWhere((t) => t.role == 'tool');
        return say('You have ${tool.result!['count']} shifts');
      },
    ]);
    final c = make(llm,
        credits: credits, actions: [readAction('list_shifts', {'count': 2})]);
    await c.init();
    await c.send('show my shifts');
    expect(lastText(c), 'You have 2 shifts');
    expect(credits.used, 2);
  });

  test('a write only proposes; nothing runs until Confirm, and Confirm runs once', () async {
    var applied = 0;
    final action = AssistantAction(
      name: 'delete_shift',
      description: 'd',
      run: (_) async => ActionOutcome.proposal(Proposal(
        title: 'Delete Morning',
        lines: const ['Removes the shift'],
        apply: () async {
          applied++;
          return 'Deleted';
        },
      )),
    );
    final llm = FakeLlm([
      (_) => call('delete_shift'),
      (h) {
        expect(h.last.result!['status'], 'proposed');
        return say('Please review the card and tap Confirm.');
      },
    ]);
    final c = make(llm, actions: [action]);
    await c.init();
    await c.send('delete the morning shift');
    expect(applied, 0);
    final proposal = c.messages.firstWhere((m) => m.proposal != null).proposal!;
    await c.confirm(proposal);
    await c.confirm(proposal); // a second tap does nothing
    expect(applied, 1);
    expect(proposal.state, ProposalState.done);
    expect(proposal.result, 'Deleted');
  });

  test('an action the model invents is refused, and the model is told', () async {
    final llm = FakeLlm([
      (_) => call('drop_database'),
      (h) {
        expect(h.last.result!['error'], contains('no action called drop_database'));
        return say("Sorry, I can't do that.");
      },
    ]);
    final c = make(llm);
    await c.init();
    await c.send('x');
    expect(lastText(c), "Sorry, I can't do that.");
  });

  test('calls per prompt are capped, and a capped prompt is logged', () async {
    final credits = FakeCredits();
    final llm = FakeLlm([(_) => call('loop')]); // never stops asking
    final c = make(llm,
        credits: credits, actions: [readAction('loop', {'x': 1})]);
    await c.init();
    await c.send('endless');
    expect(llm.calls, 6);
    expect(credits.used, 6);
    expect(lastText(c), contains('too many steps'));
    expect(credits.entries.single['kind'], 'too_many_steps');
  });

  test('no credits left: the model is not called', () async {
    final llm = FakeLlm([(_) => say('hi')]);
    final c = make(llm, credits: FakeCredits(100));
    await c.init();
    await c.send('hi');
    expect(llm.calls, 0);
    expect(lastText(c), contains('come back tomorrow'));
    expect(c.creditsLeft, 0);
  });

  test('a slow call times out, is cancelled and logged; credits stay used', () async {
    final credits = FakeCredits();
    final llm = FakeLlm([(_) => Completer<Turn>().future]);
    final c = make(llm,
        credits: credits,
        config: const AssistantConfig(callTimeoutSeconds: 1));
    await c.init();
    await c.send('hi');
    expect(llm.cancelled, true);
    expect(lastText(c), contains('took too long'));
    expect(credits.used, 1);
    expect(credits.entries.single['reason'], 'call_timeout');
  });

  test('Stop abandons the call and runs no action afterwards', () async {
    var ran = false;
    final completer = Completer<Turn>();
    final llm = FakeLlm([(_) => completer.future]);
    final c = make(llm, actions: [
      AssistantAction(
          name: 'a',
          description: 'a',
          run: (_) async {
            ran = true;
            return const ActionOutcome.data({});
          })
    ]);
    await c.init();
    final sending = c.send('hi');
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, true);
    c.stop();
    completer.complete(Turn.model(calls: [const ToolCall('a', {})]));
    await sending;
    expect(llm.cancelled, true);
    expect(ran, false);
    expect(lastText(c), 'Stopped.');
    expect(c.busy, false);
  });

  test('cannot_help logs the request as declined', () async {
    final credits = FakeCredits();
    final llm = FakeLlm([
      (_) => call(kCannotHelp, {'reason': 'performance ranking'}),
      (_) => say('I cannot rank performance, but I can show attendance.'),
    ]);
    final c = make(llm, credits: credits);
    await c.init();
    await c.send('who is my best performer?');
    expect(credits.entries.single, containsPair('kind', 'declined'));
    expect(credits.entries.single['text'], 'who is my best performer?');
    expect(credits.entries.single['reason'], 'performance ranking');
    expect(lastText(c), contains('attendance'));
  });

  test('only the last 10 prompts are sent, and old ones drop their raw action results', () async {
    final llm = FakeLlm([(_) => call('x'), (_) => say('first answer')]);
    final c = make(llm, actions: [readAction('x', {'big': 'data'})]);
    await c.init();
    await c.send('prompt 0');
    final answerAt = llm.script.length;
    llm.script
      ..clear()
      ..add((_) => say('ok'));
    llm.calls = 0;
    for (var i = 1; i <= 11; i++) {
      await c.send('prompt $i');
    }
    final sent = llm.seen.last;
    final userTexts = sent.where((t) => t.role == 'user').map((t) => t.text).toList();
    expect(userTexts.length, AssistantController.maxPromptsSent);
    expect(userTexts.first, 'prompt 2');
    expect(userTexts.last, 'prompt 11');
    expect(answerAt, 2);
    // the first prompt's tool call is long gone from what is sent
    expect(sent.any((t) => t.role == 'tool'), false);
  });

  test('a new day starts a fresh chat and refreshes credits', () async {
    var now = DateTime.utc(2026, 11, 28, 10, 0); // 15:30 IST on the 28th
    final credits = FakeCredits(40);
    final llm = FakeLlm([(_) => say('a'), (_) => say('b')]);
    final c = make(llm, credits: credits, now: () => now);
    await c.init();
    await c.send('today');
    expect(c.messages.any((m) => m.text == 'today'), true);
    credits.used = 0;
    now = DateTime.utc(2026, 11, 28, 19, 0); // 00:30 IST on the 29th
    await c.send('tomorrow');
    expect(c.messages.any((m) => m.text == 'today'), false);
    expect(c.messages.any((m) => m.text == 'New day, starting a fresh chat.'), true);
    expect(llm.seen.last.where((t) => t.role == 'user').length, 1);
    expect(c.creditsLeft, 99);
  });

}
