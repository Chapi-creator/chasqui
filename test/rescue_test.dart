import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/sighting.dart';

void main() {
  group('patrón morse del SOS', () {
    test('tres puntos, tres rayas y tres puntos con sus pausas', () {
      // 18 tramos: seis por letra (elemento, pausa, elemento, pausa,
      // elemento y pausa entre letras).
      expect(sosSteps.length, 18);
      expect(sosSteps.first.on, isTrue);
      expect(sosSteps.first.units, 1);
      // Termina apagada y con la pausa larga entre repeticiones: la linterna
      // descansa y el ojo separa un SOS del siguiente.
      expect(sosSteps.last.on, isFalse);
      expect(sosSteps.last.units, 7);
    });

    test('los elementos visibles son puntos, rayas y puntos', () {
      final marks = [
        for (var i = 0; i < sosSteps.length; i++)
          if (sosSteps[i].on) sosSteps[i].units,
      ];
      expect(marks, [1, 1, 1, 3, 3, 3, 1, 1, 1]);
    });

    test('un ciclo dura 10,2 s con la unidad de 300 ms', () {
      expect(sosCycleDuration(), const Duration(milliseconds: 10200));
      expect(sosCycleDuration(200), const Duration(milliseconds: 6800));
    });

    test('cada tramo sabe qué elemento del patrón iluminar', () {
      expect(sosMarkIndex(0), 0);
      // Las pausas no encienden ningún elemento.
      expect(sosMarkIndex(1), isNull);
      expect(sosMarkIndex(5), isNull);
      expect(sosMarkIndex(6), 3);
      expect(sosMarkIndex(16), 8);
      expect(sosMarkIndex(17), isNull);
    });
  });

  group('encendido del SOS', () {
    test('recorre el ciclo y vuelve a empezar sin desfase', () {
      fakeAsync((async) {
        final events = <(int, bool)>[];
        final blinker = SosBlinker(
          onStep: (index, step) => events.add((index, step.on)),
        );
        blinker.start();
        async.elapse(sosCycleDuration() - const Duration(milliseconds: 1));
        expect(events.length, 18);
        expect(events.first, (0, true));
        expect(events.last, (17, false));
        // Al cerrar los 10,2 s arranca de nuevo el primer punto, sin pausa de
        // más ni de menos.
        async.elapse(const Duration(milliseconds: 1));
        expect(events.length, 19);
        expect(events.last, (0, true));
        blinker.stop();
      });
    });

    test('respeta la duración de puntos, rayas y pausas', () {
      fakeAsync((async) {
        final starts = <String>[];
        final blinker = SosBlinker(
          onStep: (index, step) => starts.add('$index:${step.units}'),
        );
        blinker.start();
        // Punto (1), pausa (1), punto (1)…
        async.elapse(const Duration(milliseconds: 900));
        expect(starts, ['0:1', '1:1', '2:1', '3:1']);
        // La primera raya empieza en la unidad 8 (2,4 s): los tres puntos de
        // la S y la pausa de tres unidades que la separa de la O.
        async.elapse(const Duration(milliseconds: 1500));
        expect(starts.last, '6:3');
        blinker.stop();
      });
    });

    test('detenerlo corta el ciclo', () {
      fakeAsync((async) {
        final events = <int>[];
        final blinker = SosBlinker(onStep: (index, step) => events.add(index));
        blinker.start();
        async.elapse(const Duration(milliseconds: 300));
        blinker.stop();
        expect(blinker.running, isFalse);
        async.elapse(const Duration(seconds: 20));
        expect(events, [0, 1]);
      });
    });
  });

  group('alfabeto morse exacto', () {
    // Tabla del ITU-R M.1677-1, copiada tal cual. Si alguien cambia un punto
    // por una raya, esta prueba lo dice en vez de transmitir basura.
    const itu = {
      'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.',
      'F': '..-.', 'G': '--.', 'H': '....', 'I': '..', 'J': '.---',
      'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---',
      'P': '.--.', 'Q': '--.-', 'R': '.-.', 'S': '...', 'T': '-',
      'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--',
      'Z': '--..',
      '0': '-----', '1': '.----', '2': '..---', '3': '...--',
      '4': '....-', '5': '.....', '6': '-....', '7': '--...',
      '8': '---..', '9': '----.',
      '.': '.-.-.-', ',': '--..--', '?': '..--..', "'": '.----.',
      '/': '-..-.', '(': '-.--.', ')': '-.--.-', '"': '.-..-.',
      '=': '-...-', '+': '.-.-.', '@': '.--.-.', ':': '---...',
      '-': '-....-', '&': '.-...', ';': '-.-.-.', '_': '..--.-',
      r'$': '...-..-', '!': '-.-.--',
    };

    test('letras, números y signos coinciden uno por uno', () {
      for (final entry in itu.entries) {
        expect(
          morseAlphabet[entry.key],
          entry.value,
          reason: 'el código de ${entry.key} no es el del ITU',
        );
      }
    });

    test('la ñ y la exclamación inicial son las convenciones del español', () {
      expect(morseAlphabet['Ñ'], '--.--');
      expect(morseAlphabet['¡'], '--...-');
    });

    test('no hay códigos de más ni de menos en la tabla', () {
      // 26 letras + 10 números + 19 signos + ñ.
      expect(morseAlphabet.length, 56);
    });

    test('una frase con letras, números y signos sale en ese orden', () {
      final message = MorseMessage.encode('ABC 123 ?');
      expect(message.preview, '.- -... -.-. / .---- ..--- ...-- / ..--..');
    });
  });

  group('texto libre a morse', () {
    test('cada letra usa su código', () {
      final message = MorseMessage.encode('Hola');
      expect(message.text, 'HOLA');
      expect(message.codes, ['....', '---', '.-..', '.-']);
      expect(message.preview, '.... --- .-.. .-');
      expect(message.skipped, isEmpty);
      expect(message.markCount, 13);
    });

    test('las palabras se separan con pausa larga', () {
      final message = MorseMessage.encode('  SOS   AUXILIO  ');
      expect(message.text, 'SOS AUXILIO');
      expect(message.preview, startsWith('... --- ... / '));
      // Entre la S y la A de palabras distintas hay siete unidades apagadas.
      final gap = message.steps.where(
        (step) => !step.on && step.units == 7,
      );
      expect(gap, isNotEmpty);
    });

    test('tildes y minúsculas se pliegan; la ñ tiene su propio código', () {
      final message = MorseMessage.encode('Médico añejo');
      expect(message.text, 'MEDICO AÑEJO');
      final index = message.text.indexOf('Ñ');
      expect(message.codeAt(index), '--.--');
      expect(message.skipped, isEmpty);
    });

    test('lo que no existe en morse se descarta y se informa', () {
      final message = MorseMessage.encode('SOS ¿listos?');
      // El signo de apertura no tiene código; el de cierre sí.
      expect(message.skipped, ['¿']);
      expect(message.text, 'SOS LISTOS?');
      expect(message.preview.endsWith('..--..'), isTrue);
    });

    test('un mensaje vacío no genera tramos', () {
      final message = MorseMessage.encode('   ');
      expect(message.isEmpty, isTrue);
      expect(message.preview, isEmpty);
      expect(message.totalUnits, 0);
    });

    test('el espaciado sigue la convención: 1, 3 y 7 unidades', () {
      final letter = MorseMessage.encode('E');
      // Punto encendido y pausa de fin de mensaje.
      expect(letter.steps.map((s) => s.units).toList(), [1, 7]);

      final sameLetter = MorseMessage.encode('I'); // dos puntos
      expect(sameLetter.steps.map((s) => s.units).toList(), [1, 1, 1, 7]);

      final twoLetters = MorseMessage.encode('ET');
      expect(twoLetters.steps.map((s) => s.units).toList(), [1, 3, 3, 7]);

      final twoWords = MorseMessage.encode('E T');
      expect(twoWords.steps.map((s) => s.units).toList(), [1, 7, 3, 7]);
    });

    test('cada tramo encendido sabe qué letra y qué elemento transmite', () {
      final message = MorseMessage.encode('ET');
      expect(message.markLetter(0), 0);
      expect(message.markElement(0), 0);
      // Las pausas no encienden nada.
      expect(message.markLetter(1), isNull);
      expect(message.markElement(1), isNull);
      expect(message.markLetter(2), 1);
      expect(message.markElement(2), 0);
    });

    test('la duración depende de la velocidad elegida', () {
      final message = MorseMessage.encode('HOLA');
      // 23 unidades de puntos y rayas, 9 pausas entre elementos, 9 entre
      // letras y 7 de cierre.
      expect(message.totalUnits, 48);
      expect(message.duration(200), const Duration(milliseconds: 9600));
      expect(message.duration(120), const Duration(milliseconds: 5760));
    });

    test('el mensaje se repite con el mismo motor del SOS', () {
      fakeAsync((async) {
        final message = MorseMessage.encode('ET');
        final events = <int>[];
        final blinker = SosBlinker(
          onStep: (index, step) => events.add(index),
          unitMs: 100,
          steps: message.steps,
        );
        blinker.start();
        async.elapse(const Duration(milliseconds: 1399));
        expect(events, [0, 1, 2, 3]);
        // Al cerrar la pasada vuelve al primer punto del mensaje.
        async.elapse(const Duration(milliseconds: 1));
        expect(events.length, 5);
        expect(events.last, 0);
        blinker.stop();
      });
    });
  });

  group('contador de avistamiento', () {
    test('el texto crece con el tiempo', () {
      expect(formatSightingAge(const Duration(seconds: 5)), 'recién');
      expect(formatSightingAge(const Duration(seconds: 45)), 'hace 45 s');
      expect(formatSightingAge(const Duration(seconds: 90)), 'hace 1 min');
      expect(formatSightingAge(const Duration(minutes: 59)), 'hace 59 min');
      expect(
        formatSightingAge(const Duration(hours: 2, minutes: 14)),
        'hace 2 h 14 min',
      );
      expect(formatSightingAge(const Duration(hours: 6)), 'hace 6 h');
      expect(
        formatSightingAge(const Duration(hours: 27)),
        'hace 1 d 3 h',
      );
      expect(formatSightingAge(const Duration(days: 2)), 'hace 2 d');
    });

    test('un reloj adelantado no muestra tiempos negativos', () {
      expect(formatSightingAge(const Duration(seconds: -30)), 'recién');
    });

    test('la marca sobrevive al reinicio de la app', () async {
      final directory = await Directory.systemTemp.createTemp(
        'chasqui_rescate_test',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final log = SightingLog(directory: directory);
      expect(await log.load(), isNull);

      final stamp = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      await log.save(stamp);
      expect(await log.load(), stamp);
    });

    test('un archivo corrupto se ignora en vez de romper el panel', () async {
      final directory = await Directory.systemTemp.createTemp(
        'chasqui_rescate_corrupto',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await File('${directory.path}/chasqui_rescate.json').writeAsString('{');
      final log = SightingLog(directory: directory);
      expect(await log.load(), isNull);
    });
  });
}
