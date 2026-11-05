import 'dart:typed_data';

/// Paquete recibido por un enlace concreto.
class InboundPacket {
  const InboundPacket(this.linkId, this.bytes);
  final String linkId;
  final Uint8List bytes;
}

/// Cambio de estado de un enlace (conexión BLE establecida o perdida).
class LinkEvent {
  const LinkEvent({
    required this.linkId,
    required this.connected,
    this.rssi,
  });
  final String linkId;
  final bool connected;
  final int? rssi;
}

/// Contrato de radio. Permite tener BLE real, modo demo o futuro LoRa
/// sin tocar la lógica de la malla.
abstract class MeshTransport {
  Stream<InboundPacket> get inbound;
  Stream<LinkEvent> get linkEvents;

  /// Enlaces activos en este momento.
  int get connectedLinks;

  /// False si la radio no está disponible (sin Bluetooth, permiso denegado...).
  bool get available;

  String get label;

  Future<void> start();
  Future<void> stop();

  /// Envía una trama ya codificada.
  /// [onlyLink] limita el envío a un enlace; [exceptLink] lo excluye.
  Future<void> send(
    Uint8List frame, {
    String? onlyLink,
    String? exceptLink,
  });

  /// El planificador de energía enciende y apaga el escaneo (lo caro).
  /// El advertising se mantiene siempre: cuesta ~20 veces menos que escanear.
  void setDiscoveryEnabled(bool enabled);
}
