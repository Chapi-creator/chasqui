import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/light_sampler.dart';
import 'package:sinred/src/rescue/morse.dart';
import 'package:sinred/src/rescue/morse_decoder.dart';

/// Mete un mensaje ya codificado en el decodificador, como si la cámara lo
/// hubiera visto: cada tramo con su duración real.
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
      // La primera marca es una raya; el punto de la A calibra la escala.
      final reading = decodeMessage(MorseMessage.encode('TA'));
      expect(reading.text, 'TA');
    });

    test('solo rayas: sin un punto no hay con qué medir', () {
      // Limitación conocida y dicha en la pantalla: la O se lee como S porque
      // la única marca recibida (largo 3) se toma como punto.
      final reading = decodeMessage(MorseMessage.encode('O'));
      expect(reading.text, 'S');
    });

    test('números y signos vuelven tal cual', () {
      final reading = decodeMessage(MorseMessage.encode('123?'));
      expect(reading.text, '123?');
    });

    test('reconoce la llamada de atención y la quita del mensaje', () {
      final message = MorseMessage.encode('SOS', attention: true);
      final reading = decodeMessage(message);
      expect(reading.text, 'VVV SOS');
      expect(reading.hasAttention, isTrue);
      expect(reading.message, 'SOS');
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

    test('borrar deja el receptor en blanco', () {
      final decoder = MorseDecoder();
      decoder.mark(100);
      decoder.clear();
      expect(decoder.reading.isEmpty, isTrue);
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
      // Alternan luz y pausa.
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
  });

  group('llamada de atención', () {
    test('se suma delante del texto, separada como una palabra', () {
      final plain = MorseMessage.encode('HOLA');
      final called = MorseMessage.encode('HOLA', attention: true);
      expect(called.text, 'VVV HOLA');
      expect(called.preview, '...- ...- ...- / .... --- .-.. .-');
      expect(called.bodyText, 'HOLA');
      expect(called.hasAttention, isTrue);
      // Tres V: cuatro elementos cada una.
      expect(called.markCount, plain.markCount + 12);
    });

    test('sin mensaje no hay llamada de atención', () {
      final empty = MorseMessage.encode('', attention: true);
      expect(empty.isEmpty, isTrue);
      expect(empty.hasAttention, isFalse);
    });
  });
}
