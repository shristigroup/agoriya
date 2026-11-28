/// Shared types for the AI assistant: chat messages, the turns sent to the
/// model, and the actions the model may ask the app to run.

enum ChatRole { user, assistant, note }

enum ProposalState { pending, running, done, cancelled, failed }

/// A change the assistant wants to make. Nothing is written until the owner
/// taps Confirm, which runs [apply].
class Proposal {
  final String title;
  final List<String> lines;
  final Future<String> Function() apply;
  ProposalState state = ProposalState.pending;
  String? result;

  Proposal({required this.title, required this.lines, required this.apply});
}

class ChatMessage {
  final ChatRole role;
  final String text;
  final Proposal? proposal;
  const ChatMessage(this.role, this.text, {this.proposal});
}

class ToolCall {
  final String name;
  final Map<String, dynamic> args;
  const ToolCall(this.name, this.args);
}

/// One entry of the conversation sent to the model.
/// role: 'user' | 'model' | 'tool'.
class Turn {
  final String role;
  final String? text;
  final List<ToolCall> calls;
  final String? toolName;
  final Map<String, dynamic>? result;

  /// The provider's own object for a model turn (kept so it can be sent back
  /// unchanged); null with a fake client.
  final Object? raw;

  const Turn.user(this.text)
      : role = 'user',
        calls = const [],
        toolName = null,
        result = null,
        raw = null;

  const Turn.model({this.text, this.calls = const [], this.raw})
      : role = 'model',
        toolName = null,
        result = null;

  const Turn.tool(this.toolName, this.result)
      : role = 'tool',
        text = null,
        calls = const [],
        raw = null;
}

enum ParamType { string, integer, number, boolean, stringList }

class ParamSpec {
  final ParamType type;
  final String description;
  final bool required;
  const ParamSpec(this.type, this.description, {this.required = true});
}

/// What running an action produced: data for the model, or a proposal (for a
/// write), or an error message.
class ActionOutcome {
  final Map<String, dynamic>? data;
  final Proposal? proposal;
  final String? error;
  const ActionOutcome.data(this.data)
      : proposal = null,
        error = null;
  const ActionOutcome.proposal(this.proposal)
      : data = null,
        error = null;
  const ActionOutcome.error(this.error)
      : data = null,
        proposal = null;
}

/// An action the model may ask for. Reads run at once; writes return a
/// proposal and run only on Confirm.
class AssistantAction {
  final String name;
  final String description;
  final Map<String, ParamSpec> params;
  final Future<ActionOutcome> Function(Map<String, dynamic> args) run;

  const AssistantAction({
    required this.name,
    required this.description,
    this.params = const {},
    required this.run,
  });
}

/// The name of the built-in action the model calls when nothing fits.
const String kCannotHelp = 'cannot_help';
