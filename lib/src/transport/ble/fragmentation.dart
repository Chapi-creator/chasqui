import 'dart:typed_data';

import '../../core/bytes.dart';

/// Trocea tramas de malla en paquetes que quepan en una escritura BLE.
///
/// Cabecera de trozo (7 bytes):
/// `0x02 | tag(4) | índice(1) | total(1) | datos`
class FrameChunker {
  static const int marker = 0x02;
  static const int overhead = 7;

  static List<Uint8List> split(Uint8List frame, int maxWriteLength) {
    final usable = (maxWriteLength - overhead).clamp(8, 4096);
    final total = (frame.length / usable).ceil();
    final tag = randomBytes(4);
    final chunks = <Uint8List>[];
    for (var i = 0; i < total; i++) {
      final start = i * usable;
      final end = (start + usable).clamp(0, frame.length);
      final payload = frame.sublist(start, end);
      final chunk = Uint8List(overhead + payload.length);
      chunk[0] = marker;
      chunk.setRange(1, 5, tag);
      chunk[5] = i;
      chunk[6] = total;
      chunk.setRange(overhead, chunk.length, payload);
      chunks.add(chunk);
    }
    return chunks;
  }
}

class _Pending {
  _Pending(this.total, this.createdAt)
    : parts = List<Uint8List?>.filled(total, null);

  final int total;
  final DateTime createdAt;
  final List<Uint8List?> parts;
  int received = 0;

  Uint8List? assemble() {
    if (received != total) return null;
    var length = 0;
    for (final part in parts) {
      length += part!.length;
    }
    final out = Uint8List(length);
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part!.length, part);
      offset += part.length;
    }
    return out;
  }
}

/// Reensambla los trozos que llegan por un enlace.
class FrameReassembler {
  FrameReassembler({
    this.timeout = const Duration(seconds: 15),
    this.maxPending = 64,
  });

  final Duration timeout;

  /// Tope de reensamblados a la vez. Cada tag nuevo crea una entrada; sin tope,
  /// un enlace que manda trozos con tags distintos (o ruido) podía llenar la
  /// memoria del teléfono en segundos.
  final int maxPending;
  final Map<String, _Pending> _pending = <String, _Pending>{};

  /// Devuelve la trama completa o null si aún faltan trozos.
  Uint8List? add(String linkId, Uint8List chunk) {
    if (chunk.isEmpty || chunk[0] != FrameChunker.marker || chunk.length < 8) {
      return chunk; // trama sin trocear
    }
    final tag = toHex(chunk.sublist(1, 5));
    final index = chunk[5];
    final total = chunk[6];
    if (total == 0 || index >= total) return null;

    final key = '$linkId:$tag';
    if (!_pending.containsKey(key) && _pending.length >= maxPending) {
      _prune();
      if (_pending.length >= maxPending) _evictOldest();
    }
    final entry = _pending.putIfAbsent(
      key,
      () => _Pending(total, DateTime.now()),
    );
    if (entry.total != total || entry.parts[index] != null) {
      if (entry.total != total) {
        _pending.remove(key);
        return null;
      }
      return null;
    }
    entry.parts[index] = chunk.sublist(FrameChunker.overhead);
    entry.received += 1;

    final assembled = entry.assemble();
    if (assembled != null) {
      _pending.remove(key);
      return assembled;
    }
    _prune();
    return null;
  }

  /// Saca el reensamblado más viejo: lo que llegue después de él tiene menos
  /// chance de completarse que lo recién empezado.
  void _evictOldest() {
    String? oldestKey;
    DateTime? oldest;
    _pending.forEach((key, entry) {
      if (oldest == null || entry.createdAt.isBefore(oldest!)) {
        oldest = entry.createdAt;
        oldestKey = key;
      }
    });
    if (oldestKey != null) _pending.remove(oldestKey);
  }

  void _prune() {
    final now = DateTime.now();
    _pending.removeWhere(
      (_, entry) => now.difference(entry.createdAt) > timeout,
    );
  }

  void clear() => _pending.clear();
}
