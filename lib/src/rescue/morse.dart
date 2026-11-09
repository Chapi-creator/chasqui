import 'dart:async';

/// Patrón morse del SOS: tres puntos, tres rayas, tres puntos.
///
/// La luz se ve desde lejos solo si el ritmo es tranquilo: un SOS apurado entra
/// y sale del ojo de quien mira sin registrarse. Por eso la unidad es larga
/// (300 ms) y entre repeticiones hay una pausa de siete unidades.

/// Un tramo del ciclo: luz encendida o apagada durante [units] unidades.
class LightStep {
  const LightStep({required this.on, required this.units});

  final bool on;
  final int units;

  Duration duration(int unitMs) => Duration(milliseconds: units * unitMs);

  @override
  String toString() => '${on ? 'encendido' : 'apagado'} x$units';
}

/// Milisegundos que dura una unidad morse. Con 300 el ciclo completo queda en
/// 10,2 s: lo bastante lento para leerse desde el aire y sin pausas muertas.
const int sosUnitMs = 300;

List<LightStep> _buildSos() {
  final steps = <LightStep>[];

  void letter(List<int> elements, int gapUnits) {
    for (var i = 0; i < elements.length; i++) {
      // Entre elementos de una misma letra se apaga una unidad.
      if (i > 0) steps.add(const LightStep(on: false, units: 1));
      steps.add(LightStep(on: true, units: elements[i]));
    }
    // Entre letras tres unidades; al final del ciclo, siete (pausa entre
    // repeticiones: así el ojo distingue un SOS del siguiente).
    steps.add(LightStep(on: false, units: gapUnits));
  }

  letter([1, 1, 1], 3); // S
  letter([3, 3, 3], 3); // O
  letter([1, 1, 1], 7); // S + pausa
  return List.unmodifiable(steps);
}

/// Secuencia completa del SOS. Suma 34 unidades y termina apagada, para que la
/// linterna descanse entre ciclos.
final List<LightStep> sosSteps = _buildSos();

/// Número de elementos visibles del SOS: los tres puntos, las tres rayas y
/// los tres puntos finales (sin contar las pausas).
const List<int> sosOnSteps = [0, 2, 4, 6, 8, 10, 12, 14, 16];

/// Qué elemento del SOS (0 a 8) corresponde a cada tramo del ciclo, o null si
/// el tramo es una pausa. Sirve para iluminar el patrón en la pantalla.
int? sosMarkIndex(int stepIndex) {
  final mark = sosOnSteps.indexOf(stepIndex);
  return mark < 0 ? null : mark;
}

/// Cuánto dura una repetición completa del SOS con esta unidad.
Duration sosCycleDuration([int unitMs = sosUnitMs]) {
  var units = 0;
  for (final step in sosSteps) {
    units += step.units;
  }
  return Duration(milliseconds: units * unitMs);
}

/// Recorre [sosSteps] en bucle llamando a [onStep] al empezar cada tramo.
///
/// Usa un temporizador por tramo en lugar de un `Timer.periodic`: el patrón no
/// es uniforme (punto y raya duran distinto), y reprogramar tramo a tramo evita
/// que el desfase se acumule al final del ciclo.
class SosBlinker {
  SosBlinker({
    required this.onStep,
    this.unitMs = sosUnitMs,
    List<LightStep>? steps,
  }) : steps = steps ?? sosSteps;

  final void Function(int index, LightStep step) onStep;
  final int unitMs;
  final List<LightStep> steps;

  Timer? _timer;
  int _index = 0;

  bool get running => _timer != null;

  /// Arranca el ciclo desde el primer punto (encendido).
  void start() {
    stop();
    _index = 0;
    _fire();
  }

  void _fire() {
    final step = steps[_index];
    onStep(_index, step);
    _timer = Timer(step.duration(unitMs), () {
      _index = (_index + 1) % steps.length;
      _fire();
    });
  }

  /// Detiene el ciclo. Quien lo usa es responsable de apagar la luz.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

// ------------------------------------------------------- texto libre a morse

/// Alfabeto morse internacional. Incluye la ñ y los signos que aparecen en un
/// mensaje de emergencia; lo que no está acá se descarta y la pantalla avisa
/// cuáles quedaron afuera.
const Map<String, String> morseAlphabet = {
  'A': '.-',
  'B': '-...',
  'C': '-.-.',
  'D': '-..',
  'E': '.',
  'F': '..-.',
  'G': '--.',
  'H': '....',
  'I': '..',
  'J': '.---',
  'K': '-.-',
  'L': '.-..',
  'M': '--',
  'N': '-.',
  'O': '---',
  'P': '.--.',
  'Q': '--.-',
  'R': '.-.',
  'S': '...',
  'T': '-',
  'U': '..-',
  'V': '...-',
  'W': '.--',
  'X': '-..-',
  'Y': '-.--',
  'Z': '--..',
  'Ñ': '--.--',
  '0': '-----',
  '1': '.----',
  '2': '..---',
  '3': '...--',
  '4': '....-',
  '5': '.....',
  '6': '-....',
  '7': '--...',
  '8': '---..',
  '9': '----.',
  '.': '.-.-.-',
  ',': '--..--',
  '?': '..--..',
  '!': '-.-.--',
  '¡': '--...-',
  "'": '.----.',
  '"': '.-..-.',
  '/': '-..-.',
  '(': '-.--.',
  ')': '-.--.-',
  '&': '.-...',
  ':': '---...',
  ';': '-.-.-.',
  '=': '-...-',
  '+': '.-.-.',
  '-': '-....-',
  '_': '..--.-',
  r'$': '...-..-',
  '@': '.--.-.',
};

/// La tabla al revés: de código a símbolo. Se arma una vez y sirve para leer
/// los destellos que llegan por cámara.
final Map<String, String> reverseMorse = {
  for (final entry in morseAlphabet.entries) entry.value: entry.key,
};

/// Qué símbolo corresponde a un código, o `?` si no es válido. Un destello
/// mal medido produce un código que no existe: se marca así en lugar de
/// inventar una letra.
String morseSymbolFor(String code) => reverseMorse[code] ?? '?';

/// Tildes y diéresis que no cambian la letra. Sin esto, "MÉDICO" quedaría a
/// medias: la É no existe en morse, pero la E sí.
const Map<String, String> _foldedLetters = {
  'Á': 'A',
  'À': 'A',
  'Ä': 'A',
  'Â': 'A',
  'Ã': 'A',
  'É': 'E',
  'È': 'E',
  'Ë': 'E',
  'Ê': 'E',
  'Í': 'I',
  'Ì': 'I',
  'Ï': 'I',
  'Î': 'I',
  'Ó': 'O',
  'Ò': 'O',
  'Ö': 'O',
  'Ô': 'O',
  'Õ': 'O',
  'Ú': 'U',
  'Ù': 'U',
  'Ü': 'U',
  'Û': 'U',
  'Ç': 'C',
};

/// Deja el texto en la forma que se puede transmitir: mayúsculas, sin tildes
/// y con un solo espacio entre palabras. La ñ se conserva porque tiene código
/// propio.
String normalizeMorseText(String input) {
  final buffer = StringBuffer();
  for (final char in input.toUpperCase().split('')) {
    buffer.write(_foldedLetters[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Un mensaje ya convertido a tramos de luz, con el mapa de qué letra y qué
/// elemento se está transmitiendo en cada tramo.
///
/// Las pausas siguen la convención: una unidad entre elementos de la misma
/// letra, tres entre letras y siete entre palabras. Después del último elemento
/// queda la pausa larga, así el mensaje se puede repetir en bucle sin que las
/// palabras se peguen.
class MorseMessage {
  MorseMessage._({
    required this.text,
    required this.codes,
    required this.steps,
    required this.skipped,
    required List<int> stepLetters,
    required List<int> stepElements,
  }) : _stepLetters = stepLetters,
       _stepElements = stepElements;

  factory MorseMessage.encode(
    String input, {
    int letterGapUnits = 3,
    int wordGapUnits = 7,
  }) {
    final normalized = normalizeMorseText(input);
    final chars = <String>[];
    final codes = <String>[];
    final skipped = <String>[];
    var pendingSpace = false;

    for (final char in normalized.split('')) {
      if (char == ' ') {
        // El espacio solo vale si después viene algo transmitible: así no
        // quedan huecos al principio ni al final.
        if (chars.isNotEmpty) pendingSpace = true;
        continue;
      }
      final code = morseAlphabet[char];
      if (code == null) {
        if (!skipped.contains(char)) skipped.add(char);
        continue;
      }
      if (pendingSpace) {
        chars.add(' ');
        codes.add('');
        pendingSpace = false;
      }
      chars.add(char);
      codes.add(code);
    }

    final steps = <LightStep>[];
    final stepLetters = <int>[];
    final stepElements = <int>[];
    int? previousLetter;

    for (var i = 0; i < chars.length; i++) {
      final code = codes[i];
      if (code.isEmpty) continue;
      for (var e = 0; e < code.length; e++) {
        if (previousLetter != null) {
          final sameLetter = previousLetter == i;
          // Entre letras hay un espacio en `chars`, así que dos letras de la
          // misma palabra quedan a distancia 1 y de palabras distintas a 2.
          final gap = sameLetter
              ? 1
              : (i - previousLetter > 1 ? wordGapUnits : letterGapUnits);
          steps.add(LightStep(on: false, units: gap));
          stepLetters.add(-1);
          stepElements.add(-1);
        }
        steps.add(LightStep(on: true, units: code[e] == '-' ? 3 : 1));
        stepLetters.add(i);
        stepElements.add(e);
        previousLetter = i;
      }
    }

    if (steps.isNotEmpty) {
      // Pausa de fin de mensaje: separa una repetición de la siguiente.
      steps.add(LightStep(on: false, units: wordGapUnits));
      stepLetters.add(-1);
      stepElements.add(-1);
    }

    return MorseMessage._(
      text: chars.join(),
      codes: List.unmodifiable(codes),
      steps: List.unmodifiable(steps),
      skipped: List.unmodifiable(skipped),
      stepLetters: List.unmodifiable(stepLetters),
      stepElements: List.unmodifiable(stepElements),
    );
  }

  /// Letras y espacios tal como se van a transmitir.
  final String text;

  /// Código de cada carácter de [text]; los espacios van vacíos.
  final List<String> codes;

  /// Tramos de luz del mensaje completo, en orden.
  final List<LightStep> steps;

  /// Caracteres que se descartaron por no tener código morse.
  final List<String> skipped;

  final List<int> _stepLetters;
  final List<int> _stepElements;

  bool get isEmpty => steps.isEmpty;

  /// Elementos encendidos del mensaje (sin contar las pausas).
  int get markCount => _stepLetters.where((letter) => letter >= 0).length;

  /// Posición en [text] de la letra que enciende este tramo, o null si el
  /// tramo es una pausa.
  int? markLetter(int stepIndex) {
    if (stepIndex < 0 || stepIndex >= _stepLetters.length) return null;
    final letter = _stepLetters[stepIndex];
    return letter < 0 ? null : letter;
  }

  /// Qué elemento de la letra enciende este tramo (0 = primero).
  int? markElement(int stepIndex) {
    if (stepIndex < 0 || stepIndex >= _stepElements.length) return null;
    final element = _stepElements[stepIndex];
    return element < 0 ? null : element;
  }

  /// El mensaje en morse para leer en pantalla: `.... --- .-.. .-` y ` / `
  /// entre palabras.
  String get preview {
    final buffer = StringBuffer();
    var first = true;
    for (var i = 0; i < codes.length; i++) {
      if (codes[i].isEmpty) continue;
      if (!first) {
        final wordBreak = i > 0 && codes[i - 1].isEmpty;
        buffer.write(wordBreak ? ' / ' : ' ');
      }
      buffer.write(codes[i]);
      first = false;
    }
    return buffer.toString();
  }

  /// Cuánto dura una pasada completa, en unidades morse.
  int get totalUnits {
    var units = 0;
    for (final step in steps) {
      units += step.units;
    }
    return units;
  }

  Duration duration(int unitMs) => Duration(milliseconds: totalUnits * unitMs);

  /// Código de la letra en la posición [letterIndex] de [text].
  String codeAt(int letterIndex) {
    if (letterIndex < 0 || letterIndex >= codes.length) return '';
    return codes[letterIndex];
  }
}
