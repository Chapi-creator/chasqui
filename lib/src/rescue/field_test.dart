import 'dart:math';

import 'morse.dart';

/// Prueba de campo: medir con la cámara y la linterna de verdad, no en una
/// simulación.
///
/// Dos teléfonos: uno transmite desde esta pantalla y el otro lee con el
/// receptor. Después se marca si salió bien. El número que queda al final es
/// lo que pasó en el patio, en el cerro o en la calle, con esa luz y esa
/// distancia.

/// Niveles, del más corto al más largo.
const List<String> fieldTestLevels = ['Fácil', 'Medio', 'Difícil'];

/// Palabras de cada nivel. Todas se pueden escribir en morse (letras, números
/// y espacios): la prueba no puede mandar algo que el transmisor descarte.
const Map<String, List<String>> fieldTestPools = {
  'Fácil': ['AS', 'NO', 'MI', 'TE', 'SOL', 'MAR', 'RIO', 'PAN', 'OSA', 'LUZ'],
  'Medio': [
    'CASA',
    'LUNA',
    'MANO',
    'AIRE',
    'AGUA',
    'NORTE',
    'FUEGO',
    'PLAYA',
    'TARDE',
    'CAMINO',
  ],
  'Difícil': [
    'PELIGRO',
    'AUXILIO',
    'RESCATE',
    'SENALES',
    'NECESITO',
    '1234',
    'SOS 123',
    'AGUA 7',
    'NORTE 20',
    'AYUDA 112',
  ],
};

/// Cuántas palabras tiene una prueba. Ocho alcanza para un número estable sin
/// aburrir: con cuatro, una sola falla mueve el resultado 25 puntos.
const int fieldTestWordCount = 8;

/// Peso de una palabra: lo que cuesta transmitirla y leerla.
///
/// Cuenta las marcas de morse —la duración real de la transmisión— y suma un
/// extra por cada dígito: un número no es "corto" aunque tenga pocos símbolos,
/// tiene cinco marcas cada uno y se confunde con otra cifra. Así una palabra
/// con números no queda al principio de la prueba.
int fieldTestWeight(String word) {
  var marks = 0;
  var digits = 0;
  for (final char in word.split('')) {
    if (char == ' ') continue;
    final code = morseAlphabet[char];
    if (code == null) continue;
    marks += code.length;
    if (char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 57) digits++;
  }
  return marks + digits * 6;
}

/// Palabras de una prueba, de la más corta a la más larga.
///
/// El orden es creciente a propósito: si la primera ya falla, el problema no
/// es la distancia sino que hay que calibrar o acercarse.
List<String> fieldTestWords(
  String level, {
  required int seed,
  int count = fieldTestWordCount,
}) {
  final pool = fieldTestPools[level] ?? fieldTestPools[fieldTestLevels.first]!;
  final shuffled = List<String>.from(pool)..shuffle(Random(seed));
  final chosen = shuffled.take(count).toList();
  chosen.sort((a, b) {
    final difference = fieldTestWeight(a).compareTo(fieldTestWeight(b));
    return difference != 0 ? difference : a.compareTo(b);
  });
  return chosen;
}

/// Porcentaje de aciertos, redondeado.
int fieldTestPercent(int correct, int total) {
  if (total <= 0) return 0;
  return ((correct * 100) / total).round();
}

/// Qué significa el número, sin adornos.
String fieldTestVerdict(int percent) {
  if (percent >= 90) {
    return 'Excelente: a esta distancia y con esta luz la lectura es '
        'confiable.';
  }
  if (percent >= 70) {
    return 'Sirve: en una emergencia se entiende, con algún reintento.';
  }
  if (percent >= 40) {
    return 'Justo: conviene acercarse, transmitir más lento o calibrar el '
        'receptor.';
  }
  return 'No alcanza: revisá el encuadre, tapá el fondo y volvé a calibrar '
      'antes de confiar en la lectura a esta distancia.';
}
