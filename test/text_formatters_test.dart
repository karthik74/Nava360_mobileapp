import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nava360/core/text_formatters.dart';

TextEditingValue _fmt(String text, {int? cursor}) {
  const formatter = TitleCaseTextFormatter();
  return formatter.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor ?? text.length),
    ),
  );
}

void main() {
  group('TitleCaseTextFormatter', () {
    test('capitalizes a single word', () {
      expect(_fmt('hello').text, 'Hello');
    });

    test('capitalizes every word', () {
      expect(_fmt('hello world').text, 'Hello World');
      expect(_fmt('john doe').text, 'John Doe');
      expect(_fmt('good morning everyone').text, 'Good Morning Everyone');
      expect(_fmt('my name is raghunandan').text, 'My Name Is Raghunandan');
    });

    test('handles pasted multi-line paragraphs', () {
      expect(
        _fmt('dear sir,\ngood morning to all\nregards team'),
        isA<TextEditingValue>().having(
          (v) => v.text,
          'text',
          'Dear Sir,\nGood Morning To All\nRegards Team',
        ),
      );
    });

    test('keeps the cursor position when editing mid-text', () {
      // User typed "w" into "Hello orld" at index 6 → cursor sits at 7.
      final out = _fmt('Hello world', cursor: 7);
      expect(out.text, 'Hello World');
      expect(out.selection.baseOffset, 7);
    });

    test('leaves already-correct text untouched (no rebuild)', () {
      const value = TextEditingValue(
        text: 'Hello World',
        selection: TextSelection.collapsed(offset: 5),
      );
      final out = const TitleCaseTextFormatter()
          .formatEditUpdate(TextEditingValue.empty, value);
      expect(identical(out, value), isTrue);
    });

    test('does not touch mid-word capitals, digits or symbols', () {
      expect(_fmt('call McDonald at 9am (urgent)').text,
          'Call McDonald At 9am (Urgent)');
      expect(_fmt('HR + IT dept').text, 'HR + IT Dept');
    });

    test('handles empty input', () {
      expect(_fmt('').text, '');
    });
  });

  group('UpperCaseTextFormatter', () {
    test('upper-cases everything typed or pasted', () {
      const formatter = UpperCaseTextFormatter();
      final out = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(
          text: 'emp-0001',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      expect(out.text, 'EMP-0001');
      expect(out.selection.baseOffset, 8);
    });
  });
}
