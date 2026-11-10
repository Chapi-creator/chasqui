import 'dart:typed_data';

import 'bytes.dart';

/// Una foto viaja partida en trozos pequeños.
///
/// Por qué no una trama grande: el enlace BLE reensambla tramas de hasta 255
/// trozos, pero una trama de 40 KB ocupa el aire minutos y, si se pierde un
/// solo trozo BLE, se pierde entera. Con trozos de 3 KB, cada uno es una trama
/// independiente con su propia deduplicación y su propio reenvío: lo que llega
/// se guarda y lo que falta se puede volver a pedir en el siguiente encuentro.
///
/// Formato de cada trozo, antes de cifrar:
/// `id de foto (16) | índice (1) | total (1) | datos`
class PhotoPart {
  const PhotoPart({
    required this.pid,
    required this.index,
    required this.total,
    required this.data,
  });

  final Uint8List pid;
  final int index;
  final int total;
  final Uint8List data;

  String get pidHex => toHex(pid);

  bool get isFirst => index == 0;
  bool get isLast => index == total - 1;
}

class PhotoChunker {
  static const int pidLength = 16;
  static const int headerBytes = pidLength + 2;

  /// Tamaño de datos por trozo. Con 3 KB, una foto de 40 KB son 14 tramas.
  static const int chunkBytes = 3000;

  /// Tope de la foto comprimida. Más que esto tarda demasiado de pie junto a
  /// la otra persona y gasta batería de los dos lados.
  static const int maxPhotoBytes = 45 * 1024;

  /// El índice y el total van en un byte cada uno.
  static const int maxChunks = 200;

  static int chunksFor(int byteLength) =>
      (byteLength + chunkBytes - 1) ~/ chunkBytes;

  /// Parte una foto en trozos listos para cifrar y mandar.
  static List<PhotoPart> split(Uint8List pid, List<int> jpeg) {
    if (pid.length != pidLength) {
      throw ArgumentError('El id de foto debe tener $pidLength bytes');
    }
    if (jpeg.isEmpty || jpeg.length > maxPhotoBytes) {
      throw ArgumentError('La foto no entra en el tope de la malla');
    }
    final total = chunksFor(jpeg.length);
    if (total > maxChunks) throw ArgumentError('Demasiados trozos');
    final parts = <PhotoPart>[];
    for (var index = 0; index < total; index++) {
      final start = index * chunkBytes;
      final end = (start + chunkBytes).clamp(0, jpeg.length);
      parts.add(
        PhotoPart(
          pid: pid,
          index: index,
          total: total,
          data: Uint8List.fromList(jpeg.sublist(start, end)),
        ),
      );
    }
    return parts;
  }

  /// Lee un trozo ya descifrado. Devuelve null si no tiene forma válida.
  static PhotoPart? parse(Uint8List raw) {
    if (raw.length <= headerBytes) return null;
    final total = raw[headerBytes - 1];
    final index = raw[headerBytes - 2];
    if (total == 0 || total > maxChunks || index >= total) return null;
    if (raw.length - headerBytes > chunkBytes) return null;
    return PhotoPart(
      pid: Uint8List.fromList(raw.sublist(0, pidLength)),
      index: index,
      total: total,
      data: Uint8List.fromList(raw.sublist(headerBytes)),
    );
  }

  /// Vuelve a armar el trozo (para el emisor y las pruebas).
  static Uint8List encode(PhotoPart part) {
    final out = Uint8List(headerBytes + part.data.length);
    out.setRange(0, pidLength, part.pid);
    out[pidLength] = part.index;
    out[pidLength + 1] = part.total;
    out.setRange(headerBytes, out.length, part.data);
    return out;
  }
}

class _PendingPhoto {
  _PendingPhoto(this.total, this.createdAt)
    : parts = List<Uint8List?>.filled(total, null);

  final int total;
  final DateTime createdAt;
  final List<Uint8List?> parts;
  int received = 0;
  int bytes = 0;

  bool get complete => received == total;

  Uint8List assemble() {
    final out = Uint8List(bytes);
    var offset = 0;
    for (final part in parts) {
      out.setRange(offset, offset + part!.length, part);
      offset += part.length;
    }
    return out;
  }
}

/// Resultado de juntar trozos: una foto completa.
class AssembledPhoto {
  const AssembledPhoto({required this.pidHex, required this.bytes});

  final String pidHex;
  final Uint8List bytes;

  /// Progreso 0–1 de una foto en curso, para poder mostrarlo.
  static double progress(int received, int total) =>
      total == 0 ? 0 : received / total;
}

/// Junta los trozos que llegan de un mismo emisor.
///
/// Los trozos pueden llegar en desorden y por caminos distintos (uno directo,
/// otro por un repetidor). Se guardan por emisor y id de foto, no por enlace:
/// si el enlace se corta y vuelve, la foto sigue armándose.
class PhotoAssembler {
  PhotoAssembler({
    this.timeout = const Duration(minutes: 3),
    this.maxPending = 12,
    this.maxPhotoBytes = PhotoChunker.maxPhotoBytes,
  });

  final Duration timeout;
  final int maxPending;
  final int maxPhotoBytes;

  final Map<String, _PendingPhoto> _pending = <String, _PendingPhoto>{};

  /// Cuántos trozos faltan de una foto en curso (null si no hay ninguna).
  int? missing(String sourceId, String pidHex) {
    final entry = _pending['$sourceId:$pidHex'];
    if (entry == null) return null;
    return entry.total - entry.received;
  }

  /// Agrega un trozo. Devuelve la foto cuando se completa.
  AssembledPhoto? add(String sourceId, PhotoPart part) {
    final key = '$sourceId:${part.pidHex}';
    final existing = _pending[key];
    if (existing != null && existing.total != part.total) {
      // Otro total para el mismo id: o se corrompió, o alguien intenta colar
      // basura. Se descarta lo viejo y empieza de nuevo.
      _pending.remove(key);
    }
    if (!_pending.containsKey(key)) {
      if (_pending.length >= maxPending) {
        _prune();
        if (_pending.length >= maxPending) _evictOldest();
      }
      _pending[key] = _PendingPhoto(part.total, DateTime.now());
    }
    final entry = _pending[key]!;
    if (entry.parts[part.index] != null) return null;
    if (entry.bytes + part.data.length > maxPhotoBytes) {
      _pending.remove(key);
      return null;
    }
    entry.parts[part.index] = part.data;
    entry.received += 1;
    entry.bytes += part.data.length;
    if (!entry.complete) return null;
    _pending.remove(key);
    return AssembledPhoto(pidHex: part.pidHex, bytes: entry.assemble());
  }

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

  int get pendingCount => _pending.length;
}
