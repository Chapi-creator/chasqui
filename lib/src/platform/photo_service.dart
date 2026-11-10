import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Foto elegida y ya comprimida por Android.
class PickedPhoto {
  const PickedPhoto({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;

  int get kilobytes => (bytes.length / 1024).ceil();
}

/// Selector de fotos del sistema.
///
/// Usa el selector de Android (SAF): no pide permiso de almacenamiento y solo
/// devuelve la imagen que el usuario elige. La compresión (480 px, JPEG de
/// ~40 KB) se hace en Kotlin para no cargar una foto de 12 MP en Dart.
class PhotoService {
  static const MethodChannel _channel = MethodChannel('chasqui/photo');

  /// Abre el selector. Devuelve null si el usuario cancela.
  static Future<PickedPhoto?> pick() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('pick');
      if (result == null) return null;
      final bytes = result['bytes'];
      if (bytes is! Uint8List || bytes.isEmpty) return null;
      return PickedPhoto(
        bytes: bytes,
        width: (result['width'] as num?)?.toInt() ?? 0,
        height: (result['height'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (error) {
      debugPrint('Fotos: el selector falló (${error.code}: ${error.message})');
      return null;
    } on MissingPluginException {
      // En escritorio o en pruebas no hay canal nativo.
      return null;
    }
  }

  /// Cuánto va a tardar de forma aproximada. Es una estimación honesta: el
  /// BLE real da entre 1 y 3 KB/s con los dos teléfonos cerca.
  static String estimate(int bytes) {
    final seconds = (bytes / 2000).ceil();
    if (seconds < 10) return 'unos $seconds segundos';
    return 'unos $seconds segundos (dejalos cerca)';
  }
}
