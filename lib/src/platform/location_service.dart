import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/geo.dart';

/// Ubicación del teléfono, sin internet y sin cuentas.
///
/// El permiso y el GPS los gestiona la capa nativa. Aquí solo se expone el
/// flujo de posiciones y se traduce a objetos del dominio.
class LocationService {
  static const MethodChannel _channel = MethodChannel('sinred/location');
  static final StreamController<GeoPoint> _updates =
      StreamController<GeoPoint>.broadcast();

  static bool _listening = false;

  /// Posiciones nuevas mientras el GPS está encendido.
  static Stream<GeoPoint> get updates => _updates.stream;

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'update') {
        final point = GeoPoint.fromMap(call.arguments);
        if (point != null) _updates.add(point);
      }
      return null;
    });
  }

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pide el permiso de ubicación y espera la respuesta del usuario.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel
          .invokeMethod<bool>('requestPermission')
          .timeout(const Duration(seconds: 30), onTimeout: () => false);
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Enciende las actualizaciones (15 s / 10 m). Devuelve false si no hay
  /// permiso o el GPS está apagado en el sistema.
  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    _ensureListener();
    try {
      final started = await _channel.invokeMethod<bool>('start');
      return started ?? false;
    } on PlatformException catch (error) {
      debugPrint('Ubicación: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// Última posición conocida, sin encender las actualizaciones.
  static Future<GeoPoint?> current() async {
    if (!Platform.isAndroid) return null;
    _ensureListener();
    try {
      final raw = await _channel.invokeMethod<Object?>('current');
      return GeoPoint.fromMap(raw);
    } catch (_) {
      return null;
    }
  }

  /// Ajustes de la app, para cuando el usuario negó el permiso para siempre.
  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }
}
