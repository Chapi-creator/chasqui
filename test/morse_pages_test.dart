import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/rescue/morse.dart';
import 'package:sinred/src/ui/morse_learn_page.dart';
import 'package:sinred/src/ui/morse_receiver_page.dart';
import 'package:sinred/src/ui/telegraph_page.dart';

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
  });

  group('telegrafía', () {
    testWidgets('el SOS está listo para transmitir', (tester) async {
      await pumpPage(tester, const TelegraphPage());
      expect(find.text('... --- ...'), findsOneWidget);
    });
  });
}
