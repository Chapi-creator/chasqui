import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/field_test.dart';
import 'package:sinred/src/rescue/morse.dart';

void main() {
  group('prueba de campo', () {
    test('cada nivel arma ocho palabras distintas', () {
      for (final level in fieldTestLevels) {
        final words = fieldTestWords(level, seed: 7);
        expect(words.length, fieldTestWordCount, reason: level);
        expect(words.toSet().length, words.length, reason: level);
      }
    });

    test('van de la más liviana a la más pesada', () {
      for (final level in fieldTestLevels) {
        final words = fieldTestWords(level, seed: 3);
        for (var i = 1; i < words.length; i++) {
          expect(
            fieldTestWeight(words[i]) >= fieldTestWeight(words[i - 1]),
            isTrue,
            reason: '$level: ${words[i - 1]} antes que ${words[i]}',
          );
        }
      }
    });

    test('una palabra con números no queda al principio', () {
      final words = fieldTestWords('Difícil', seed: 11);
      final firstNumber = words.indexWhere(
        (word) => RegExp(r'\d').hasMatch(word),
      );
      final lettersAfter = words
          .skip(firstNumber < 0 ? words.length : firstNumber + 1)
          .where((word) => !RegExp(r'\d').hasMatch(word))
          .length;
      if (firstNumber >= 0) {
        expect(
          lettersAfter,
          0,
          reason: 'los números son lo más difícil del nivel: van al final',
        );
      }
    });

    test('la misma semilla da la misma prueba', () {
      expect(
        fieldTestWords('Medio', seed: 42),
        fieldTestWords('Medio', seed: 42),
      );
    });

    test('todas las palabras se pueden transmitir enteras', () {
      for (final level in fieldTestLevels) {
        for (final word in fieldTestPools[level]!) {
          final message = MorseMessage.encode(word);
          expect(message.skipped, isEmpty, reason: word);
          expect(message.text, word, reason: word);
          expect(message.steps, isNotEmpty, reason: word);
        }
      }
    });

    test('el porcentaje y el veredicto acompañan el resultado', () {
      expect(fieldTestPercent(0, 8), 0);
      expect(fieldTestPercent(4, 8), 50);
      expect(fieldTestPercent(8, 8), 100);
      expect(fieldTestPercent(3, 0), 0);

      expect(fieldTestVerdict(100), contains('Excelente'));
      expect(fieldTestVerdict(75), contains('Sirve'));
      expect(fieldTestVerdict(50), contains('Justo'));
      expect(fieldTestVerdict(10), contains('No alcanza'));
    });
  });
}
