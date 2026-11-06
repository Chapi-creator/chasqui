import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Brújula del teléfono, sin internet.
///
/// Solo se enciende mientras hay un chat abierto con alguien cuya posición se
/// conoce: el magnetómetro gasta batería y no tiene sentido tenerlo siempre
/// escuchando.
class CompassService {
  static const MethodChannel _channel = MethodChannel('sinred/sensors');
  static final StreamController<double> _headings =
      StreamController<double>.broadcast();

  static bool _listening = false;
  static bool _available = false;

  /// Pantallas que usan la brújula ahora mismo.
  ///
  /// Con dos chats apilados (uno abierto desde una notificación) cerrar el de
  /// arriba apagaba el sensor y el de abajo se quedaba con una flecha congelada.
  static int _users = 0;

  /// Rumbo del teléfono en grados (0 = norte, sentido horario).
  static Stream<double> get headings => _headings.stream;

  /// ¿El teléfono tiene brújula? Se sabe después de llamar a [start].
  static bool get available => _available;

  static void _ensureListener() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'heading') {
        final value = (call.arguments as num?)?.toDouble();
        if (value != null && _headings.hasListener) _headings.add(value);
      }
      return null;
    });
  }

  static Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    _ensureListener();
    _users += 1;
    if (_users > 1) return _available;
    try {
      final started = await _channel.invokeMethod<bool>('start');
      _available = started ?? false;
      return _available;
    } on PlatformException catch (error) {
      debugPrint('Brújula: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    if (_users > 0) _users -= 1;
    if (_users > 0) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
