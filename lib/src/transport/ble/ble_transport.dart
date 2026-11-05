import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../../core/identity.dart';
import '../transport.dart';
import 'fragmentation.dart';

/// Radio real: cada teléfono es periférico (GATT server + advertising) y
/// central (escaneo + conexión) a la vez. Así el mensaje salta de teléfono en
/// teléfono sin internet ni punto de acceso.
///
/// Consumo: el advertising queda siempre encendido porque cuesta ~20 veces
/// menos que escanear; el escaneo lo abre y cierra [RadioScheduler].
class BleMeshTransport implements MeshTransport {
  BleMeshTransport({required this.identity, this.maxLinks = 2});

  final NodeIdentity identity;
  final int maxLinks;

  static final UUID _serviceUuid =
      UUID.fromString('c0de51ed-0001-4a11-9e11-0f0f0f0f0f01');
  static final UUID _characteristicUuid =
      UUID.fromString('c0de51ed-0002-4a11-9e11-0f0f0f0f0f02');

  final CentralManager _central = CentralManager();
  final PeripheralManager _peripheral = PeripheralManager();

  final StreamController<InboundPacket> _inbound =
      StreamController<InboundPacket>.broadcast();
  final StreamController<LinkEvent> _linkEvents =
      StreamController<LinkEvent>.broadcast();

  final Map<String, _BleLink> _links = <String, _BleLink>{};
  final Set<String> _connecting = <String>{};
  final FrameReassembler _reassembler = FrameReassembler();

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  GATTService? _service;
  bool _running = false;
  bool _discoveryWanted = true;
  bool _advertising = false;

  String? lastError;

  @override
  Stream<InboundPacket> get inbound => _inbound.stream;

  @override
  Stream<LinkEvent> get linkEvents => _linkEvents.stream;

  @override
  int get connectedLinks => _links.length;

  @override
  bool get available =>
      _running && _central.state == BluetoothLowEnergyState.poweredOn;

  @override
  String get label => 'Bluetooth LE (malla entre teléfonos)';

  @override
  Future<void> start() async {
    if (_running) return;
    try {
      await _central.authorize();
    } catch (error) {
      debugPrint('BLE: authorize() falló ($error)');
    }
    // En algunos equipos el estado tarda un instante en reportarse.
    if (_central.state == BluetoothLowEnergyState.unknown) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (_central.state != BluetoothLowEnergyState.poweredOn) {
      throw StateError(
        _central.state == BluetoothLowEnergyState.poweredOff
            ? 'Bluetooth apagado'
            : 'Bluetooth sin permisos o no disponible',
      );
    }

    _subscriptions
      ..add(_central.discovered.listen(_onDiscovered))
      ..add(_central.connectionStateChanged.listen(_onPeripheralLinkChanged))
      ..add(_central.characteristicNotified.listen(_onNotified))
      ..add(_peripheral.characteristicWriteRequested.listen(_onWriteRequested))
      ..add(_peripheral.characteristicNotifyStateChanged
          .listen(_onNotifyStateChanged))
      ..add(_peripheral.connectionStateChanged.listen(_onCentralLinkChanged));

    _service = GATTService(
      uuid: _serviceUuid,
      isPrimary: true,
      includedServices: const <GATTService>[],
      characteristics: [
        GATTCharacteristic.mutable(
          uuid: _characteristicUuid,
          properties: const [
            GATTCharacteristicProperty.write,
            GATTCharacteristicProperty.writeWithoutResponse,
            GATTCharacteristicProperty.notify,
          ],
          permissions: const [GATTCharacteristicPermission.write],
          descriptors: const <GATTDescriptor>[],
        ),
      ],
    );

    try {
      await _peripheral.addService(_service!);
      await _startAdvertising();
    } catch (error) {
      // Algunos chips no soportan rol periférico; seguimos como central.
      lastError = 'Sin rol periférico: $error';
      debugPrint('BLE: $lastError');
    }

    _running = true;
    if (_discoveryWanted) await _startDiscovery();
  }

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    // Sin esto, el siguiente start() creía que ya estaba anunciándose y no
    // volvía a llamar a startAdvertising: el teléfono quedaba invisible tras
    // reiniciar la radio o cambiar de modo demo a BLE.
    _advertising = false;
    _connecting.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    try {
      await _central.stopDiscovery();
    } catch (_) {}
    try {
      await _peripheral.stopAdvertising();
    } catch (_) {}
    for (final link in _links.values.toList()) {
      await _disconnect(link);
    }
    _links.clear();
    try {
      await _peripheral.removeAllServices();
    } catch (_) {}
    _reassembler.clear();
  }

  @override
  Future<void> send(
    Uint8List frame, {
    String? onlyLink,
    String? exceptLink,
  }) async {
    if (!_running) return;
    final targets = onlyLink != null
        ? [if (_links[onlyLink] != null) _links[onlyLink]!]
        : _links.values.where((link) => link.id != exceptLink).toList();
    for (final link in targets) {
      try {
        final chunks = FrameChunker.split(frame, link.maxWrite);
        for (final chunk in chunks) {
          await _write(link, chunk);
        }
      } catch (error) {
        debugPrint('BLE: error enviando a ${link.id} ($error)');
      }
    }
  }

  @override
  void setDiscoveryEnabled(bool enabled) {
    _discoveryWanted = enabled;
    if (!_running) return;
    if (enabled) {
      if (_links.length < maxLinks) unawaited(_startDiscovery());
    } else {
      unawaited(_stopDiscovery());
    }
  }

  Future<void> _startAdvertising() async {
    if (_advertising) return;
    // El paquete de advertising solo puede pesar 31 bytes y un UUID de 128
    // bits ya ocupa 18: con nombre y serviceData encima, Android responde
    // ADVERTISE_FAILED_DATA_TOO_LARGE y el teléfono deja de ser visible.
    // Con solo el UUID (21 bytes) entra siempre; el nombre y el id viajan en
    // el anuncio de presencia, una vez conectados.
    final advertisement = Advertisement(serviceUUIDs: [_serviceUuid]);
    await _peripheral.startAdvertising(advertisement);
    _advertising = true;
  }

  Future<void> _startDiscovery() async {
    if (!_running) return;
    if (_links.length >= maxLinks) return;
    try {
      await _central.startDiscovery(serviceUUIDs: [_serviceUuid]);
    } catch (error) {
      lastError = 'Escaneo falló: $error';
      debugPrint('BLE: $lastError');
    }
  }

  Future<void> _stopDiscovery() async {
    try {
      await _central.stopDiscovery();
    } catch (_) {}
  }

  void _onDiscovered(DiscoveredEventArgs args) {
    if (!_running) return;
    if (_links.length >= maxLinks) {
      unawaited(_stopDiscovery());
      return;
    }
    final id = args.peripheral.uuid.toString();
    if (_links.containsKey(id) || _connecting.contains(id)) return;
    unawaited(_connect(args.peripheral, args.rssi));
  }

  Future<void> _connect(Peripheral peripheral, int rssi) async {
    final id = peripheral.uuid.toString();
    _connecting.add(id);
    try {
      // Android puede dejar el connect() colgado para siempre en algunos
      // chips; sin timeout, ese nodo quedaría bloqueado en _connecting y no
      // se volvería a intentar.
      await _central.connect(peripheral).timeout(const Duration(seconds: 20));
      try {
        // Android 14+ ignora peticiones posteriores: pedimos una sola vez.
        await _central.requestMTU(peripheral, mtu: 517);
      } catch (error) {
        debugPrint('BLE: MTU no negociado ($error)');
      }
      final services = await _central.discoverGATT(peripheral);
      GATTService? service;
      for (final candidate in services) {
        if (candidate.uuid == _serviceUuid) {
          service = candidate;
          break;
        }
      }
      if (service == null) {
        throw StateError('Servicio SinRed no encontrado');
      }
      GATTCharacteristic? characteristic;
      for (final candidate in service.characteristics) {
        if (candidate.uuid == _characteristicUuid) {
          characteristic = candidate;
          break;
        }
      }
      if (characteristic == null) {
        throw StateError('Característica SinRed no encontrada');
      }
      await _central.setCharacteristicNotifyState(
        peripheral,
        characteristic,
        state: true,
      );
      var maxWrite = 180;
      try {
        maxWrite = await _central.getMaximumWriteLength(
          peripheral,
          type: GATTCharacteristicWriteType.withoutResponse,
        );
      } catch (_) {}
      if (!_running) {
        // La radio se paró (reinicio, cambio a demo) mientras conectábamos:
        // registrar el enlace dejaría un vínculo fantasma en la UI.
        try {
          await _central.disconnect(peripheral);
        } catch (_) {}
        return;
      }
      _links[id] = _BleLink(
        id: id,
        peripheral: peripheral,
        characteristic: characteristic,
        maxWrite: maxWrite,
        isCentral: true,
      );
      _linkEvents.add(LinkEvent(linkId: id, connected: true, rssi: rssi));
      if (_links.length >= maxLinks) await _stopDiscovery();
    } catch (error) {
      lastError = 'No se pudo conectar: $error';
      debugPrint('BLE: $lastError');
      try {
        await _central.disconnect(peripheral);
      } catch (_) {}
    } finally {
      _connecting.remove(id);
    }
  }

  void _onNotifyStateChanged(GATTCharacteristicNotifyStateChangedEventArgs args) {
    final id = args.central.uuid.toString();
    if (!args.state) {
      unawaited(_dropLink(id));
      return;
    }
    if (_links.containsKey(id)) return;
    unawaited(() async {
      var maxWrite = 180;
      try {
        maxWrite = await _peripheral.getMaximumNotifyLength(args.central);
      } catch (_) {}
      if (!_running) return;
      _links[id] = _BleLink(
        id: id,
        central: args.central,
        characteristic: args.characteristic,
        maxWrite: maxWrite,
        isCentral: false,
      );
      _linkEvents.add(LinkEvent(linkId: id, connected: true));
    }());
  }

  Future<void> _onWriteRequested(
    GATTCharacteristicWriteRequestedEventArgs args,
  ) async {
    try {
      await _peripheral.respondWriteRequest(args.request);
    } catch (error) {
      debugPrint('BLE: respondWriteRequest ($error)');
    }
    final id = args.central.uuid.toString();
    final frame = _reassembler.add(id, args.request.value);
    if (frame != null) {
      _inbound.add(InboundPacket(id, frame));
    }
  }

  void _onNotified(GATTCharacteristicNotifiedEventArgs args) {
    final id = args.peripheral.uuid.toString();
    final frame = _reassembler.add(id, args.value);
    if (frame != null) {
      _inbound.add(InboundPacket(id, frame));
    }
  }

  void _onPeripheralLinkChanged(PeripheralConnectionStateChangedEventArgs args) {
    if (args.state == ConnectionState.disconnected) {
      final id = args.peripheral.uuid.toString();
      unawaited(_dropLink(id));
      // Workaround conocido: algunos controladores dejan de anunciarse tras
      // una desconexión.
      unawaited(_rearmAdvertising());
      if (_discoveryWanted) unawaited(_startDiscovery());
    }
  }

  void _onCentralLinkChanged(CentralConnectionStateChangedEventArgs args) {
    if (args.state == ConnectionState.disconnected) {
      unawaited(_dropLink(args.central.uuid.toString()));
    }
  }

  Future<void> _rearmAdvertising() async {
    if (!_running) return;
    try {
      await _peripheral.stopAdvertising();
    } catch (_) {}
    _advertising = false;
    try {
      await _startAdvertising();
    } catch (error) {
      debugPrint('BLE: no se pudo re-armar advertising ($error)');
    }
  }

  Future<void> _dropLink(String id) async {
    final link = _links.remove(id);
    if (link != null) {
      _linkEvents.add(LinkEvent(linkId: id, connected: false));
    }
  }

  Future<void> _write(_BleLink link, Uint8List chunk) async {
    if (link.isCentral) {
      await _central.writeCharacteristic(
        link.peripheral!,
        link.characteristic,
        value: chunk,
        type: GATTCharacteristicWriteType.withoutResponse,
      );
    } else {
      await _peripheral.notifyCharacteristic(
        link.central!,
        link.characteristic,
        value: chunk,
      );
    }
  }

  Future<void> _disconnect(_BleLink link) async {
    try {
      if (link.isCentral) {
        await _central.disconnect(link.peripheral!);
      } else {
        await _peripheral.disconnect(link.central!);
      }
    } catch (error) {
      debugPrint('BLE: desconexión ($error)');
    }
  }
}

class _BleLink {
  _BleLink({
    required this.id,
    required this.characteristic,
    required this.maxWrite,
    required this.isCentral,
    this.peripheral,
    this.central,
  });

  final String id;
  final GATTCharacteristic characteristic;
  final int maxWrite;
  final bool isCentral;
  final Peripheral? peripheral;
  final Central? central;
}
