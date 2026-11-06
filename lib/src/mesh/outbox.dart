import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/frame.dart';

/// Trama esperando confirmación (mensajes propios) o reenvío (tramas de otros).
class OutboxEntry {
  OutboxEntry({
    required this.frame,
    required this.queuedAt,
    this.attempts = 0,
    this.lastAttempt,
  });

  final MeshFrame frame;
  final DateTime queuedAt;
  int attempts;
  DateTime? lastAttempt;

  String get key => frame.dedupKey;
}

/// Cola acotada de tramas pendientes.
///
/// - Mensajes propios sin confirmar: se reintentan y caducan a las 24 h
///   (store-and-forward: si el contacto aparece mañana, recibe el mensaje).
/// - Tramas de terceros: se guardan las últimas para reenviarlas cuando
///   aparezca un nodo nuevo, en lugar de inundar la radio todo el tiempo.
class Outbox {
  Outbox({
    this.maxMessages = 200,
    this.maxRelay = 64,
    this.maxChannel = 20,
    this.ttl = const Duration(hours: 24),
  });

  final int maxMessages;
  final int maxRelay;

  /// Tope aparte para el canal abierto. Sus avisos no tienen ACK, así que
  /// nunca “se confirman” y se quedan hasta caducar: si compartieran la cola
  /// con los mensajes privados, una tarde de estados rápidos acabaría
  /// expulsando mensajes reales sin entregar.
  final int maxChannel;

  final Duration ttl;

  /// Espera base antes de reintentar un mensaje propio. Se duplica con cada
  /// intento fallido (30 s → 60 s → 2 min → 4 min): insistir cada 20 s con la
  /// cola llena inundaba la radio y gastaba batería sin ganar entregas.
  static const Duration retryBase = Duration(seconds: 30);

  final List<OutboxEntry> _own = <OutboxEntry>[];
  final List<OutboxEntry> _channel = <OutboxEntry>[];
  final List<OutboxEntry> _relay = <OutboxEntry>[];

  /// Lo que este nodo envió y aún puede reintentar: privados primero.
  List<OutboxEntry> get ownPending =>
      List.unmodifiable(<OutboxEntry>[..._own, ..._channel]);
  List<MeshFrame> get relayFrames =>
      List.unmodifiable(_relay.map((e) => e.frame));

  void enqueueOwn(MeshFrame frame) {
    _own.removeWhere((e) => e.key == frame.dedupKey);
    _own.add(OutboxEntry(frame: frame, queuedAt: DateTime.now()));
    _trim(_own, maxMessages);
  }

  /// Aviso del canal abierto (estado o SOS): cola propia, sin ACK.
  void enqueueChannel(MeshFrame frame) {
    _channel.removeWhere((e) => e.key == frame.dedupKey);
    _channel.add(OutboxEntry(frame: frame, queuedAt: DateTime.now()));
    _trim(_channel, maxChannel);
  }

  void enqueueRelay(MeshFrame frame) {
    if (_relay.any((e) => e.key == frame.dedupKey)) return;
    _relay.add(OutboxEntry(frame: frame, queuedAt: DateTime.now()));
    _trim(_relay, maxRelay);
  }

  void markAttempt(String key, {DateTime? at}) {
    final now = at ?? DateTime.now();
    for (final entry in <OutboxEntry>[..._own, ..._channel]) {
      if (entry.key == key) {
        entry.attempts += 1;
        entry.lastAttempt = now;
      }
    }
  }

  void markSent(String key) {
    for (final entry in _own) {
      if (entry.key == key) entry.lastAttempt = DateTime.now();
    }
  }

  /// ¿Toca reintentar esta entrada? Respeta el backoff exponencial según los
  /// intentos ya hechos, para no saturar el aire.
  bool isDue(OutboxEntry entry, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final last = entry.lastAttempt ?? entry.queuedAt;
    final factor = 1 << entry.attempts.clamp(0, 3);
    return at.difference(last) >= retryBase * factor;
  }

  List<OutboxEntry> dueForRetry({DateTime? now}) {
    final at = now ?? DateTime.now();
    return <OutboxEntry>[
      ..._own,
      ..._channel,
    ].where((e) => isDue(e, now: at)).toList();
  }

  void remove(String key) {
    _own.removeWhere((e) => e.key == key);
    _channel.removeWhere((e) => e.key == key);
    _relay.removeWhere((e) => e.key == key);
  }

  /// Elimina lo caducado. Devuelve las claves de los mensajes propios expirados
  /// para que la capa superior los marque como fallidos.
  List<String> pruneExpired({DateTime? now}) {
    final at = now ?? DateTime.now();
    final expired = <String>[];
    bool prune(List<OutboxEntry> list) {
      var removed = false;
      list.removeWhere((e) {
        final isExpired = at.difference(e.queuedAt) > ttl;
        if (isExpired) {
          expired.add(e.key);
          removed = true;
        }
        return isExpired;
      });
      return removed;
    }

    prune(_own);
    prune(_channel);
    _relay.removeWhere((e) => at.difference(e.queuedAt) > ttl);
    return expired;
  }

  int get length => _own.length + _channel.length + _relay.length;

  void _trim(List<OutboxEntry> list, int max) {
    while (list.length > max) {
      list.removeAt(0);
    }
  }

  /// También se guardan las tramas acarreadas: si el teléfono se apaga (o se
  /// queda sin batería en un apagón), al volver sigue llevando lo que recogió.
  List<Map<String, dynamic>> encode() => [
    ..._own.map(_encodeEntry),
    ..._channel.map((e) => _encodeEntry(e)..['c'] = true),
    ..._relay.map((e) => _encodeEntry(e)..['r'] = true),
  ];

  static Map<String, dynamic> _encodeEntry(OutboxEntry entry) => {
    'q': entry.queuedAt.millisecondsSinceEpoch,
    'b': base64Encode(entry.frame.encode()),
  };

  /// Recupera lo pendiente conservando **cuándo** se encoló: si se reiniciara
  /// la fecha en cada arranque, un mensaje de hace una semana se reintentaría
  /// para siempre en lugar de caducar a las 24 h.
  void restore(List<Map<String, dynamic>> json, {DateTime? now}) {
    final at = now ?? DateTime.now();
    for (final item in json) {
      try {
        final frame = MeshFrame.decode(base64Decode(item['b'] as String));
        final queuedAt = DateTime.fromMillisecondsSinceEpoch(
          (item['q'] as num).toInt(),
        );
        if (at.difference(queuedAt) > ttl) continue;
        final entry = OutboxEntry(frame: frame, queuedAt: queuedAt);
        if (item['r'] == true) {
          _relay.removeWhere((e) => e.key == entry.key);
          _relay.add(entry);
        } else if (item['c'] == true) {
          _channel.removeWhere((e) => e.key == entry.key);
          _channel.add(entry);
        } else {
          _own.removeWhere((e) => e.key == entry.key);
          _own.add(entry);
        }
      } catch (error) {
        debugPrint('Outbox: entrada corrupta ignorada ($error)');
      }
    }
    _trim(_own, maxMessages);
    _trim(_channel, maxChannel);
    _trim(_relay, maxRelay);
  }
}
