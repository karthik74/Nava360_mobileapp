/// Assistant voice-input languages: the 8 supported Indian-market languages
/// with their speech-to-text locale ids. Voice is input-only — replies are
/// shown as text, never spoken.

class AssistantLanguage {
  final String code; // en | hi | kn | ta | te | ml | mr | bn
  final String label; // shown in the picker, in its own script
  final String sttLocale; // speech_to_text locale id

  const AssistantLanguage(this.code, this.label, this.sttLocale);
}

const List<AssistantLanguage> kAssistantLanguages = [
  AssistantLanguage('en', 'English', 'en_IN'),
  AssistantLanguage('hi', 'हिन्दी', 'hi_IN'),
  AssistantLanguage('kn', 'ಕನ್ನಡ', 'kn_IN'),
  AssistantLanguage('ta', 'தமிழ்', 'ta_IN'),
  AssistantLanguage('te', 'తెలుగు', 'te_IN'),
  AssistantLanguage('ml', 'മലയാളം', 'ml_IN'),
  AssistantLanguage('mr', 'मराठी', 'mr_IN'),
  AssistantLanguage('bn', 'বাংলা', 'bn_IN'),
];

AssistantLanguage assistantLanguageByCode(String code) =>
    kAssistantLanguages.firstWhere((l) => l.code == code,
        orElse: () => kAssistantLanguages.first);

