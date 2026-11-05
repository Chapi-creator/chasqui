import 'dart:math' as math;
import 'dart:typed_data';

import 'bytes.dart';

/// Punto geográfico compartido entre dos teléfonos.
///
/// Viaja cifrado y solo a contactos; nunca se envía a un servidor porque no
/// hay servidor. La precisión ([accuracy]) se muestra siempre: un dato de GPS
/// con ±500 m no sirve para decir que alguien está "a 20 m".
class GeoPoint {
  const GeoPoint({
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.at,
  });

  /// Latitud en grados decimales (-90 a 90).
  final double lat;

  /// Longitud en grados decimales (-180 a 180).
  final double lon;

  /// Radio de error estimado, en metros.
  final double accuracy;

  /// Cuándo se tomó la posición.
  final DateTime at;

  /// Bytes del payload de una trama de ubicación: lat, lon, precisión y hora.
  ///
  /// 18 bytes: latitud y longitud escaladas a 1e7 (int32, suficiente para
  /// ±180°), precisión en metros (uint16, tope 65 km) y timestamp en ms.
  static const int payloadLength = 18;

  bool get isValid =>
      lat.isFinite &&
      lon.isFinite &&
      lat.abs() <= 90 &&
      lon.abs() <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0;

  Uint8List encodePayload() {
    final out = Uint8List(payloadLength);
    final data = ByteData.sublistView(out);
    data.setInt32(0, (lat * 1e7).round(), Endian.big);
    data.setInt32(4, (lon * 1e7).round(), Endian.big);
    data.setUint16(8, accuracy.round().clamp(0, 65535), Endian.big);
    writeUint64(out, 10, at.millisecondsSinceEpoch);
    return out;
  }

  static GeoPoint? decodePayload(List<int> bytes) {
    if (bytes.length < payloadLength) return null;
    final raw = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final data = ByteData.sublistView(raw, 0, payloadLength);
    final point = GeoPoint(
      lat: data.getInt32(0, Endian.big) / 1e7,
      lon: data.getInt32(4, Endian.big) / 1e7,
      accuracy: data.getUint16(8, Endian.big).toDouble(),
      at: DateTime.fromMillisecondsSinceEpoch(readUint64(raw, 10)),
    );
    return point.isValid ? point : null;
  }

  Map<String, Object?> toMap() => {
        'lat': lat,
        'lon': lon,
        'acc': accuracy,
        'ts': at.millisecondsSinceEpoch,
      };

  /// Lectura defensiva de lo que manda la capa nativa.
  static GeoPoint? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final lat = (raw['lat'] as num?)?.toDouble();
    final lon = (raw['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final point = GeoPoint(
      lat: lat,
      lon: lon,
      accuracy: (raw['acc'] as num?)?.toDouble() ?? 0,
      at: DateTime.fromMillisecondsSinceEpoch(
        (raw['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return point.isValid ? point : null;
  }

  @override
  String toString() =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)} ±${accuracy.round()} m';
}

/// Siglas de las 8 direcciones, en español y con una o dos letras.
///
/// El usuario pidió letras sueltas ("S" para el sur); se añaden las diagonales
/// (SE, SO…) porque con solo cuatro rumbos el error llega a 45°.
const List<String> cardinalLabels = <String>[
  'N',
  'NE',
  'E',
  'SE',
  'S',
  'SO',
  'O',
  'NO',
];

/// Distancia en metros entre dos puntos (haversine, esfera de 6371 km).
double distanceMeters(GeoPoint a, GeoPoint b) {
  const earthRadius = 6371000.0;
  final dLat = _radians(b.lat - a.lat);
  final dLon = _radians(b.lon - a.lon);
  final lat1 = _radians(a.lat);
  final lat2 = _radians(b.lat);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
}

/// Rumbo inicial de [from] hacia [to], en grados (0 = norte, 90 = este).
double bearingDegrees(GeoPoint from, GeoPoint to) {
  final lat1 = _radians(from.lat);
  final lat2 = _radians(to.lat);
  final dLon = _radians(to.lon - from.lon);
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final degrees = math.atan2(y, x) * 180 / math.pi;
  return (degrees + 360) % 360;
}

/// Sigla de la dirección de un rumbo: N, NE, E, SE, S, SO, O, NO.
String cardinalShort(double bearingDegrees) {
  final normalized = ((bearingDegrees % 360) + 360) % 360;
  final index = ((normalized + 22.5) ~/ 45) % 8;
  return cardinalLabels[index];
}

/// Metros en formato corto y sin falsa precisión.
String formatDistance(double meters) {
  if (!meters.isFinite) return '?';
  if (meters < 10) return '${meters.round()} m';
  if (meters < 100) return '${(meters / 5).round() * 5} m';
  if (meters < 1000) return '${(meters / 10).round() * 10} m';
  final km = meters / 1000;
  final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${text.replaceAll('.', ',')} km';
}

/// Minutos andando a 1,3 m/s, con un mínimo de uno.
int walkingMinutes(double meters) {
  if (!meters.isFinite || meters <= 0) return 1;
  return (meters / 1.3 / 60).round().clamp(1, 999);
}

/// Texto del "asistente" local que interpreta unas coordenadas recibidas.
///
/// No hay IA ni internet: es aritmética de rumbo y distancia, explicada en
/// castellano para que el dato se entienda sin abrir otra app.
String describeProximity({
  GeoPoint? mine,
  required GeoPoint theirs,
  required String name,
  DateTime? now,
}) {
  final age = (now ?? DateTime.now()).difference(theirs.at);
  final freshness =
      age.inMinutes >= 1 ? ' Dato de hace ${_humanAge(age)}.' : '';
  if (mine == null) {
    return '📍 $name compartió su ubicación.'
        '$freshness Activa «Compartir mi ubicación» en Ajustes para calcular '
        'la distancia y la dirección.';
  }
  final distance = distanceMeters(mine, theirs);
  final bearing = bearingDegrees(mine, theirs);
  final direction = cardinalShort(bearing);
  return '📍 $name está a ≈${formatDistance(distance)} al $direction '
      '(rumbo ${bearing.round()}°). A pie: ~${walkingMinutes(distance)} min.'
      '$freshness Precisión ±${theirs.accuracy.round()} m.';
}

/// Estimación de distancia por intensidad de señal, solo como respaldo.
///
/// Con una antena no se puede saber de qué lado está la otra persona, así que
/// esto nunca produce una dirección: únicamente un rango muy grueso.
double rssiDistanceMeters(int rssi) {
  // Potencia esperada a 1 m y exponente de pérdida en interiores, valores
  // habituales para BLE. Es una aproximación: paredes y cuerpos la alteran.
  const txPowerAtOneMeter = -59.0;
  const pathLossExponent = 2.0;
  return math.pow(10, (txPowerAtOneMeter - rssi) / (10 * pathLossExponent))
      .toDouble();
}

/// Rango legible a partir del RSSI, sin decimales que aparenten precisión.
String? rssiRangeLabel(int? rssi) {
  if (rssi == null || rssi == 0) return null;
  final meters = rssiDistanceMeters(rssi);
  if (meters < 6) return 'muy cerca (≈5 m)';
  if (meters < 15) return '≈10 m';
  if (meters < 35) return '≈25 m';
  if (meters < 70) return '≈50 m';
  return 'a más de 50 m';
}

String _humanAge(Duration age) {
  if (age.inMinutes < 60) return '${age.inMinutes} min';
  if (age.inHours < 24) return '${age.inHours} h';
  return '${age.inDays} días';
}

double _radians(double degrees) => degrees * math.pi / 180;
