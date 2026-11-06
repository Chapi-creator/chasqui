import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sinred/src/core/board.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/mesh/mesh_node.dart';
import 'package:sinred/src/ui/board_page.dart';

import 'support/fake_transport.dart';

void main() {
  testWidgets(
    'el tablero muestra los avisos y deja publicar uno',
    (tester) async {
      // Todo lo que toca disco o criptografía corre en tiempo real; el reloj
      // falso se reserva para la interfaz.
      late MeshNode node;
      late FakeTransport transport;
      late Directory directory;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp('sinred_board_ui');
        transport = FakeTransport();
        node = MeshNode(
          identity: await NodeIdentity.generate(),
          store: StateStore(directory: directory),
          transport: transport,
          monitorBattery: false,
        );
        await node.start();
        await node.sendBoardPost(BoardCategory.need, 'Falta agua refugio');
      });

      await tester.pumpWidget(
        ChangeNotifierProvider<MeshNode>.value(
          value: node,
          child: const MaterialApp(home: BoardPage()),
        ),
      );
      await tester.pump();

      expect(find.text('Tablero de emergencia'), findsOneWidget);
      expect(find.text('Falta agua refugio'), findsOneWidget);
      expect(find.text('Necesito (1)'), findsOneWidget);
      expect(find.textContaining('caduca en'), findsOneWidget);

      // El formulario de publicación.
      await tester.tap(find.text('Publicar en necesito'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Corto y concreto: qué, dónde y desde cuándo.'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'Medicinas señora Rosa');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Publicar'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'el diálogo se cierra al publicar',
      );
      // El envío usa criptografía real: se le da un ciclo de reloj real.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        node.boardPosts(BoardCategory.need).map((post) => post.text),
        contains('Medicinas señora Rosa'),
      );
      expect(find.text('Medicinas señora Rosa'), findsOneWidget);
      expect(find.text('Necesito (2)'), findsOneWidget);

      await tester.runAsync(() async {
        await node.stop();
        await transport.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
