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
