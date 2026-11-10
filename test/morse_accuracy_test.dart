import 'dart:math' as math;

import 'package:chasqui/src/rescue/light_sampler.dart';
import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/morse_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula la cadena completa: un emisor que respeta el morse al pie de la letra,
/// una cámara que muestrea con fotogramas irregulares, retardo de exposición y
/// ruido, y el receptor real.
///
/// Sirve para lo que no se puede probar con un widget: el receptor entero visto
/// como un sistema de tiempo. Los fallos que se reportaron —SOS leído como SOT,
/// HOLA como HOMA— son justo de aquí: pausas cortas que la cámara no alcanza a
/// ver y que pegaban dos puntos en una raya.
String simulate(
  String message, {
  int unitMs = 200,
  double fps = 30,
  double jitter = 0,
  double dropRate = 0,
  double noise = 0.02,
  double exposureMs = 0,
  int seed = 7,
}) {
  final steps = MorseMessage.encode(message).steps;
  final windows = <_Span>[];
  var t = 0;
  for (final step in steps) {
    final ms = step.units * unitMs;
    windows.add(_Span(step.on, t, t + ms));
    t += ms;
  }
  final total = t;

  final sampler = LightSampler();
  final decoder = MorseDecoder();
  final random = math.Random(seed);
  final stepMs = 1000 / fps;
  var luma = 0.08;
  var now = 0.0;

  while (now <= total) {
    final on = windows.any((s) => s.on && now >= s.start && now < s.end);
    final target = on ? 1.0 : 0.08;
    if (exposureMs <= 0) {
      luma = target;
    } else {
      luma += (target - luma) * (1 - math.exp(-stepMs / exposureMs));
    }
    final sample = (luma + (random.nextDouble() - 0.5) * noise).clamp(0.0, 1.0);
    final change = sampler.addSample(sample, now.round());
    if (change != null) {
      change.on ? decoder.mark(change.ms) : decoder.gap(change.ms);
    }
    final delta = stepMs * (1 + (random.nextDouble() - 0.5) * 2 * jitter);
    now += random.nextDouble() < dropRate ? delta * 2 : delta;
  }
  decoder.closeLetter();
  return decoder.reading.text;
}

class _Span {
  const _Span(this.on, this.start, this.end);
  final bool on;
  final int start;
  final int end;
}

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

    test('a ritmo lento no hace falta cámara rápida', () {
      expect(simulate('SOS', unitMs: 300, fps: 12, jitter: 0.35, dropRate: 0.08, exposureMs: 30), 'SOS');
      expect(simulate('HOLA', unitMs: 300, fps: 12, jitter: 0.35, dropRate: 0.08, exposureMs: 30), 'HOLA');
    });
  });
}
