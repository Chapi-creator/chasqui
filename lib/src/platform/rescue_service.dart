import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Linterna, sirena y pantalla despierta para el panel de señales.
///
/// Todo pasa en el teléfono: ni radio BLE, ni datos, ni servidores. La malla
/// sigue escuchando igual mientras el panel está abierto, y esto no la toca.
class RescueService {
  static const MethodChannel _channel = MethodChannel('chasqui/rescue');

  /// ¿Este teléfono tiene linterna? Se pregunta al abrir el panel.
  static Future<bool> hasTorch() async {
    if (!Platform.isAndroid) return false;
    try {
      final available = await _channel.invokeMethod<bool>('hasTorch');
      return available ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enciende o apaga la linterna. Devuelve false si otra app la tiene tomada.
  static Future<bool> setTorch(bool on) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('torch', {'on': on});
      return ok ?? false;
    } on PlatformException catch (error) {
      debugPrint('Linterna: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sirena de dos tonos en bucle. Devuelve false si el altavoz está ocupado.
  static Future<bool> setSiren(bool on) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('siren', {'on': on});
      return ok ?? false;
    } on PlatformException catch (error) {
      debugPrint('Sirena: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Pitido continuo para el morse escrito. Cada punto y cada raya lo prenden y
  /// lo apagan. Devuelve false si el altavoz está ocupado.
  static Future<bool> setTone(bool on) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('tone', {'on': on});
      return ok ?? false;
    } on PlatformException catch (error) {
      debugPrint('Pitido: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Mantiene la pantalla encendida y a brillo máximo (y lo devuelve al salir).
  ///
  /// Solo se usa mientras hay algo que mostrarle al cielo: una pantalla blanca
  /// a media luz no se ve al sol.
  static Future<void> keepAwake(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('keepAwake', {'on': on});
    } catch (_) {}
  }

  /// Apaga todo lo que el panel pudo encender. Se llama al cerrar la pantalla.
  static Future<void> release() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {}
  }
}
