import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/secure_storage.dart';

/// User-configurable voice-input preferences for the AI assistant.
/// Replies are text-only — there is no voice output.
class AssistantVoiceSettings {
  /// Input language code (en/hi/kn/ta/te/ml/mr/bn).
  final String language;

  /// Haptic feedback on voice interactions (accessibility).
  final bool haptics;

  const AssistantVoiceSettings({
    this.language = 'en',
    this.haptics = true,
  });

  AssistantVoiceSettings copyWith({String? language, bool? haptics}) =>
      AssistantVoiceSettings(
        language: language ?? this.language,
        haptics: haptics ?? this.haptics,
      );

  Map<String, dynamic> toJson() => {
        'language': language,
        'haptics': haptics,
      };

  factory AssistantVoiceSettings.fromJson(Map<String, dynamic> j) =>
      AssistantVoiceSettings(
        language: j['language'] as String? ?? 'en',
        haptics: j['haptics'] != false,
      );
}

class AssistantVoiceSettingsNotifier extends Notifier<AssistantVoiceSettings> {
  @override
  AssistantVoiceSettings build() {
    _load();
    return const AssistantVoiceSettings();
  }

  Future<void> _load() async {
    final raw = await SecureStorage.readAssistantVoiceJson();
    if (raw == null || raw.isEmpty) return;
    try {
      state = AssistantVoiceSettings.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt prefs — keep defaults.
    }
  }

  Future<void> update(AssistantVoiceSettings next) async {
    state = next;
    await SecureStorage.writeAssistantVoiceJson(jsonEncode(next.toJson()));
  }
}

final assistantVoiceSettingsProvider =
    NotifierProvider<AssistantVoiceSettingsNotifier, AssistantVoiceSettings>(
        AssistantVoiceSettingsNotifier.new);
