import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/morse.dart';
import 'package:sinred/src/rescue/sighting.dart';

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
        'sinred_rescate_test',
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
        'sinred_rescate_corrupto',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await File('${directory.path}/sinred_rescate.json').writeAsString('{');
      final log = SightingLog(directory: directory);
      expect(await log.load(), isNull);
    });
  });
}
