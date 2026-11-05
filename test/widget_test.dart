import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sinred/src/app.dart';
import 'package:sinred/src/core/identity.dart';
import 'package:sinred/src/data/state_store.dart';
import 'package:sinred/src/mesh/mesh_node.dart';
import 'package:sinred/src/transport/demo_transport.dart';

void main() {
  testWidgets('la pantalla principal explica el chat sin internet',
      (tester) async {
    final identity = await NodeIdentity.generate();
    final node = MeshNode(
      identity: identity,
      store: StateStore(fileName: 'sinred_widget_test.json'),
      transport: DemoMeshTransport(owner: identity),
      monitorBattery: false,
    );
    addTearDown(node.dispose);

    await tester.pumpWidget(SinRedApp(node: node));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('SinRed'), findsOneWidget);
    expect(find.text('Chatea sin internet'), findsOneWidget);
    expect(find.text('Nuevo chat'), findsOneWidget);

    // La radio arranca temporizadores del reloj falso; se apagan en el reloj
    // real para que el test no termine con timers vivos.
    await tester.runAsync(node.stop);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
