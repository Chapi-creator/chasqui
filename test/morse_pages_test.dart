import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/rescue/light_calibration.dart';
import 'package:chasqui/src/rescue/morse.dart';
import 'package:chasqui/src/rescue/morse_log.dart';
import 'package:chasqui/src/ui/morse_field_test_page.dart';
import 'package:chasqui/src/ui/morse_learn_page.dart';
import 'package:chasqui/src/ui/morse_receiver_page.dart';
import 'package:chasqui/src/ui/telegraph_page.dart';

/// Pantalla alta: las páginas son listas largas y en 800x600 el juego y el
/// botón de transmitir quedarían fuera del árbol.
Future<void> pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pump();
}

/// El código grande del juego, para saber qué letra preguntó.
String quizCode(WidgetTester tester) {
  final text = tester.widgetList<Text>(find.byType(Text)).firstWhere(
    (widget) =>
        widget.style?.fontSize == 40 && (widget.data ?? '').contains(RegExp(r'[.-]')),
  );
  return text.data!;
}

void main() {
  group('pantalla de aprender', () {
    testWidgets('muestra el abecedario y la palabra de ejemplo', (tester) async {
      await pumpPage(tester, const MorseLearnPage(quizSeed: 1));
      expect(find.text('El abecedario'), findsOneWidget);
      expect(find.text('Armá una palabra'), findsOneWidget);
      // Las 56 entradas de la tabla están en la grilla.
      expect(find.text('Ñ'), findsOneWidget);
      expect(find.text('--.--'), findsOneWidget);
    });

    testWidgets('acertar suma un punto', (tester) async {
      await pumpPage(tester, const MorseLearnPage(quizSeed: 3));
      expect(find.text('Aciertos: 0 de 0'), findsOneWidget);

      final answer = reverseMorse[quizCode(tester)];
      expect(answer, isNotNull, reason: 'el código preguntado debe existir');

      await tester.tap(find.widgetWithText(OutlinedButton, answer!));
      await tester.pump();

      expect(find.text('Aciertos: 1 de 1'), findsOneWidget);
      expect(find.text('Siguiente'), findsOneWidget);
    });

    testWidgets('equivoarse no suma y muestra la respuesta', (tester) async {
      await pumpPage(tester, const MorseLearnPage(quizSeed: 5));
      final answer = reverseMorse[quizCode(tester)]!;
      // Cualquier opción que no sea la correcta, de las que se muestran.
      final wrong = [
        for (final option in const ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'])
          if (option != answer &&
              find.widgetWithText(OutlinedButton, option).evaluate().isNotEmpty)
            option,
      ].first;

      await tester.tap(find.widgetWithText(OutlinedButton, wrong));
      await tester.pump();

      expect(find.text('Aciertos: 0 de 1'), findsOneWidget);
      expect(find.text('Escuchar la $answer'), findsOneWidget);
    });
  });

  group('pantalla de recibir', () {
    testWidgets('sin cámara ofrece el modo por toques', (tester) async {
      await pumpPage(tester, const MorseReceiverPage(enableCamera: false));
      expect(find.text('Recibir morse'), findsOneWidget);
      expect(find.text('Sin cámara: a mano'), findsOneWidget);
      expect(find.text('Todavía no llegó ninguna marca.'), findsOneWidget);
    });

    testWidgets('sin cámara el botón de calibrar queda apagado', (tester) async {
      await pumpPage(tester, const MorseReceiverPage(enableCamera: false));
      expect(find.text('Calibrar'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Calibrar'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('el historial muestra lo leído y se puede borrar', (
      tester,
    ) async {
      var cleared = 0;
      await pumpPage(
        tester,
        MorseReceiverPage(
          enableCamera: false,
          history: [
            MorseLogEntry(
              text: 'SOS',
              at: DateTime.now(),
              marks: 9,
              unitMs: 120,
            ),
          ],
          onClearHistory: () => cleared++,
        ),
      );
      expect(find.text('Lo que ya leíste'), findsOneWidget);
      expect(find.text('SOS'), findsOneWidget);
      expect(find.textContaining('9 marcas'), findsOneWidget);

      await tester.tap(find.text('Borrar historial'));
      await tester.pump();
      expect(cleared, 1);
    });

    testWidgets('guardar queda apagado sin mensaje', (tester) async {
      await pumpPage(tester, const MorseReceiverPage(enableCamera: false));
      final guardar = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Guardar'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(guardar.onPressed, isNull);
    });

    testWidgets('la confirmación por linterna viene activa y se apaga', (
      tester,
    ) async {
      await pumpPage(tester, const MorseReceiverPage(enableCamera: false));
      expect(find.text('Confirmar la recepción'), findsOneWidget);
      // El primero es el de la cámara: el de la confirmación es el último.
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);

      await tester.tap(find.byType(Switch).last);
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch).last).value, isFalse);
    });

    testWidgets('con calibración guardada ofrece repetirla o quitarla', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const MorseReceiverPage(
          enableCamera: false,
          calibration: LightCalibration(dark: 0.15, bright: 0.85),
        ),
      );
      expect(find.text('Repetir'), findsOneWidget);
      expect(find.text('Quitar calibración'), findsOneWidget);
    });
  });

  group('telegrafía', () {
    testWidgets('el SOS está listo para transmitir', (tester) async {
      await pumpPage(tester, const TelegraphPage());
      expect(find.text('... --- ...'), findsOneWidget);
    });
  });
  group('prueba de campo', () {
    testWidgets('recorre las ocho palabras y da el resultado', (tester) async {
      await pumpPage(tester, const MorseFieldTestPage(seed: 5));
      expect(find.text('Palabra 1 de 8'), findsOneWidget);
      expect(find.text('Aciertos: 0'), findsOneWidget);

      for (var i = 1; i <= 8; i++) {
        expect(find.text('Palabra $i de 8'), findsOneWidget);
        await tester.tap(find.text('Leí bien'));
        await tester.pump();
      }

      expect(find.text('Resultado'), findsOneWidget);
      expect(find.text('8 de 8 · 100 %'), findsOneWidget);
      expect(find.textContaining('Excelente'), findsOneWidget);
    });

    testWidgets('una falla se refleja en el número', (tester) async {
      await pumpPage(tester, const MorseFieldTestPage(seed: 9));
      for (var i = 1; i <= 8; i++) {
        await tester.tap(find.text(i == 4 ? 'Leí mal' : 'Leí bien'));
        await tester.pump();
      }
      expect(find.text('7 de 8 · 88 %'), findsOneWidget);
      expect(find.textContaining('Sirve'), findsOneWidget);
    });
  });

}
