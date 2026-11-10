import 'package:flutter_test/flutter_test.dart';
import 'package:chasqui/src/core/geo.dart';
import 'package:chasqui/src/core/models.dart';

GeoPoint point(double lat, double lon, {double accuracy = 5}) => GeoPoint(
      lat: lat,
      lon: lon,
      accuracy: accuracy,
      at: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

void main() {
  group('distancia y rumbo', () {
    test('un milésimo de latitud son ~111 m', () {
      final meters = distanceMeters(point(0, 0), point(0.001, 0));
      expect(meters, closeTo(111.2, 0.5));
    });

    test('el rumbo apunta a los cuatro puntos cardinales', () {
      final origin = point(0, 0);
      expect(bearingDegrees(origin, point(1, 0)), closeTo(0, 0.01));
      expect(bearingDegrees(origin, point(0, 1)), closeTo(90, 0.01));
      expect(bearingDegrees(origin, point(-1, 0)), closeTo(180, 0.01));
      expect(bearingDegrees(origin, point(0, -1)), closeTo(270, 0.01));
    });

    test('las siglas cubren las 8 direcciones y cierran el círculo', () {
      expect(cardinalShort(0), 'N');
      expect(cardinalShort(20), 'N');
      expect(cardinalShort(45), 'NE');
      expect(cardinalShort(90), 'E');
      expect(cardinalShort(135), 'SE');
      expect(cardinalShort(180), 'S');
      expect(cardinalShort(225), 'SO');
      expect(cardinalShort(270), 'O');
      expect(cardinalShort(315), 'NO');
      expect(cardinalShort(350), 'N');
      // Rumbos fuera de rango o negativos no rompen la sigla.
      expect(cardinalShort(405), 'NE', reason: '405° = 45°');
      expect(cardinalShort(-90), 'O');
    });

    test('la distancia se redondea sin falsa precisión', () {
      expect(formatDistance(4.4), '4 m');
      expect(formatDistance(47), '45 m');
      expect(formatDistance(123), '120 m');
      expect(formatDistance(1240), '1,2 km');
      expect(formatDistance(12345), '12 km');
    });

    test('andando se estima un mínimo de un minuto', () {
      expect(walkingMinutes(5), 1);
      expect(walkingMinutes(780), 10);
    });
  });

  group('payload de ubicación', () {
    test('ida y vuelta conserva coordenadas, precisión y hora', () {
      final original = point(4.60971, -74.08175, accuracy: 12);
      final decoded = GeoPoint.decodePayload(original.encodePayload());

      expect(decoded, isNotNull);
      expect(decoded!.lat, closeTo(4.60971, 1e-6));
      expect(decoded.lon, closeTo(-74.08175, 1e-6));
      expect(decoded.accuracy, 12);
      expect(decoded.at, original.at);
      expect(original.encodePayload().length, GeoPoint.payloadLength);
    });

    test('coordenadas imposibles se rechazan', () {
      expect(
        GeoPoint.decodePayload(GeoPoint(lat: 999, lon: 0, accuracy: 1, at: DateTime.now()).encodePayload()),
        isNull,
      );
      expect(GeoPoint.decodePayload([0, 0, 0]), isNull);
    });
  });

  group('asistente local', () {
    test('traduce coordenadas a distancia y dirección', () {
      final text = describeProximity(
        mine: point(0, 0),
        theirs: point(0, 0.001),
        name: 'Ana',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(text, contains('Ana'));
      expect(text, contains('≈110 m al E'));
      expect(text, contains('A pie: ~1 min'));
      expect(text, contains('Precisión ±5 m'));
    });

    test('sin ubicación propia no inventa una distancia', () {
      final text = describeProximity(
        mine: null,
        theirs: point(0, 0.001),
        name: 'Ana',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      expect(text, contains('Activa «Compartir mi ubicación»'));
      expect(text, isNot(contains('al E')));
    });

    test('avisa si el dato tiene minutos', () {
      final theirs = GeoPoint(
        lat: 0,
        lon: 0.001,
        accuracy: 5,
        at: DateTime.fromMillisecondsSinceEpoch(1700000000000 - 120000),
      );
      final text = describeProximity(
        mine: point(0, 0),
        theirs: theirs,
        name: 'Ana',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(text, contains('Dato de hace 2 min'));
    });
  });

  group('respaldo por señal', () {
    test('el RSSI solo da un rango, nunca una dirección', () {
      expect(rssiRangeLabel(null), isNull);
      expect(rssiRangeLabel(0), isNull);
      expect(rssiRangeLabel(-45), 'muy cerca (≈5 m)');
      expect(rssiRangeLabel(-90), '≈50 m');
      expect(rssiRangeLabel(-100), 'a más de 50 m');
      expect(rssiRangeLabel(-70), isNot(contains('N')));
    });
  });

  group('persistencia del mensaje', () {
    test('el tipo y las coordenadas sobreviven al JSON', () {
      final message = ChatMessage(
        id: 'm1',
        peerId: 'peer',
        outgoing: false,
        text: 'Ubicación compartida',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        kind: MessageKind.location,
        location: point(4.6, -74.08, accuracy: 9),
      );

      final restored = ChatMessage.fromJson(message.toJson());

      expect(restored.kind, MessageKind.location);
      expect(restored.location!.lat, closeTo(4.6, 1e-6));
      expect(restored.location!.accuracy, 9);
    });

    test('un mensaje viejo sin tipo se lee como texto', () {
      final restored = ChatMessage.fromJson({
        'id': 'm2',
        'peerId': 'peer',
        'outgoing': true,
        'text': 'hola',
        'ts': 1700000000000,
        'status': 'sent',
      });

      expect(restored.kind, MessageKind.text);
      expect(restored.location, isNull);
    });
  });
}
