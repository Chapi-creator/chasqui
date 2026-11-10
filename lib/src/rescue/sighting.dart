import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cuánto hace que no se ve a nadie, en palabras.
///
/// Es el dato que cambia la decisión: a los veinte minutos uno sigue
/// confiando en que vuelvan; a las seis horas ya hay que moverse o cambiar de
/// señal. Por eso el texto crece en detalle con el tiempo.
String formatSightingAge(Duration age) {
  // Un reloj ajustado a mano puede dejar la marca en el futuro.
  if (age.isNegative) return 'recién';
  final seconds = age.inSeconds;
  if (seconds < 15) return 'recién';
  if (seconds < 60) return 'hace $seconds s';
  final minutes = age.inMinutes;
  if (minutes < 60) return 'hace $minutes min';
  final hours = age.inHours;
  if (hours < 24) {
    final rest = minutes - hours * 60;
    return rest == 0 ? 'hace $hours h' : 'hace $hours h $rest min';
  }
  final days = age.inDays;
  final restHours = hours - days * 24;
  return restHours == 0 ? 'hace $days d' : 'hace $days d $restHours h';
}

/// Momento del último avistamiento, guardado en su propio archivo.
///
/// Va aparte del estado de la malla a propósito: el contador tiene que seguir
/// siendo cierto aunque la app se cierre para ahorrar batería, y no conviene
/// mezclarlo con identidad, contactos y mensajes (si ese archivo se corrompe,
/// se pierde todo lo demás).
class SightingLog {
  SightingLog({Directory? directory, this.fileName = 'chasqui_rescate.json'})
    : _directory = directory;

  final Directory? _directory;
  final String fileName;

  Future<File?> _file() async {
    try {
      final directory = _directory ?? await getApplicationDocumentsDirectory();
      return File('${directory.path}${Platform.pathSeparator}$fileName');
    } catch (error) {
      debugPrint('Rescate: almacenamiento no disponible ($error)');
      return null;
    }
  }

  Future<DateTime?> load() async {
    final file = await _file();
    if (file == null || !await file.exists()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      final stamp = raw is Map ? raw['sighting'] : null;
      if (stamp is! int || stamp <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(stamp);
    } catch (error) {
      debugPrint('Rescate: marca ilegible ($error)');
      return null;
    }
  }

  /// Escritura atómica (temporal y rename): si el teléfono se apaga a mitad,
  /// la marca anterior sigue entera en lugar de quedar un JSON truncado.
  Future<void> save(DateTime time) async {
    final file = await _file();
    if (file == null) return;
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(
        jsonEncode({'v': 1, 'sighting': time.millisecondsSinceEpoch}),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('Rescate: no se pudo guardar la marca ($error)');
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Se reintenta en la próxima marca; no hay nada más que hacer.
      }
    }
  }
}
