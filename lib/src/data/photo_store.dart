import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Guarda las fotos que viajan por la malla en archivos, no en el estado.
///
/// El estado se reescribe entero cada pocos segundos: meter ahí 40 KB en
/// base64 por foto lo convertiría en un archivo de megabytes y la app se
/// trabaría. Un archivo por foto, y el mensaje solo recuerda el nombre.
class PhotoStore {
  PhotoStore({Directory? directory, this.limit = 80}) : _directory = directory;

  final Directory? _directory;

  /// Cuántas fotos se conservan. Al pasarse, se borran las más viejas: en una
  /// emergencia el teléfono tiene que seguir funcionando, no ser un archivo.
  final int limit;

  Directory? _resolved;

  Future<Directory?> _dir() async {
    if (_resolved != null) return _resolved;
    try {
      final base = _directory ?? await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}fotos');
      if (!await dir.exists()) await dir.create(recursive: true);
      _resolved = dir;
      return dir;
    } catch (error) {
      // Sin almacenamiento disponible, las fotos se muestran vacías pero los
      // mensajes y la identidad siguen funcionando.
      debugPrint('Fotos: almacenamiento no disponible ($error)');
      return null;
    }
  }

  /// Guarda la foto y devuelve su nombre de archivo, o null si no se pudo.
  Future<String?> save(Uint8List bytes, {required String idHex}) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final name = '$idHex.jpg';
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      await _trim(dir);
      return name;
    } catch (error) {
      debugPrint('Fotos: no se pudo guardar ($error)');
      return null;
    }
  }

  Future<Uint8List?> load(String name) async {
    final dir = await _dir();
    if (dir == null) return null;
    try {
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (error) {
      debugPrint('Fotos: no se pudo leer ($error)');
      return null;
    }
  }

  Future<void> _trim(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.jpg'))
          .cast<File>()
          .toList();
      if (files.length <= limit) return;
      files.sort(
        (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
      );
      for (final file in files.take(files.length - limit)) {
        try {
          await file.delete();
        } catch (_) {
          // Sin importancia: se reintenta en el próximo guardado.
        }
      }
    } catch (error) {
      debugPrint('Fotos: no se pudo limpiar ($error)');
    }
  }
}
