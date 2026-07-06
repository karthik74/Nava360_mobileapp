import 'package:flutter/services.dart';

/// Shared input formatters — the single home for capitalization logic.
///
/// Usage on any text field:
/// ```dart
/// TextFormField(
///   textCapitalization: TextCapitalization.words, // keyboard hint
///   inputFormatters: const [TitleCaseTextFormatter()],
/// )
/// ```
///
/// Do NOT apply [TitleCaseTextFormatter] to: emails, passwords, OTP/PIN codes,
/// usernames/employee codes, URLs, phone numbers, numeric inputs, coupon/API
/// codes, or search fields that require exact-case matching.

/// Upper-cases the first letter of every word while typing or pasting.
///
/// `hello world` → `Hello World`. Only ASCII `a-z` at a word start is
/// changed; every other character (including mid-word capitals such as
/// `McDonald` or ALL-CAPS acronyms) is left untouched. The transformation
/// is length-preserving, so the caret and composing region carry over
/// unchanged — the cursor never jumps, even when editing mid-text.
class TitleCaseTextFormatter extends TextInputFormatter {
  const TitleCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    List<int>? codes; // allocated lazily, only when a change is needed
    var wordStart = true;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (wordStart && c >= 0x61 && c <= 0x7A) {
        codes ??= List<int>.of(text.codeUnits);
        codes[i] = c - 0x20; // a-z → A-Z
      }
      // A new word starts after whitespace or opening punctuation. An
      // apostrophe is deliberately NOT a boundary (don't → Don't) and a
      // digit is not either (9am stays 9am).
      wordStart = c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 // whitespace
          || c == 0x28 || c == 0x5B || c == 0x7B // ( [ {
          || c == 0x22 || c == 0x2F || c == 0x2D; // " / -
    }
    if (codes == null) return newValue; // already Title Case — no rebuild
    return newValue.copyWith(text: String.fromCharCodes(codes));
  }
}

/// Forces typed or pasted text to upper-case. Usernames are employee codes,
/// which are stored upper-case — this keeps sign-in working regardless of the
/// keyboard's auto-capitalisation state.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
