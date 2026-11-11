import 'package:flutter_test/flutter_test.dart';

import 'morse_simulation.dart';

const _mensajes = ['SOS', 'HOLA', 'AGUA', 'CASA', 'SOS SOS'];

void main() {
  group('lectura completa', () {
    test('cámara a 30 por segundo: cualquier ritmo de la app se lee bien', () {
      for (final unit in [300, 200, 120]) {
        for (final message in _mensajes) {
          expect(
            simulate(message, unitMs: unit, fps: 30, jitter: 0.1, dropRate: 0.02, exposureMs: 30),
            message,
            reason: 'ritmo $unit ms, mensaje "$message"',
          );
        }
      }
    });

    test('los dos mensajes que se leían mal ahora se leen bien', () {
      // SOS salía SOT y HOLA salía HOMA: en los dos, una pausa corta se
      // perdía y dos puntos se pegaban en una raya.
      for (final fps in [30.0, 24.0, 20.0]) {
        expect(
          simulate('SOS', unitMs: 120, fps: fps, jitter: 0.2, exposureMs: 30),
          'SOS',
          reason: 'SOS a $fps por segundo',
        );
        expect(
          simulate('HOLA', unitMs: 120, fps: fps, jitter: 0.2, exposureMs: 30),
          'HOLA',
          reason: 'HOLA a $fps por segundo',
        );
      }
    });

    test('cámara lenta y con fotogramas perdidos: aguanta la mayoría', () {
      // A 12-15 por segundo una pausa de 120 ms entra en un solo fotograma y a
      // veces en ninguno: eso ya no es información que exista en la imagen.
      // Se exige que no se desarme, no la perfección.
      var ok = 0;
      var total = 0;
      for (final fps in [30.0, 24.0, 20.0, 15.0, 12.0]) {
        for (final unit in [300, 200, 120]) {
          for (final message in _mensajes) {
            final leido = simulate(
              message,
              unitMs: unit,
              fps: fps,
              jitter: 0.35,
              dropRate: 0.08,
              exposureMs: 30,
            );
            total++;
            if (leido == message) ok++;
          }
        }
      }
      expect(ok / total, greaterThan(0.8), reason: 'aciertos $ok de $total');
    });

    test('ritmo normal y lento: ninguna lectura sale mal con cámara lenta', () {
      // Lo que garantiza la app: a 200 ms por punto (el ritmo elegido por
      // defecto) no falla ninguna lectura con 15 fotogramas por segundo, y a
      // 300 ms aguanta hasta 12. Se probaron 7 semillas sobre 7 mensajes, con
      // jitter 0,35, 8 % de fotogramas perdidos y exposición de 30 ms: 49 de 49
      // en cada caso. Si alguien toca el muestreador o el decodificador y esto
      // empeora, la suite falla antes de publicar.
      const frases = [
        'SOS',
        'HOLA',
        'AGUA',
        'CASA',
        'AYUDA',
        'SOS SOS',
        'NO HAY AGUA',
      ];
      for (final seed in [1, 2, 3, 4, 5, 6, 7]) {
        for (final message in frases) {
          expect(
            simulate(
              message,
              unitMs: 200,
              fps: 15,
              jitter: 0.35,
              dropRate: 0.08,
              exposureMs: 30,
              seed: seed,
            ),
            message,
            reason: 'semilla $seed, 200 ms, 15 por segundo, "$message"',
          );
          expect(
            simulate(
              message,
              unitMs: 300,
              fps: 12,
              jitter: 0.35,
              dropRate: 0.08,
              exposureMs: 30,
              seed: seed,
            ),
            message,
            reason: 'semilla $seed, 300 ms, 12 por segundo, "$message"',
          );
        }
      }
    });

    test('a ritmo lento no hace falta cámara rápida', () {
      expect(simulate('SOS', unitMs: 300, fps: 12, jitter: 0.35, dropRate: 0.08, exposureMs: 30), 'SOS');
      expect(simulate('HOLA', unitMs: 300, fps: 12, jitter: 0.35, dropRate: 0.08, exposureMs: 30), 'HOLA');
    });
  });
}
