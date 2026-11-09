import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/light_sampler.dart';
import 'package:sinred/src/rescue/morse.dart';
import 'package:sinred/src/rescue/morse_decoder.dart';

/// Mete un mensaje ya codificado en el decodificador, como si la cámara lo
/// hubiera visto: cada tramo con su duración exacta.
MorseReading decodeMessage(MorseMessage message, {int unitMs = 100}) {
  final decoder = MorseDecoder();
  for (final step in message.steps) {
    if (step.on) {
      decoder.mark(step.units * unitMs);
    } else {
      decoder.gap(step.units * unitMs);
    }
  }
  return decoder.reading;
}

/// Simula la cámara entera: una luz que parpadea según el mensaje, muestreada
/// cada [frameMs] como lo hace un teléfono a 30 por segundo.
///
/// [dips] son instantes en los que la cámara "pierde" la luz durante un solo
/// fotograma (exposición, pulso, un reflejo). Eso es exactamente lo que antes
/// partía una raya en dos y arruinaba el mensaje.
MorseReading decodeFromCamera(
  MorseMessage message, {
  int unitMs = 200,
  int frameMs = 33,
  List<int> dips = const [],
  bool noise = true,
}) {
  final sampler = LightSampler();
  final decoder = MorseDecoder();
  final starts = <int>[];
  final ends = <int>[];
  final lights = <bool>[];

  var cursor = 0;
  for (final step in message.steps) {
    final duration = step.units * unitMs;
    starts.add(cursor);
    ends.add(cursor + duration);
    lights.add(step.on);
    cursor += duration;
  }
  final total = cursor;

  bool isOn(int time) {
    for (var i = 0; i < starts.length; i++) {
      if (time >= starts[i] && time < ends[i]) return lights[i];
    }
    return false;
  }

  // La cola deja que la cámara cierre el último tramo.
  for (var time = 0; time <= total + 400; time += frameMs) {
    var on = isOn(time);
    final dipped = dips.any((dip) => time >= dip && time < dip + frameMs);
    if (dipped) on = false;

    var luma = on ? 0.92 : 0.08;
    if (noise) {
      // Temblor de la cámara: no cambia el estado, solo el número.
      luma += 0.015 * math.sin(time / 7.0);
    }
    final change = sampler.addSample(luma, time);
    if (change == null) continue;
    if (change.on) {
      decoder.mark(change.ms);
    } else {
      decoder.gap(change.ms);
    }
  }
  // La pantalla cierra la última letra cuando el silencio ya es de letra.
  decoder.closeLetter();
  return decoder.reading;
}

void main() {
  group('decodificador de destellos', () {
    test('lee un SOS tal como se transmitió', () {
      final reading = decodeMessage(MorseMessage.encode('SOS'));
      expect(reading.text, 'SOS');
    });

    test('separa palabras con la pausa larga', () {
      final reading = decodeMessage(MorseMessage.encode('HOLA MUNDO'));
      expect(reading.text, 'HOLA MUNDO');
    });

    test('adivina el ritmo aunque no sea el de la app', () {
      // Un operador lento, con unidad de 300 ms.
      final reading = decodeMessage(MorseMessage.encode('AGUA'), unitMs: 300);
      expect(reading.text, 'AGUA');
      expect(reading.unitMs, 300);
    });

    test('un mensaje que empieza con raya no se confunde', () {
      final reading = decodeMessage(MorseMessage.encode('TA'));
      expect(reading.text, 'TA');
    });

    test('solo rayas: las pausas alcanzan para no leerlas como puntos', () {
      // Sin puntos, las pausas de letra (3) y de fin (7) todavía distinguen
      // una raya: la O se lee bien.
      final reading = decodeMessage(MorseMessage.encode('O'));
      expect(reading.text, 'O');
    });

    test('números y signos vuelven tal cual', () {
      final reading = decodeMessage(MorseMessage.encode('123?'));
      expect(reading.text, '123?');
    });

    test('la letra en curso se muestra aparte hasta que termina', () {
      final decoder = MorseDecoder();
      decoder.mark(100);
      decoder.gap(100);
      decoder.mark(300);
      final reading = decoder.reading;
      expect(reading.text, '');
      expect(reading.pending, '. -');
      expect(reading.marks, 2);
    });

    test('un código que no existe se marca en vez de inventarse', () {
      final decoder = MorseDecoder();
      // . . - - . - . - : no está en la tabla.
      for (final ms in [100, 100, 300, 300, 100, 300, 100, 300]) {
        decoder.mark(ms);
        decoder.gap(100);
      }
      decoder.gap(300);
      expect(decoder.reading.text, '?');
    });

    test('el chispazo de un solo fotograma no se cuenta como punto', () {
      final decoder = MorseDecoder();
      decoder.mark(15);
      decoder.mark(100);
      expect(decoder.reading.marks, 1);
    });

    test('una pausa de un fotograma dentro de una raya no la parte', () {
      final decoder = MorseDecoder();
      // La primera T con un hueco de un fotograma en el medio de su raya.
      decoder.mark(150);
      decoder.gap(30);
      decoder.mark(150);
      decoder.gap(300);
      decoder.mark(300);
      decoder.gap(700);
      // Si la raya se hubiera partido, saldría I en lugar de T.
      expect(decoder.reading.text, 'TT');
      expect(decoder.reading.marks, 2);
    });

    test('el ritmo ya elegido no cambia si el nuevo explica casi igual', () {
      final decoder = MorseDecoder();
      for (final step in MorseMessage.encode('SOS').steps) {
        if (step.on) {
          decoder.mark(step.units * 200);
        } else {
          decoder.gap(step.units * 200);
        }
      }
      expect(decoder.reading.unitMs, 200);
      // Una marca imprecisa no reescribe el mensaje que ya se leyó.
      decoder.mark(250);
      expect(decoder.reading.unitMs, 200);
      expect(decoder.reading.text, startsWith('SOS'));
    });

    test('borrar deja el receptor en blanco', () {
      final decoder = MorseDecoder();
      decoder.mark(100);
      decoder.clear();
      expect(decoder.reading.isEmpty, isTrue);
    });
  });

  group('cámara a 30 fotogramas por segundo', () {
    test('SOS a 200 ms por punto se lee entero', () {
      final reading = decodeFromCamera(MorseMessage.encode('SOS'));
      expect(reading.text, 'SOS');
    });

    test('una frase con palabras sobrevive al muestreo', () {
      final reading = decodeFromCamera(
        MorseMessage.encode('ESTAMOS BIEN'),
        unitMs: 300,
      );
      expect(reading.text, 'ESTAMOS BIEN');
    });

    test('a ritmo rápido (120 ms) también se lee', () {
      final reading = decodeFromCamera(
        MorseMessage.encode('AGUA'),
        unitMs: 120,
      );
      expect(reading.text, 'AGUA');
    });

    test('los parpadeos de exposición no cambian el mensaje', () {
      // Un fotograma perdido en el medio de tres rayas distintas.
      final reading = decodeFromCamera(
        MorseMessage.encode('SOS'),
        dips: const [300, 900, 1500],
      );
      expect(reading.text, 'SOS');
    });

    test('aguanta temblor sin perder letras', () {
      final reading = decodeFromCamera(
        MorseMessage.encode('SOS'),
        noise: true,
      );
      expect(reading.text, 'SOS');
    });

    test('un operador lento se lee igual', () {
      final reading = decodeFromCamera(
        MorseMessage.encode('HOLA'),
        unitMs: 400,
      );
      expect(reading.text, 'HOLA');
    });
  });

  group('brillo de la cámara a encendidos', () {
    List<LightTransition> run(List<double> values, {int stepMs = 25}) {
      final sampler = LightSampler();
      final transitions = <LightTransition>[];
      for (var i = 0; i < values.length; i++) {
        final change = sampler.addSample(values[i], i * stepMs);
        if (change != null) transitions.add(change);
      }
      return transitions;
    }

    test('una luz que parpadea cada 100 ms da tramos de 100 ms', () {
      final values = <double>[];
      for (var i = 0; i < 400; i++) {
        // Bloques de 100 ms encendido y apagado.
        values.add(((i * 25) ~/ 100).isEven ? 0.9 : 0.05);
      }
      final transitions = run(values);
      expect(transitions.length, greaterThan(10));
      final durations = transitions.skip(1).map((t) => t.ms).toList();
      for (final ms in durations) {
        expect(ms, inInclusiveRange(75, 125));
      }
      for (var i = 1; i < transitions.length; i++) {
        expect(transitions[i].on, isNot(transitions[i - 1].on));
      }
    });

    test('una pared oscura y quieta no produce señales', () {
      final transitions = run(List.filled(200, 0.12));
      expect(transitions, isEmpty);
    });

    test('un destello más corto que un parpadeo de cámara se descarta', () {
      final values = <double>[
        ...List.filled(20, 0.05),
        0.95,
        ...List.filled(60, 0.05),
      ];
      final transitions = run(values);
      expect(transitions.where((t) => t.on), isEmpty);
    });

    test('un hueco de un fotograma dentro de una raya no la corta', () {
      final values = <double>[];
      // 600 ms de luz con un solo fotograma oscuro a la mitad.
      for (var i = 0; i < 24; i++) {
        values.add(i == 12 ? 0.05 : 0.9);
      }
      values.addAll(List.filled(20, 0.05));
      final transitions = run(values);
      expect(transitions.first.on, isTrue);
      expect(transitions.first.ms, inInclusiveRange(550, 650));
      expect(transitions.length, lessThanOrEqualTo(3));
    });

    test('sin contraste avisa que no hay señal', () {
      final sampler = LightSampler();
      for (var i = 0; i < 40; i++) {
        sampler.addSample(0.2 + i * 0.0005, i * 30);
      }
      expect(sampler.hasSignal, isFalse);
    });
  });
}
