import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/rescue/light_calibration.dart';
import 'package:chasqui/src/rescue/light_sampler.dart';
import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/morse_decoder.dart';

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
  LightCalibration? calibration,
  double onLevel = 0.92,
  double offLevel = 0.08,
}) {
  final sampler = LightSampler()..setCalibration(calibration);
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

    var luma = on ? onLevel : offLevel;
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
      // Raya de 600 ms con un solo fotograma oscuro a la mitad, pausa de
      // letra y un punto: así se sabe el ritmo y no hay ambigüedad.
      final values = <double>[];
      for (var i = 0; i < 24; i++) {
        values.add(i == 12 ? 0.05 : 0.9); // 600 ms de luz, parpadeo en 300
      }
      values.addAll(List.filled(24, 0.05)); // 600 ms de pausa de letra
      values.addAll(List.filled(8, 0.9)); // 200 ms de luz: un punto
      values.addAll(List.filled(40, 0.05));

      final sampler = LightSampler();
      final decoder = MorseDecoder();
      for (var i = 0; i < values.length; i++) {
        final change = sampler.addSample(values[i], i * 25);
        if (change == null) continue;
        change.on ? decoder.mark(change.ms) : decoder.gap(change.ms);
      }
      decoder.closeLetter();

      // El parpadeo puede partir la raya en dos marcas, pero sin pausa en el
      // medio el decodificador las vuelve a unir: sigue siendo una raya.
      expect(decoder.reading.text, 'TE');
    });

    test('sin contraste avisa que no hay señal', () {
      final sampler = LightSampler();
      for (var i = 0; i < 40; i++) {
        sampler.addSample(0.2 + i * 0.0005, i * 30);
      }
      expect(sampler.hasSignal, isFalse);
    });
  });

  group('punto corto a 30 fotogramas', () {
    test('un punto de 120 ms no se pierde', () {
      // Luz 4 fotogramas, pausa 4 fotogramas: 132 ms cada tramo.
      final values = <double>[
        for (var block = 0; block < 6; block++) ...List.filled(4, block.isEven ? 0.9 : 0.05),
      ];
      final sampler = LightSampler();
      final transitions = <LightTransition>[];
      for (var i = 0; i < values.length; i++) {
        final change = sampler.addSample(values[i], i * 33);
        if (change != null) transitions.add(change);
      }
      expect(transitions.length, greaterThanOrEqualTo(4));
      for (final transition in transitions.skip(1)) {
        expect(transition.ms, inInclusiveRange(99, 165));
      }
    });
  });

  group('precisión con ruido', () {
    MorseReading readWithNoise(
      String text, {
      int unitMs = 200,
      double jitter = 0.25,
      int seed = 5,
      double dropRate = 0,
    }) {
      final random = math.Random(seed);
      final message = MorseMessage.encode(text);
      final sampler = LightSampler();
      final decoder = MorseDecoder();
      final on = <bool>[];
      final durations = <int>[];
      for (final step in message.steps) {
        final base = step.units * unitMs;
        final noisy =
            (base * (1 + (random.nextDouble() * 2 - 1) * jitter)).round();
        on.add(step.on);
        durations.add(math.max(20, noisy));
      }
      var time = 0;
      var index = 0;
      var end = durations.first;
      for (; index < durations.length; time += 33) {
        if (time >= end) {
          if (index == durations.length - 1) break;
          index++;
          end += durations[index];
        }
        var luma = on[index] ? 0.9 : 0.1;
        // Fotograma perdido: la cámara lo entrega al revés.
        if (random.nextDouble() < dropRate) luma = on[index] ? 0.1 : 0.9;
        final change = sampler.addSample(luma, time);
        if (change == null) continue;
        if (change.on) {
          decoder.mark(change.ms);
        } else {
          decoder.gap(change.ms);
        }
      }
      decoder.closeLetter();
      return decoder.reading;
    }

    test('aguanta un 25 % de temblor en ritmos distintos', () {
      for (final unit in [120, 200, 320]) {
        for (final text in ['SOS', 'HOLA', 'ESTOY BIEN', 'NECESITO AGUA']) {
          expect(
            readWithNoise(text, unitMs: unit).text,
            text,
            reason: '"$text" a $unit ms',
          );
        }
      }
    });

    test('con fotogramas perdidos igual lee casi todo', () {
      var chars = 0;
      var ok = 0;
      for (final text in [
        'SOS',
        'HOLA',
        'AGUA',
        'ESTOY BIEN',
        'MANDEN AYUDA',
      ]) {
        final reading = readWithNoise(
          text,
          jitter: 0.2,
          dropRate: 0.03,
          seed: 11,
        );
        chars += text.length;
        for (var i = 0; i < text.length && i < reading.text.length; i++) {
          if (text[i] == reading.text[i]) ok++;
        }
      }
      expect(ok / chars, greaterThan(0.9));
    });

    test('una pausa real de 66 ms no se fusiona con la raya', () {
      // Números medidos en una simulación de SOS con 30 % de temblor: la pausa
      // de 66 ms es la de la O y antes se comía, dejando M en vez de O.
      final decoder = MorseDecoder();
      const marks = [99, 132, 132, 264, 396, 330, 165, 99, 132];
      const gaps = [132, 132, 429, 165, 66, 429, 132, 132];
      for (var i = 0; i < marks.length; i++) {
        decoder.mark(marks[i]);
        if (i < gaps.length) decoder.gap(gaps[i]);
      }
      decoder.closeLetter();
      expect(decoder.reading.text, 'SOS');
    });
  });

  group('calibración del lugar', () {
    test('con umbrales medidos lee el mismo mensaje', () {
      final reading = decodeFromCamera(
        MorseMessage.encode('SOS'),
        calibration: const LightCalibration(dark: 0.1, bright: 0.9),
      );
      expect(reading.text, 'SOS');
    });

    test('un brillo medido como "luz" se lee como encendido', () {
      // Sin calibrar, un nivel fijo de 0.5 no llega al umbral de encendido
      // (0.6) y la luz se ve apagada para siempre. Con la calibración del
      // lugar —fondo 20 %, luz 60 %— ese mismo 0.5 es luz encendida.
      final plain = LightSampler();
      expect(plain.addSample(0.5, 0), isNull);
      expect(plain.isOn, isFalse);

      final calibrated = LightSampler()
        ..setCalibration(const LightCalibration(dark: 0.2, bright: 0.6));
      calibrated.addSample(0.5, 0);
      calibrated.addSample(0.5, 33);
      expect(calibrated.isOn, isTrue);
    });

    test('los umbrales calibrados mandan sobre los automáticos', () {
      final sampler = LightSampler()
        ..setCalibration(const LightCalibration(dark: 0.2, bright: 0.6));
      expect(sampler.calibration?.turnOn, closeTo(0.44, 1e-9));
      expect(sampler.calibration?.turnOff, closeTo(0.36, 1e-9));

      // 0.42 está en la zona muerta: por debajo de 0.44 no enciende.
      sampler.addSample(0.42, 0);
      sampler.addSample(0.42, 33);
      expect(sampler.isOn, isFalse);

      // 0.5 enciende en ese mismo fotograma: desde la 1.0.0 un cambio se
      // acepta en cuanto cruza el umbral, sin esperar al siguiente. Lo que se
      // reporta es el tramo apagado que termina.
      final off = sampler.addSample(0.5, 66);
      expect(off?.on, isFalse);
      expect(off?.ms, inInclusiveRange(40, 70));

      // Y 0.3, por debajo del umbral de apagado, cierra el tramo de luz.
      final on = sampler.addSample(0.3, 132);
      expect(on?.on, isTrue);
      // La luz duró de 66 a 132, pero el borde se interpola entre los dos
      // fotogramas que cruzan el umbral, así que la medida queda algo antes
      // de 66. Con el fotograma entero como borde, a 10 por segundo el error
      // llegaba a 100 ms por tramo.
      expect(on?.ms, inInclusiveRange(40, 70));
    });

    test('una calibración sin diferencia se ignora', () {
      final sampler = LightSampler()
        ..setCalibration(const LightCalibration(dark: 0.5, bright: 0.52));
      expect(sampler.calibration, isNull);
    });

    test('con calibración hay señal aunque el contraste ahora sea bajo', () {
      final sampler = LightSampler()
        ..setCalibration(const LightCalibration(dark: 0.1, bright: 0.9));
      sampler.addSample(0.9, 0);
      sampler.addSample(0.9, 33);
      expect(sampler.contrast, 0);
      expect(sampler.hasSignal, isTrue);
    });

    test('el pitido de un fondo muy claro no impide leer', () {
      // Cámara con exposición alta: el "apagado" ya viene claro. Con la
      // calibración de ese lugar, el mensaje se lee igual.
      final reading = decodeFromCamera(
        MorseMessage.encode('AGUA'),
        onLevel: 0.82,
        offLevel: 0.62,
        calibration: const LightCalibration(dark: 0.62, bright: 0.82),
      );
      expect(reading.text, 'AGUA');
    });
  });

  group('abecedario', () {
    test('cada código es único y vuelve a su letra', () {
      expect(reverseMorse.length, morseAlphabet.length);
      for (final entry in morseAlphabet.entries) {
        expect(morseSymbolFor(entry.value), entry.key);
      }
    });

    test('el SOS de la app coincide con sus tramos', () {
      expect(sosSteps.length, 18);
      expect(sosOnSteps.length, 9);
      for (var i = 0; i < sosSteps.length; i++) {
        expect(sosSteps[i].on, sosOnSteps.contains(i), reason: 'tramo $i');
      }
      expect(sosCycleDuration().inMilliseconds, 34 * sosUnitMs);
    });
  });
}
