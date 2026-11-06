import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Servicio en primer plano (Android) que mantiene vivo el proceso mientras la
/// app está en segundo plano. Sin él, el sistema puede congelar el escaneo BLE
/// y los mensajes dejarían de llegar.
class PowerService {
  static const MethodChannel _channel = MethodChannel('sinred/power');

  /// Pide permisos de Bluetooth y notificaciones (Android 12+/13+).
  ///
  /// Espera a que el usuario responda al diálogo: si se lanzara la radio antes,
  /// Android 14 rechaza el servicio en primer plano y no se puede escanear.
  /// El tope de tiempo evita que la app se quede sin radio si la respuesta se
  /// pierde al recrearse la Activity.
  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel
          .invokeMethod<bool>('requestPermissions')
          .timeout(const Duration(seconds: 30), onTimeout: () => null);
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// ¿Hay al menos un permiso de Bluetooth concedido?
  static Future<bool> hasPermissions() async {
    if (!Platform.isAndroid) return false;
    try {
      final granted = await _channel.invokeMethod<bool>('hasPermissions');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> startForeground({String text = 'Malla activa'}) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('startForeground', {
        'text': text,
      });
      return result ?? false;
    } on PlatformException catch (error) {
      debugPrint('PowerService: ${error.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stopForeground() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stopForeground');
    } catch (_) {}
  }

  static Future<void> updateText(String text) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateText', {'text': text});
    } catch (_) {}
  }

  /// Aviso local de que un contacto guardado está al alcance.
  ///
  /// No es el servicio en primer plano: es una notificación suelta, así que no
  /// mantiene el proceso vivo ni impide que el usuario la descarte. Incluye
  /// [peerId] para que tocarla abra justo ese chat.
  static Future<void> notifyContact(
    String name, {
    required String peerId,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('notifyContact', {
        'name': name,
        'peerId': peerId,
        'body': body,
      });
    } catch (_) {}
  }

  /// Aviso del canal abierto (estado o SOS).
  ///
  /// Un SOS usa un canal de notificación de importancia máxima y vibra; un
  /// estado normal no interrumpe. Tocarlo abre la conversación del canal.
  static Future<void> notifyChannel({
    required String title,
    required String body,
    required bool sos,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('notifyChannel', {
        'title': title,
        'body': body,
        'sos': sos,
      });
    } catch (_) {}
  }

  /// Recibe el id del nodo cuando el usuario toca una notificación.
  static void setChatOpenHandler(void Function(String peerId)? handler) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openChat') {
        final peerId = call.arguments as String?;
        if (peerId != null && peerId.isNotEmpty) handler?.call(peerId);
      }
      return null;
    });
  }

  /// Chat pedido desde una notificación antes de que la app arrancara.
  static Future<String?> takePendingChat() async {
    if (!Platform.isAndroid) return null;
    try {
      final peerId = await _channel.invokeMethod<String>('consumePendingChat');
      if (peerId == null || peerId.isEmpty) return null;
      return peerId;
    } catch (_) {
      return null;
    }
  }

  /// Abre los ajustes del sistema para excluir la app de la optimización de
  /// batería (el usuario decide; no forzamos nada).
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openBatterySettings');
    } catch (_) {}
  }
}
