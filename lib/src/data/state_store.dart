import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models.dart';
import '../power/power_policy.dart';
import '../rescue/light_calibration.dart';
import '../rescue/morse_log.dart';

/// Estado que sobrevive al cierre de la app: identidad, mensajes, contactos y
/// mensajes aún sin entregar (store-and-forward real, no solo en memoria).
class AppSnapshot {
  AppSnapshot({
    required this.displayName,
    required this.privateKey,
    required this.messages,
    required this.peers,
    required this.outbox,
    required this.radioMode,
    required this.useDemo,
    this.shareLocation = false,
    this.showProximity = false,
    this.relayMode = false,
    this.lightCalibration,
    this.morseLog = const <MorseLogEntry>[],
  });

  final String displayName;
  final Uint8List privateKey;
  final List<ChatMessage> messages;
  final List<PeerRecord> peers;

  /// Entradas de la cola de salida tal cual las serializa `Outbox.encode()`
  /// (`b`: trama en base64, `q`: instante de encolado).
  final List<Map<String, dynamic>> outbox;
  final RadioMode radioMode;
  final bool useDemo;

  /// El usuario aceptó compartir sus coordenadas con sus contactos.
  final bool shareLocation;

  /// Mostrar distancia y dirección de quien comparte su ubicación.
  final bool showProximity;

  /// El teléfono hace de repetidor de la malla (escucha casi siempre).
  final bool relayMode;

  /// Umbrales del receptor de morse medidos en el lugar, si se calibró.
  final LightCalibration? lightCalibration;

  /// Mensajes leídos con el receptor de morse, del más nuevo al más viejo.
  final List<MorseLogEntry> morseLog;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'name': displayName,
    'key': base64Encode(privateKey),
    'messages': messages.map((m) => m.toJson()).toList(),
    'peers': peers.map((p) => p.toJson()).toList(),
    'outbox': outbox,
    'mode': radioMode.name,
    'demo': useDemo,
    'shareLocation': shareLocation,
    'showProximity': showProximity,
    'relayMode': relayMode,
    if (lightCalibration != null) 'lightCal': lightCalibration!.toJson(),
    if (morseLog.isNotEmpty)
      'morse': morseLog.map((entry) => entry.toJson()).toList(),
  };

  factory AppSnapshot.fromJson(Map<String, dynamic> json) => AppSnapshot(
    displayName: json['name'] as String? ?? 'Yo',
    privateKey: base64Decode(json['key'] as String),
    messages: (json['messages'] as List<dynamic>? ?? [])
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    peers: (json['peers'] as List<dynamic>? ?? [])
        .map((p) => PeerRecord.fromJson(p as Map<String, dynamic>))
        .toList(),
    outbox: _decodeOutbox(json['outbox']),
    radioMode: RadioMode.fromName(json['mode'] as String?),
    useDemo: json['demo'] as bool? ?? false,
    shareLocation: json['shareLocation'] as bool? ?? false,
    showProximity: json['showProximity'] as bool? ?? false,
    relayMode: json['relayMode'] as bool? ?? false,
    lightCalibration: LightCalibration.fromJson(json['lightCal']),
    morseLog: _decodeMorseLog(json['morse']),
  );

  /// El historial no puede romper la carga entera: si el campo viene con otra
  /// forma (estado escrito por una versión distinta o archivo tocado), se
  /// descarta solo eso y se conservan identidad, contactos y mensajes.
  static List<MorseLogEntry> _decodeMorseLog(Object? raw) {
    if (raw is! List) return const <MorseLogEntry>[];
    return raw
        .map(MorseLogEntry.fromJson)
        .whereType<MorseLogEntry>()
        .toList();
  }

  /// Acepta el formato actual (mapa con fecha) y el antiguo (base64 suelto)
  /// para no perder la cola de quien ya tenía estado guardado.
  static List<Map<String, dynamic>> _decodeOutbox(Object? raw) {
    final list = raw as List<dynamic>? ?? const <dynamic>[];
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is String) {
        out.add({'b': item, 'q': DateTime.now().millisecondsSinceEpoch});
      } else if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }
}

class StateStore {
  StateStore({this.fileName = 'chasqui_state.json', Directory? directory})
    : _directory = directory;

  final String fileName;

  /// Solo para tests: permite escribir en un directorio temporal.
  final Directory? _directory;

  /// Cerrojo de escritura: `save` puede llamarse mientras otra ya está en
  /// curso (el temporizador de 2 s y un cierre de la app, por ejemplo). Dos
  /// escrituras simultáneas al mismo temporal podían dejar el JSON truncado o
  /// reventar el rename, y con él la identidad y los contactos.
  bool _writing = false;
  final List<Completer<void>> _waiting = <Completer<void>>[];

  Future<File?> _file() async {
    try {
      final directory = _directory ?? await getApplicationDocumentsDirectory();
      return File('${directory.path}${Platform.pathSeparator}$fileName');
    } catch (error) {
      debugPrint('Almacenamiento no disponible ($error)');
      return null;
    }
  }

  Future<AppSnapshot?> load() async {
    final file = await _file();
    if (file == null || !await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AppSnapshot.fromJson(json);
    } catch (error) {
      debugPrint('Estado corrupto, se reinicia ($error)');
      return null;
    }
  }

  /// Escritura atómica: primero el temporal y después el rename. Si el proceso
  /// muere a mitad, el archivo bueno sigue intacto en lugar de quedar un JSON
  /// truncado (lo que haría perder identidad, contactos e historial).
  Future<void> save(AppSnapshot snapshot) async {
    if (_writing) {
      // Se espera el turno con un Completer creado aquí: encadenar la escritura
      // a una Future guardada de antes rompía al cambiar de zona (los tests de
      // widgets cierran la app desde `runAsync` y el futuro nunca despertaba).
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _writing = true;
    try {
      await _write(snapshot);
    } finally {
      _writing = false;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }

  Future<void> _write(AppSnapshot snapshot) async {
    final file = await _file();
    if (file == null) return;
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
      await temp.rename(file.path);
    } catch (error) {
      debugPrint('No se pudo guardar el estado ($error)');
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Sin importancia: se reescribe en el siguiente guardado.
      }
    }
  }
}
