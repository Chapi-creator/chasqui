import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/ui/light_send_sheet.dart';

Future<void> pumpSheet(WidgetTester tester, {String initialText = ''}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LightSendSheet(initialText: initialText),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('mandar con la linterna', () {
    testWidgets('sin texto no deja transmitir', (tester) async {
      await pumpSheet(tester);
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Transmitir'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('muestra el morse y la duración de lo escrito', (tester) async {
      await pumpSheet(tester, initialText: 'SOS');
      expect(find.text('... --- ...'), findsOneWidget);
      expect(find.textContaining('ms por punto'), findsWidgets);
    });

    testWidgets('avisa qué caracteres quedan afuera', (tester) async {
      await pumpSheet(tester, initialText: 'SOS €');
      expect(find.textContaining('quedan afuera'), findsOneWidget);
    });

    testWidgets('el texto que se escribe reemplaza al inicial', (tester) async {
      await pumpSheet(tester);
      await tester.enterText(find.byType(TextField), 'AGUA');
      await tester.pump();
      expect(find.text('.- --. ..- .-'), findsOneWidget);
    });
  });
}
