import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'assistant_models.dart';

/// What the assistant needs from a language model: one call that takes the
/// conversation and the available actions, and returns text and/or requests
/// to run actions. Kept small so the provider can be swapped in one file.
abstract class LlmClient {
  Future<Turn> generate(
    List<Turn> history, {
    required String systemPrompt,
    required String model,
    required List<ToolSpec> tools,
  });

  /// Best effort: abandon the call in flight (the Stop button).
  void cancel();
}

class ToolSpec {
  final String name;
  final String description;
  final Map<String, ParamSpec> params;
  const ToolSpec(this.name, this.description, this.params);
}

/// Gemini through Firebase AI Logic (Gemini Developer API). The API key stays
/// on Firebase's side; App Check (see main.dart) protects it from other apps.
class FirebaseAiClient implements LlmClient {
  http.Client? _inFlight;

  Schema _schema(ParamSpec p) {
    switch (p.type) {
      case ParamType.integer:
        return Schema.integer(description: p.description);
      case ParamType.number:
        return Schema.number(description: p.description);
      case ParamType.boolean:
        return Schema.boolean(description: p.description);
      case ParamType.stringList:
        return Schema.array(
            description: p.description, items: Schema.string());
      case ParamType.string:
        return Schema.string(description: p.description);
    }
  }

  Content _content(Turn t) {
    switch (t.role) {
      case 'user':
        return Content.text(t.text ?? '');
      case 'tool':
        return Content.functionResponse(t.toolName!, t.result ?? const {});
      default:
        final raw = t.raw;
        if (raw is Content) return raw;
        return Content.model([
          if (t.text != null && t.text!.isNotEmpty) TextPart(t.text!),
          for (final c in t.calls) FunctionCall(c.name, c.args),
        ]);
    }
  }

  @override
  Future<Turn> generate(
    List<Turn> history, {
    required String systemPrompt,
    required String model,
    required List<ToolSpec> tools,
  }) async {
    final client = _inFlight = _CancellableClient();
    try {
      final generative = FirebaseAI.googleAI().generativeModel(
        model: model,
        systemInstruction: Content.system(systemPrompt),
        httpClient: client,
        tools: [
          Tool.functionDeclarations([
            for (final t in tools)
              FunctionDeclaration(
                t.name,
                t.description,
                parameters: {
                  for (final e in t.params.entries) e.key: _schema(e.value)
                },
                optionalParameters: [
                  for (final e in t.params.entries)
                    if (!e.value.required) e.key
                ],
              ),
          ]),
        ],
      );
      final response =
          await generative.generateContent(history.map(_content).toList());
      return Turn.model(
        text: response.text,
        calls: [
          for (final c in response.functionCalls)
            ToolCall(c.name, Map<String, dynamic>.from(c.args))
        ],
        raw: response.candidates.isNotEmpty ? response.candidates.first.content : null,
      );
    } finally {
      if (identical(_inFlight, client)) _inFlight = null;
    }
  }

  @override
  void cancel() {
    _inFlight?.close();
    _inFlight = null;
  }
}

/// An HTTP client that can be closed to abandon a request in flight.
class _CancellableClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _inner.send(request);

  @override
  void close() => _inner.close();
}
