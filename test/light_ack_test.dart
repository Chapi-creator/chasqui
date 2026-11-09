import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/light_ack.dart';

void main() {
  group('confirmación por luz', () {
    test('no contesta mientras haya texto a medio armar', () {
      expect(
        ackDue(
          hasText: false,
          alreadyAcked: false,
          lightOn: false,
          silenceMs: 5000,
        ),
        isFalse,
      );
    });

    test('espera a que el silencio supere el fin de palabra', () {
      expect(
        ackDue(
          hasText: true,
          alreadyAcked: false,
          lightOn: false,
          silenceMs: ackSilenceMs - 1,
        ),
        isFalse,
        reason: 'a 1.9 s todavía podría estar llegando otra letra',
      );
      expect(
        ackDue(
          hasText: true,
          alreadyAcked: false,
          lightOn: false,
          silenceMs: ackSilenceMs,
        ),
        isTrue,
      );
    });

    test('con la luz encendida no se contesta', () {
      expect(
        ackDue(
          hasText: true,
          alreadyAcked: false,
          lightOn: true,
          silenceMs: 9000,
        ),
        isFalse,
        reason: 'el destello se mezclaría con el mensaje del otro lado',
      );
    });

    test('contesta una sola vez por mensaje', () {
      expect(
        ackDue(
          hasText: true,
          alreadyAcked: true,
          lightOn: false,
          silenceMs: 60000,
        ),
        isFalse,
      );
    });

    test('los dos destellos son cortos y no se solapan', () {
      expect(ackPulses, 2);
      expect(ackPulseMs, lessThan(ackSilenceMs));
      expect(ackGapMs, greaterThan(0));
    });
  });
}
