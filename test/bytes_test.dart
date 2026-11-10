import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/core/bytes.dart';

void main() {
  test('no parte emojis al recortar', () {
    final text = '🙂' * 10; // 40 bytes
    final cut = clampUtf8Bytes(text, 10);

    expect(utf8.encode(cut).length, lessThanOrEqualTo(10));
    expect(cut.runes.length, 2, reason: 'caben dos emojis de 4 bytes');
  });

  test('deja intacto lo que ya cabe', () {
    expect(clampUtf8Bytes('hola', 10), 'hola');
  });

  test('recorta acentos sin dejar bytes sueltos', () {
    final cut = clampUtf8Bytes('ñ' * 5, 3); // cada ñ ocupa 2 bytes

    expect(utf8.encode(cut).length, 2);
    expect(cut, 'ñ');
  });

  test('un corte en cero devuelve cadena vacía', () {
    expect(clampUtf8Bytes('abc', 0), isEmpty);
  });
}
