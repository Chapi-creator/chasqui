import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/mesh/mesh_node.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final node = await MeshNode.bootstrap();
  runApp(SinRedApp(node: node));
  // Los permisos se piden dentro de SinRedApp, con la Activity ya visible y
  // antes de arrancar la radio (ver _bootstrapRadio).
}
