import 'dart:async';
import 'dart:typed_data';

import 'package:chasqui/src/transport/transport.dart';

/// Radio controlable desde el test: no hay Bluetooth, pero sí los mismos
/// eventos que produce la radio real.
class FakeTransport implements MeshTransport {
  final StreamController<InboundPacket> _inbound =
      StreamController<InboundPacket>.broadcast();
  final StreamController<LinkEvent> _linkEvents =
      StreamController<LinkEvent>.broadcast();

  int _linkCount = 0;
  final List<Uint8List> sent = <Uint8List>[];

  @override
  Stream<InboundPacket> get inbound => _inbound.stream;

  @override
  Stream<LinkEvent> get linkEvents => _linkEvents.stream;

  @override
  int get connectedLinks => _linkCount;

  @override
  bool get available => true;

  @override
  String get label => 'radio de prueba';

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => _linkCount = 0;

  @override
  Future<void> send(
    Uint8List frame, {
    String? onlyLink,
    String? exceptLink,
  }) async {
    sent.add(frame);
  }

  @override
  void setDiscoveryEnabled(bool enabled) {}

  /// Lo que la malla pidió: null = no soltar enlaces.
  Duration? idleLinkTimeout;

  @override
  void setIdleLinkTimeout(Duration? timeout) => idleLinkTimeout = timeout;

  void connect(String linkId, {int? rssi = -55}) {
    _linkCount += 1;
    _linkEvents.add(LinkEvent(linkId: linkId, connected: true, rssi: rssi));
  }

  void incoming(String linkId, Uint8List bytes) {
    _inbound.add(InboundPacket(linkId, bytes));
  }

  Future<void> close() async {
    await _inbound.close();
    await _linkEvents.close();
  }
}
