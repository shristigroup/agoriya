import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'assistant_config.dart';
import 'assistant_models.dart';
import 'credit_store.dart';
import 'ist_date.dart';
import 'llm_client.dart';

const String kDefaultSystemPrompt = '''
You are the TrackFolks assistant for the owner of an organisation. TrackFolks tracks field staff attendance. You help the owner manage shifts (a shift has an optional start and end time, an optional punch-in place, an optional punch-out place, and a list of people) and look at their team.

Rules:
- Use the actions provided for everything about the organisation. Never state a fact about people, shifts or attendance that did not come from an action result in this conversation. If you do not have the data, call an action or say you do not know.
- Changes (create, edit, delete, assign, remove) only produce a proposal that the owner must confirm with a button. Never say a change is done until the owner has confirmed. After proposing, tell the owner to review the card and tap Confirm.
- Times are India time. When you confirm a time, write it in 24-hour form (09:30). If a time is ambiguous (for example just "6"), ask.
- If two people could match a name, ask which one. Use people's names in replies, never their ids.
- To use a place in a shift, call find_place first, and ask the owner to pick when it is not obvious. Use only coordinates returned by find_place.
- If the request is not something the actions can do, call cannot_help with a short reason, then tell the owner in one or two sentences what you can do instead.
- Keep replies short and plain. Reply in the language the owner writes in.
''';

const String kOpeningMessage =
    'Hi! I can help you manage your team. Try things like:\n'
    '• "Create a Morning shift 9 to 6 at Reliance Mall and add everyone"\n'
    '• "Show my shifts" or "Who has no shift?"\n'
    '• "Move Ravi to the Evening shift"\n'
    '• "Who is punched in today?" or "Show Sunita\'s attendance this month"\n'
    'For a monthly export, use the export button on My Team.';

/// Runs the conversation: calls the model, runs the actions it asks for,
/// counts credits, and keeps the limits (calls per prompt, timeouts, Stop).
class AssistantController extends ChangeNotifier {
  AssistantController({
    required this.llm,
    required this.credits,
    required this.config,
    required List<AssistantAction> actions,
    DateTime Function()? now,
  })  : _actions = {for (final a in actions) a.name: a},
        _now = now ?? DateTime.now {
    _chatDate = istDateString(_now());
  }

  /// How many of the owner's recent messages are sent to the model.
  static const int maxPromptsSent = 10;

  final LlmClient llm;
  final CreditStore credits;
  final AssistantConfig config;
  final Map<String, AssistantAction> _actions;
  final DateTime Function() _now;

  final List<ChatMessage> messages = [];
  final List<Turn> _history = [];
  bool busy = false;
  int? creditsLeft;
  late String _chatDate;
  bool _stopped = false;
  int _usedThisPrompt = 0;
  final List<String> _toolsThisPrompt = [];

  Future<void> init() async {
    messages
      ..clear()
      ..add(const ChatMessage(ChatRole.assistant, kOpeningMessage));
    await _refreshCredits();
    notifyListeners();
  }

  Future<void> _refreshCredits() async {
    try {
      final used = await credits.usedToday();
      creditsLeft = (config.dailyCredits - used).clamp(0, config.dailyCredits);
    } catch (_) {
      creditsLeft = null;
    }
  }

  // ── Sending ───────────────────────────────────────────────────────────────

  Future<void> send(String text) async {
    text = text.trim();
    if (text.isEmpty || busy) return;
    await _resetIfNewDay();
    messages.add(ChatMessage(ChatRole.user, text));
    _history.add(Turn.user(text));
    busy = true;
    _stopped = false;
    _usedThisPrompt = 0;
    _toolsThisPrompt.clear();
    notifyListeners();
    final afterUser = _history.length;
    try {
      await _run(text, afterUser);
    } finally {
      busy = false;
      if (_usedThisPrompt > 0) {
        final left = creditsLeft;
        messages.add(ChatMessage(
            ChatRole.note,
            'Used $_usedThisPrompt ${_usedThisPrompt == 1 ? 'credit' : 'credits'}'
            '${left != null ? ' · $left left today' : ''}'));
      }
      notifyListeners();
    }
  }

  void _say(String text) {
    messages.add(ChatMessage(ChatRole.assistant, text));
    notifyListeners();
  }

  /// Drops the model/tool turns added since [keep] (an aborted prompt must not
  /// leave a request without its answer in the history).
  void _truncate(int keep) {
    if (_history.length > keep) _history.removeRange(keep, _history.length);
  }

  Future<void> _logUnhandled(String kind, String userText, [String? reason]) =>
      credits.log({
        'at': _now().toUtc().toIso8601String(),
        'kind': kind,
        'text': userText.length > 100 ? userText.substring(0, 100) : userText,
        if (reason != null) 'reason': reason.length > 100 ? reason.substring(0, 100) : reason,
        if (_toolsThisPrompt.isNotEmpty) 'tools': List<String>.from(_toolsThisPrompt),
      });

  Future<void> _run(String userText, int afterUser) async {
    final deadline = _now().add(Duration(seconds: config.promptTimeoutSeconds));
    var calls = 0;
    while (true) {
      if (_stopped) {
        _truncate(afterUser);
        _say('Stopped.');
        return;
      }
      if (_now().isAfter(deadline)) {
        _truncate(afterUser);
        _say('That is taking too long. Try a simpler question.');
        await _logUnhandled('error', userText, 'prompt_timeout');
        return;
      }
      if (calls >= config.maxCallsPerPrompt) {
        _truncate(afterUser);
        _say('That needs too many steps. Try a narrower question.');
        await _logUnhandled('too_many_steps', userText);
        return;
      }

      bool allowed;
      try {
        allowed = await credits.tryUse(config.dailyCredits);
      } catch (_) {
        _truncate(afterUser);
        _say('I could not check your credits. Please try again.');
        return;
      }
      if (!allowed) {
        creditsLeft = 0;
        _truncate(afterUser);
        _say(calls == 0
            ? "You've used all of today's AI credits. Please come back tomorrow."
            : "I ran out of today's AI credits before finishing. Please come back tomorrow.");
        return;
      }
      calls++;
      _usedThisPrompt++;
      if (creditsLeft != null) creditsLeft = (creditsLeft! - 1).clamp(0, 1 << 30);
      notifyListeners();

      Turn turn;
      try {
        turn = await llm
            .generate(
              _compact(_history),
              systemPrompt: _systemPrompt(),
              model: config.model,
              tools: _toolSpecs(),
            )
            .timeout(Duration(seconds: config.callTimeoutSeconds));
      } on TimeoutException {
        llm.cancel();
        _truncate(afterUser);
        _say('That took too long. Please try again.');
        await _logUnhandled('error', userText, 'call_timeout');
        return;
      } catch (e) {
        _truncate(afterUser);
        if (_stopped) {
          _say('Stopped.');
          return;
        }
        _say("I couldn't reach the AI service. Please try again in a moment.");
        await _logUnhandled('error', userText, e.toString());
        return;
      }
      if (_stopped) {
        _truncate(afterUser);
        _say('Stopped.');
        return;
      }

      _history.add(turn);
      final text = turn.text?.trim() ?? '';
      if (turn.calls.isEmpty) {
        _say(text.isEmpty ? "I'm not sure how to help with that." : text);
        return;
      }
      if (text.isNotEmpty) _say(text);

      for (final call in turn.calls) {
        if (_stopped) {
          _truncate(afterUser);
          _say('Stopped.');
          return;
        }
        _toolsThisPrompt.add(call.name);
        final result = await _execute(call, userText);
        _history.add(Turn.tool(call.name, result));
      }
    }
  }

  Future<Map<String, dynamic>> _execute(ToolCall call, String userText) async {
    if (call.name == kCannotHelp) {
      await _logUnhandled('declined', userText, call.args['reason']?.toString());
      return {'ok': true, 'note': 'Tell the owner briefly what you can do instead.'};
    }
    final action = _actions[call.name];
    if (action == null) return {'error': 'There is no action called ${call.name}.'};
    if (!config.actionEnabled(call.name)) {
      return {'error': 'This action is switched off for now. Tell the owner it is unavailable.'};
    }
    ActionOutcome outcome;
    try {
      outcome = await action.run(call.args);
    } catch (e) {
      return {'error': 'The action failed: ${e.toString().split('\n').first}'};
    }
    if (outcome.error != null) return {'error': outcome.error};
    final proposal = outcome.proposal;
    if (proposal != null) {
      messages.add(ChatMessage(ChatRole.assistant, '', proposal: proposal));
      notifyListeners();
      return {
        'status': 'proposed',
        'note': 'Shown to the owner with Confirm and Cancel buttons. Nothing has '
            'changed yet. Tell the owner to review it and tap Confirm.',
      };
    }
    final data = outcome.data ?? const <String, dynamic>{};
    if (jsonEncode(data).length > 8000) {
      return {'error': 'The result was too large. Ask the owner for something narrower.'};
    }
    return data;
  }

  // ── Proposals ─────────────────────────────────────────────────────────────

  Future<void> confirm(Proposal p) async {
    if (p.state != ProposalState.pending) return;
    p.state = ProposalState.running;
    notifyListeners();
    try {
      p.result = await p.apply();
      p.state = ProposalState.done;
      _history.add(Turn.user('[The owner confirmed: ${p.title}. Result: ${p.result}]'));
    } catch (e) {
      p.result = e.toString().split('\n').first;
      p.state = ProposalState.failed;
      _history.add(Turn.user('[Confirming "${p.title}" failed: ${p.result}]'));
    }
    notifyListeners();
  }

  void cancelProposal(Proposal p) {
    if (p.state != ProposalState.pending) return;
    p.state = ProposalState.cancelled;
    _history.add(Turn.user('[The owner cancelled: ${p.title}]'));
    notifyListeners();
  }

  // ── Stop / new day ────────────────────────────────────────────────────────

  void stop() {
    if (!busy) return;
    _stopped = true;
    llm.cancel();
    notifyListeners();
  }

  /// Each day starts a fresh chat (and the credits are a new day's too).
  Future<void> _resetIfNewDay() async {
    final today = istDateString(_now());
    if (today == _chatDate) return;
    _chatDate = today;
    _history.clear();
    messages
      ..clear()
      ..add(const ChatMessage(ChatRole.note, 'New day, starting a fresh chat.'))
      ..add(const ChatMessage(ChatRole.assistant, kOpeningMessage));
    await _refreshCredits();
  }

  // ── What is sent to the model ─────────────────────────────────────────────

  String _systemPrompt() {
    final t = _now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${config.systemPrompt ?? kDefaultSystemPrompt}\n'
        'Now: ${istDateString(_now())} $hh:$mm India time.';
  }

  List<ToolSpec> _toolSpecs() => [
        for (final a in _actions.values)
          ToolSpec(a.name, config.descriptionFor(a.name) ?? a.description, a.params),
        const ToolSpec(
          kCannotHelp,
          'Call this when the owner asks for something none of the other actions '
              'can do.',
          {'reason': ParamSpec(ParamType.string, 'Why none of the actions fit.')},
        ),
      ];

  /// The last [maxPromptsSent] messages. Older prompts keep only the owner's
  /// message and the final answer, not the actions' raw results.
  @visibleForTesting
  List<Turn> compactHistory() => _compact(_history);

  List<Turn> _compact(List<Turn> h) {
    final starts = [
      for (var i = 0; i < h.length; i++)
        if (h[i].role == 'user') i
    ];
    if (starts.isEmpty) return List.of(h);
    final from = starts.length > maxPromptsSent
        ? starts[starts.length - maxPromptsSent]
        : 0;
    final current = starts.last;
    final out = <Turn>[];
    for (var i = from; i < h.length; i++) {
      final t = h[i];
      if (i >= current) {
        out.add(t);
      } else if (t.role == 'user' ||
          (t.role == 'model' && t.calls.isEmpty && (t.text ?? '').isNotEmpty)) {
        out.add(t);
      }
    }
    return out;
  }
}
