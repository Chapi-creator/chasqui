import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reparte el APK de la app sin internet.
///
/// Usa la hoja de compartir de Android: Quick Share, Bluetooth o cualquier
/// app de archivos lo entregan teléfono a teléfono. No hace falta Play Store
/// ni datos móviles, que es justo lo que falla en un apagón.
class AppShare {
  static const MethodChannel _channel = MethodChannel('chasqui/share');

  /// Abre el selector del sistema con el APK adjunto.
  static Future<bool> shareApk() async {
    if (!Platform.isAndroid) return false;
    try {
      final sent = await _channel.invokeMethod<bool>('shareApk');
      return sent ?? false;
    } on PlatformException catch (error) {
      debugPrint('Compartir app: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
