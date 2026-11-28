import 'package:cloud_firestore/cloud_firestore.dart';

/// Settings for the assistant, from the Firestore doc Config/assistant so they
/// can change without an app release. Every field has a built-in default, so a
/// missing or broken doc still gives a working assistant.
class AssistantConfig {
  static const String defaultModel = 'gemini-3.8-flash';

  final bool enabled;
  final int dailyCredits;
  final int maxCallsPerPrompt;
  final int callTimeoutSeconds;
  final int promptTimeoutSeconds;
  final String model;

  /// Replaces the built-in system prompt when set.
  final String? systemPrompt;

  /// Per-action switches: {name: {enabled: bool, description: String}}.
  final Map<String, dynamic> actions;

  const AssistantConfig({
    this.enabled = true,
    this.dailyCredits = 100,
    this.maxCallsPerPrompt = 6,
    this.callTimeoutSeconds = 20,
    this.promptTimeoutSeconds = 45,
    this.model = defaultModel,
    this.systemPrompt,
    this.actions = const {},
  });

  factory AssistantConfig.fromMap(Map<String, dynamic>? m) {
    if (m == null) return const AssistantConfig();
    int intOr(String k, int d, {int min = 1}) {
      final v = (m[k] as num?)?.toInt();
      return (v == null || v < min) ? d : v;
    }

    return AssistantConfig(
      enabled: m['enabled'] as bool? ?? true,
      dailyCredits: intOr('dailyCredits', 100, min: 0),
      maxCallsPerPrompt: intOr('maxCallsPerPrompt', 6),
      callTimeoutSeconds: intOr('callTimeoutSeconds', 20),
      promptTimeoutSeconds: intOr('promptTimeoutSeconds', 45),
      model: (m['model'] as String?)?.trim().isNotEmpty == true
          ? (m['model'] as String).trim()
          : defaultModel,
      systemPrompt: (m['systemPrompt'] as String?)?.trim().isNotEmpty == true
          ? (m['systemPrompt'] as String).trim()
          : null,
      actions: m['actions'] is Map ? Map<String, dynamic>.from(m['actions']) : const {},
    );
  }

  bool actionEnabled(String name) {
    final a = actions[name];
    return !(a is Map && a['enabled'] == false);
  }

  String? descriptionFor(String name) {
    final a = actions[name];
    final d = a is Map ? a['description'] : null;
    return d is String && d.trim().isNotEmpty ? d.trim() : null;
  }

  /// Reads Config/assistant; any failure gives the defaults.
  static Future<AssistantConfig> load([FirebaseFirestore? db]) async {
    try {
      final doc = await (db ?? FirebaseFirestore.instance)
          .collection('Config')
          .doc('assistant')
          .get();
      return AssistantConfig.fromMap(doc.data());
    } catch (_) {
      return const AssistantConfig();
    }
  }
}
