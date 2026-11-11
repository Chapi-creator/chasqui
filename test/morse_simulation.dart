import 'dart:math' as math;

import 'package:chasqui/src/rescue/light_sampler.dart';
import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/morse_decoder.dart';

/// Un tramo del mensaje que se está transmitiendo.
class Span {
  const Span(this.on, this.start, this.end);

  final bool on;
  final int start;
  final int end;
}

/// Qué lee el receptor si el mensaje se manda con estos parámetros.
///
/// Simula la cadena completa: emisor exacto, cámara con fotogramas irregulares y
/// perdidos, retardo de exposición, ruido de la imagen, el muestreador y el
/// decodificador reales. Sirve para lo que no se puede probar con un widget: el
/// receptor entero visto como sistema de tiempo.
///
/// - [jitter]: cuánto varía el intervalo entre fotogramas (0,2 = ±20 %).
/// - [dropRate]: fracción de fotogramas que no llegan.
/// - [exposureMs]: constante de tiempo de la exposición automática; 0 = ideal.
/// - [noise]: ruido del brillo, en fracción de la escala (0,10 = ±5 %).
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
  final windows = <Span>[];
  var t = 0;
  for (final step in steps) {
    final ms = step.units * unitMs;
    windows.add(Span(step.on, t, t + ms));
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
