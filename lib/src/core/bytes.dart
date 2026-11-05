import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

final Random _random = Random.secure();

/// Bytes aleatorios criptográficamente seguros.
Uint8List randomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (clean.length.isOdd) {
    throw const FormatException('Hex impar');
  }
  return Uint8List.fromList(List<int>.generate(
    clean.length ~/ 2,
    (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
  ));
}

Uint8List concatBytes(List<List<int>> parts) {
  final total = parts.fold<int>(0, (sum, p) => sum + p.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}

/// Compara dos listas de bytes de forma simétrica (para derivar la misma clave
/// en ambos extremos sin importar el orden emisor/receptor).
int compareBytes(List<int> a, List<int> b) {
  final len = min(a.length, b.length);
  for (var i = 0; i < len; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

void writeUint16(Uint8List target, int offset, int value) {
  target[offset] = (value >> 8) & 0xff;
  target[offset + 1] = value & 0xff;
}

void writeUint32(Uint8List target, int offset, int value) {
  target[offset] = (value >> 24) & 0xff;
  target[offset + 1] = (value >> 16) & 0xff;
  target[offset + 2] = (value >> 8) & 0xff;
  target[offset + 3] = value & 0xff;
}

void writeUint64(Uint8List target, int offset, int value) {
  writeUint32(target, offset, (value >> 32) & 0xffffffff);
  writeUint32(target, offset + 4, value & 0xffffffff);
}

int readUint16(Uint8List source, int offset) =>
    (source[offset] << 8) | source[offset + 1];

int readUint32(Uint8List source, int offset) =>
    (source[offset] << 24) |
    (source[offset + 1] << 16) |
    (source[offset + 2] << 8) |
    source[offset + 3];

int readUint64(Uint8List source, int offset) =>
    (readUint32(source, offset) << 32) | readUint32(source, offset + 4);

/// Identificador corto y legible de un nodo (para mostrar en la UI).
String shortId(String nodeId) => nodeId.length <= 8 ? nodeId : nodeId.substring(0, 8);

/// Recorta un texto a [maxBytes] en UTF-8 sin partir un carácter.
///
/// Se usa bytes y no caracteres porque un emoji ocupa 4: limitar por longitud
/// de texto dejaría pasar mensajes que no caben en las tramas de la malla.
String clampUtf8Bytes(String text, int maxBytes) {
  final encoded = utf8.encode(text);
  if (encoded.length <= maxBytes) return text;
  var end = maxBytes;
  while (end > 0 && (encoded[end] & 0xC0) == 0x80) {
    end--;
  }
  return utf8.decode(encoded.sublist(0, end), allowMalformed: true);
}
