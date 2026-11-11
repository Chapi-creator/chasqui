import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/morse_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

import 'morse_simulation.dart';

/// QA del receptor de morse visto como sistema: qué se lee con cada cámara y
/// qué pasa en los bordes (sin señal, mensajes largos, ruido, cambios de ritmo).
///
/// Los números de la matriz salen de medir el receptor real (muestreador +
/// decodificador) contra una cámara simulada: fotogramas irregulares y
/// perdidos, exposición lenta y ruido de imagen. Cada banda exige un piso un
/// poco más bajo que lo medido: si alguien toca el muestreador o el
/// decodificador y algo empeora, esta prueba falla antes de publicar.
void main() {
  const mensajes = [
    'SOS',
    'HOLA',
    'AGUA',
    'CASA',
    'AYUDA',
    'SOS SOS',
    'NO HAY AGUA',
    'NECESITO MEDICO EN EL REFUGIO',
  ];
  const unidades = [300, 200, 120];
  const camaras = [30.0, 24.0, 20.0, 15.0, 12.0, 10.0];
  const temblores = [0.2, 0.35];
  const perdidas = [0.03, 0.08];
  const exposiciones = [0.0, 30.0, 60.0];
  const ruidos = [0.02, 0.10];

  /// Un acierto solo cuenta si el mensaje entero salió igual.
  Map<String, ({int ok, int total, List<String> fallos})> barrido() {
    final out = <String, ({int ok, int total, List<String> fallos})>{};
    for (final unit in unidades) {
      for (final fps in camaras) {
        var ok = 0;
        var total = 0;
        final fallos = <String>[];
        for (final jitter in temblores) {
          for (final drop in perdidas) {
            for (final expo in exposiciones) {
              for (final noise in ruidos) {
                for (final mensaje in mensajes) {
                  final leido = simulate(
                    mensaje,
                    unitMs: unit,
                    fps: fps,
                    jitter: jitter,
                    dropRate: drop,
                    exposureMs: expo,
                    noise: noise,
                  );
                  total++;
                  if (leido == mensaje) {
                    ok++;
                  } else if (fallos.length < 4) {
                    fallos.add('"$mensaje" -> "$leido" '
                        '(temblor $jitter, ${(drop * 100).round()} % perdidos, '
                        'exposición $expo, ruido $noise)');
                  }
                }
              }
            }
          }
        }
        out['$unit/$fps'] = (ok: ok, total: total, fallos: fallos);
      }
    }
    return out;
  }

  group('matriz de cámaras', () {
    late Map<String, ({int ok, int total, List<String> fallos})> celdas;

    setUpAll(() => celdas = barrido());

    ({int ok, int total, List<String> fallos}) celda(int unit, double fps) =>
        celdas['$unit/$fps']!;

    test('ritmo lento: ninguna lectura mal con cualquier cámara', () {
      // Medido: 100 % de 192 combinaciones por cadencia, de 30 a 10 imágenes
      // por segundo, con exposición de hasta 60 ms y ruido de ±5 %.
      for (final fps in camaras) {
        final c = celda(300, fps);
        expect(
          c.ok,
          c.total,
          reason: 'a $fps por segundo falló: ${c.fallos.join(' | ')}',
        );
      }
    });

    test('ritmo normal: perfecto desde 20 imágenes por segundo', () {
      for (final fps in [30.0, 24.0, 20.0]) {
        final c = celda(200, fps);
        expect(
          c.ok,
          c.total,
          reason: 'a $fps por segundo falló: ${c.fallos.join(' | ')}',
        );
      }
    });

    test('ritmo normal: aguanta 15 por segundo y cae con 12 o menos', () {
      // Medido: 98 % a 15, 87 % a 12 y 90 % a 10. Con 12 fotogramas por
      // segundo una pausa de 200 ms entra en dos fotogramas y a veces en uno:
      // ahí ya no hay información suficiente, pero el receptor no se desarma.
      expect(celda(200, 15).ok / celda(200, 15).total, greaterThan(0.95));
      expect(celda(200, 12).ok / celda(200, 12).total, greaterThan(0.85));
      expect(celda(200, 10).ok / celda(200, 10).total, greaterThan(0.85));
    });

    test('ritmo rápido: solo con cámara de 30 y exposición corta', () {
      // Medido: 91 % a 30, 79 % a 24, 64 % a 20, 57 % a 15, 35 % a 12 y 3 % a
      // 10. Es el límite físico: con 120 ms por punto hacen falta tres
      // fotogramas por punto y una cámara de 15 por segundo da 1,4. Por eso la
      // app avisa al elegir Rápido y el receptor sugiere 200 ms.
      expect(celda(120, 30).ok / celda(120, 30).total, greaterThan(0.85));
      expect(celda(120, 24).ok / celda(120, 24).total, greaterThan(0.70));
      expect(celda(120, 20).ok / celda(120, 20).total, greaterThan(0.55));
      expect(celda(120, 12).ok / celda(120, 12).total, greaterThan(0.25));
    });

    test('ninguna celda se derrumba a cero', () {
      for (final unit in unidades) {
        for (final fps in camaras) {
          final c = celda(unit, fps);
          expect(c.ok, greaterThan(0), reason: '$unit ms a $fps por segundo');
        }
      }
    });

    test('el ritmo elegido por defecto es el que mejor aguanta', () {
      // A igual cámara, 300 ms nunca es peor que 200, y 200 nunca es peor que
      // 120. Es lo que justifica que la app arranque en 200 y avise en 120.
      for (final fps in camaras) {
        expect(celda(300, fps).ok, greaterThanOrEqualTo(celda(200, fps).ok));
        expect(celda(200, fps).ok, greaterThanOrEqualTo(celda(120, fps).ok));
      }
    });
  });

  group('casos borde', () {
    test('sin luz no hay lectura', () {
      final decoder = MorseDecoder();
      for (var i = 0; i < 50; i++) {
        decoder.gap(200);
      }
      expect(decoder.reading.isEmpty, isTrue);
      expect(decoder.reading.unitMs, isNull);
    });

    test('marcas de ruido demasiado cortas se descartan', () {
      final decoder = MorseDecoder();
      for (var i = 0; i < 10; i++) {
        decoder.mark(12);
        decoder.gap(60);
      }
      expect(decoder.reading.isEmpty, isTrue);
    });

    test('un mensaje vacío no inventa letras', () {
      expect(simulate(''), '');
    });

    test('números y palabras largas se leen enteros', () {
      // Ocho caracteres con cinco símbolos cada uno y espacios: el caso más
      // largo de una letra en morse.
      expect(simulate('SOS 911', unitMs: 300, fps: 30), 'SOS 911');
      expect(
        simulate('NECESITO MEDICO EN EL REFUGIO', unitMs: 200, fps: 30),
        'NECESITO MEDICO EN EL REFUGIO',
      );
    });

    test('después de borrar, un mensaje nuevo se lee limpio', () {
      final decoder = MorseDecoder();
      void feed(String texto, int unit) {
        final pasos = MorseMessage.encode(texto).steps;
        for (final paso in pasos) {
          final ms = paso.units * unit;
          paso.on ? decoder.mark(ms) : decoder.gap(ms);
        }
      }

      feed('SOS', 200);
      decoder.closeLetter();
      expect(decoder.reading.text, 'SOS');

      decoder.clear();
      expect(decoder.reading.isEmpty, isTrue);

      feed('HOLA', 300);
      decoder.closeLetter();
      expect(decoder.reading.text, 'HOLA');
      expect(decoder.reading.unitMs, closeTo(300, 30));
    });

    test('el último símbolo queda a la vista aunque no llegue la pausa', () {
      // La cámara se queda mirando la última marca: sin cerrar la letra, el
      // receptor no puede saber que terminó. closeLetter lo resuelve.
      final decoder = MorseDecoder();
      const marcas = [200, 200, 200];
      const pausas = [200, 200];
      for (var i = 0; i < marcas.length; i++) {
        decoder.mark(marcas[i]);
        if (i < pausas.length) decoder.gap(pausas[i]);
      }
      expect(decoder.reading.pending, '. . .');
      decoder.closeLetter();
      expect(decoder.reading.text, 'S');
    });

    test('un chorro de miles de tramos no rompe ni se cuelga', () {
      final decoder = MorseDecoder();
      for (var i = 0; i < 5000; i++) {
        decoder.mark(200);
        decoder.gap(200);
      }
      // No se exige que el texto sea correcto: solo que responda y que la
      // unidad siga siendo la del emisor.
      expect(decoder.reading.unitMs, closeTo(200, 20));
    });

    test('un temblor suelto antes del mensaje no lo arruina', () {
      expect(
        simulate('SOS', unitMs: 200, fps: 30, jitter: 0.2, noise: 0.10),
        'SOS',
      );
    });

    test('la unidad estimada acompaña al emisor en los tres ritmos', () {
      for (final unit in [300, 200, 120]) {
        final decoder = MorseDecoder();
        final pasos = MorseMessage.encode('SOS').steps;
        for (final paso in pasos) {
          final ms = paso.units * unit;
          paso.on ? decoder.mark(ms) : decoder.gap(ms);
        }
        decoder.closeLetter();
        expect(decoder.reading.text, 'SOS', reason: 'ritmo $unit ms');
        expect(decoder.reading.unitMs, closeTo(unit, unit * 0.15));
      }
    });
  });
}
