import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/board.dart';
import '../core/bytes.dart';
import '../core/channel.dart';
import '../core/contact_code.dart';
import '../core/frame.dart';
import '../core/geo.dart';
import '../core/identity.dart';
import '../core/models.dart';
import '../data/state_store.dart';
import '../power/power_policy.dart';
import '../power/radio_scheduler.dart';
import '../transport/ble/ble_transport.dart';
import '../transport/demo_transport.dart';
import '../transport/transport.dart';
import 'router.dart';

/// Orquestador de la app: radio + malla + contactos + mensajes + persistencia.
///
/// La UI nunca habla con Bluetooth; solo con este objeto.
class MeshNode extends ChangeNotifier {
  MeshNode({
    required this.identity,
    required this.store,
    required MeshTransport transport,
    String displayName = 'Yo',
    RadioMode mode = RadioMode.equilibrado,
    bool monitorBattery = true,
    bool useDemo = false,
    bool shareLocation = false,
    bool showProximity = false,
    bool relayMode = false,
  }) : _transport = transport,
       _displayName = displayName,
       _radioMode = mode,
       _useDemo = useDemo,
       _shareLocation = shareLocation,
       _showProximity = showProximity,
       _relayMode = relayMode {
    _router = MeshRouter(
      identity: identity,
      broadcast: _broadcast,
      onMessage: _handleIncoming,
      onAck: _handleAck,
      onPresence: _handlePresence,
      onLocation: _handleLocation,
      onChannel: _handleChannel,
    );
    _scheduler = RadioScheduler(
      onScanGate: (enabled) => _transport.setDiscoveryEnabled(enabled),
      enableBatteryMonitor: monitorBattery,
    )..addListener(_onSchedulerChanged);
    _scheduler.setMode(mode);
    _scheduler.setAlwaysListen(relayMode);
  }

  /// Id de conversación del canal abierto (no es un nodo: es "todos").
  static const String channelId = 'todos';

  /// Tope del canal: más corto que un mensaje privado para que quepa en pocos
  /// paquetes al repetirse por toda la malla.
  static const int maxChannelBytes = ChannelMessage.maxTextBytes;

  final NodeIdentity identity;
  final StateStore store;

  late final MeshRouter _router;
  late final RadioScheduler _scheduler;
  MeshTransport _transport;

  final List<ChatMessage> _messages = <ChatMessage>[];
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  final Map<String, String> _linkToPeer = <String, String>{};
  final Map<String, int> _linkRssi = <String, int>{};

  String _displayName;
  RadioMode _radioMode;
  bool _useDemo;
  bool _started = false;
  bool _disposed = false;
  String? _error;
  DateTime? _startedAt;
  bool _shareLocation;
  bool _showProximity;
  bool _relayMode;
  GeoPoint? _myLocation;
  Timer? _retryTimer;
  Timer? _saveTimer;
  Timer? _presenceTimer;
  Timer? _locationTimer;

  /// Cada cuánto se reenvía la posición mientras está activado compartirla.
  static const Duration locationShareEvery = Duration(seconds: 60);

  /// Moverse menos que esto no amerita otro envío: el GPS tiembla solo.
  static const double locationMinMoveMeters = 15;

  /// Avisos de "contacto al alcance": la app los convierte en notificación.
  final StreamController<PeerRecord> _contactReachable =
      StreamController<PeerRecord>.broadcast();

  /// Avisos del canal que merecen notificación (estados y SOS).
  final StreamController<ChannelAlert> _channelAlerts =
      StreamController<ChannelAlert>.broadcast();
  final Set<String> _contactsInRange = <String>{};
  final Map<String, DateTime> _lastNotifiedAt = <String, DateTime>{};

  /// Un contacto cuenta como alcanzable si hay enlace directo o si su anuncio
  /// llegó hace poco por la malla (puede estar a 1–3 saltos).
  static const Duration reachableWindow = Duration(minutes: 15);

  /// Anti-spam: como mucho un aviso por contacto cada 10 minutos.
  static const Duration notifyCooldown = Duration(minutes: 10);

  /// Tope de un mensaje, en bytes UTF-8.
  ///
  /// La fragmentación BLE lleva el número de trozos en un solo byte: con
  /// 1800 bytes de texto la trama siempre cabe en menos de 255 trozos, incluso
  /// cuando el MTU no se negocia y hay que escribir bloques mínimos. Sin tope,
  /// pegar un texto enorme generaba una trama que nunca se podía reensamblar.
  static const int maxMessageBytes = 1800;

  /// Cada cuánto se re-anuncia el nodo. Sin esto, en una cadena A—B—C el
  /// último en llegar nunca conoce a los que ya estaban: solo se anuncian al
  /// conectar y la presencia no se repite. Cuesta un paquete diminuto cada
  /// pocos minutos.
  static const Duration presenceRefresh = Duration(minutes: 5);

  // ---------------------------------------------------------------- getters

  String get displayName => _displayName;
  String get nodeShortId => identity.id.substring(0, 8);
  RadioMode get radioMode => _radioMode;
  bool get usingDemo => _useDemo;
  bool get running => _started;

  /// ¿Se comparten las coordenadas con los contactos?
  bool get shareLocation => _shareLocation;

  /// ¿Se muestran distancia y dirección de quien comparte su ubicación?
  bool get showProximity => _showProximity;

  /// ¿Este teléfono está haciendo de repetidor para los demás?
  bool get relayMode => _relayMode;

  /// Tramas ajenas que este nodo reenvió desde que arrancó.
  int get relayedCount => _router.relayed;

  /// Batería conocida del teléfono (100 si la capa nativa no la reporta).
  int get batteryPercent => _scheduler.batteryLevel;

  GeoPoint? get myLocation => _myLocation;
  String? get error => _error;
  String get transportLabel => _transport.label;
  int get connectedLinks => _transport.connectedLinks;
  bool get scanning => _scheduler.scanning;
  ScanPlan get scanPlan => _scheduler.plan;
  int get batteryLevel => _scheduler.batteryLevel;
  bool get charging => _scheduler.charging;
  DateTime? get startedAt => _startedAt;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  List<ChatMessage> messagesFor(String peerId) =>
      _messages.where((m) => m.peerId == peerId).toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  List<PeerRecord> get peers {
    final list = _router.peers.values.toList()
      ..sort((a, b) {
        if (a.directLink != b.directLink) return a.directLink ? -1 : 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });
    return list;
  }

  PeerRecord? peer(String id) => _router.peers[id];

  /// Libreta de contactos por nombre, estén o no en la malla ahora mismo.
  List<PeerRecord> get contacts =>
      _router.peers.values.where((peer) => peer.isContact).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  bool isContact(String id) => _router.peers[id]?.isContact ?? false;

  /// Código corto de este teléfono, para dictarlo o escribirlo a mano.
  String get myContactCode => contactCodeOf(identity.id);

  /// Busca en la malla actual un nodo por su código corto.
  ///
  /// Solo encuentra a quien ya está anunciándose: sin servidor no hay forma
  /// de resolver un código de alguien que no está al alcance.
  PeerRecord? peerByContactCode(String raw) {
    final code = normalizeContactCode(raw);
    if (!isValidContactCode(code)) return null;
    if (contactCodeOf(identity.id) == code) return null;
    for (final peer in _router.peers.values) {
      if (peer.id == identity.id) continue;
      if (contactCodeOf(peer.id) == code) return peer;
    }
    return null;
  }

  /// Agrega como contacto a quien tenga ese código corto.
  ///
  /// La clave pública no viaja en el código: se usa la que ese nodo ya anunció
  /// por la malla (verificada id↔clave al recibirla), así que no hay riesgo de
  /// suplantación mientras el nodo esté presente.
  Future<AddContactResult> addContactByCode(String raw) async {
    final code = normalizeContactCode(raw);
    if (!isValidContactCode(code)) return AddContactResult.invalid;
    if (contactCodeOf(identity.id) == code) return AddContactResult.ownCode;

    final matches = _router.peers.values
        .where(
          (peer) => peer.id != identity.id && contactCodeOf(peer.id) == code,
        )
        .toList();
    if (matches.isEmpty) return AddContactResult.notFound;
    if (matches.length > 1) return AddContactResult.ambiguous;

    final peer = matches.single;
    if (peer.isContact) return AddContactResult.already;
    peer
      ..isContact = true
      ..contactSince = DateTime.now();
    await _persistNow();
    _refreshReachability(notify: false);
    _notify();
    return AddContactResult.added;
  }

  /// ¿Se le puede escribir a este nodo ahora mismo?
  bool isReachable(PeerRecord peer) =>
      peer.directLink ||
      DateTime.now().difference(peer.lastSeen) < reachableWindow;

  /// Emite una vez cuando un contacto de la libreta pasa a estar al alcance.
  Stream<PeerRecord> get contactReachable => _contactReachable.stream;

  int get pendingCount => _router.outbox.ownPending.length;

  /// Conversaciones ordenadas por el último mensaje.
  List<PeerRecord> get conversations {
    final ids = _messages.map((m) => m.peerId).toSet();
    final known = <PeerRecord>[];
    for (final id in ids) {
      final record = _router.peers[id];
      if (record != null) known.add(record);
    }
    known.sort((a, b) {
      final lastA = messagesFor(a.id).isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : messagesFor(a.id).last.timestamp;
      final lastB = messagesFor(b.id).isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : messagesFor(b.id).last.timestamp;
      return lastB.compareTo(lastA);
    });
    return known;
  }

  ChatMessage? lastMessageFor(String peerId) {
    final list = messagesFor(peerId);
    return list.isEmpty ? null : list.last;
  }

  // ------------------------------------------------------------ ciclo de vida

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _startedAt = DateTime.now();
    _subscribeToTransport();
    try {
      await _transport.start();
      _error = null;
    } catch (error) {
      _error = error is StateError ? error.message : error.toString();
      debugPrint('MeshNode: radio no disponible ($error)');
    }
    _applyIdlePolicy();
    await _scheduler.start();
    // Quien ya estaba al alcance al abrir la app no genera aviso: el usuario
    // está mirando la pantalla.
    _refreshReachability(notify: false);
    _retryTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _retryPending(),
    );
    _presenceTimer = Timer.periodic(
      presenceRefresh,
      (_) => unawaited(_announceToAllLinks()),
    );
    if (_shareLocation) {
      _locationTimer ??= Timer.periodic(
        locationShareEvery,
        (_) => unawaited(shareLocationNow()),
      );
    }
    _notify();
  }

  Future<void> stop() async {
    _retryTimer?.cancel();
    _saveTimer?.cancel();
    _presenceTimer?.cancel();
    _locationTimer?.cancel();
    _locationTimer = null;
    _saveTimer = null;
    _scheduler.stop();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    await _transport.stop();
    // Sin enlaces no hay nodos directos; si no, al cambiar de radio los
    // contactos seguirían mostrando "Enlace directo" sin tenerlo.
    _linkToPeer.clear();
    _linkRssi.clear();
    for (final peer in _router.peers.values) {
      peer.directLink = false;
      // El RSSI era del enlace que acabamos de cerrar: si se queda, la UI
      // dibuja barras de señal de un nodo que ya no está conectado.
      peer.rssi = null;
      // Los saltos eran de una ruta que ya no existe.
      peer.hops = 0;
    }
    _contactsInRange.clear();
    _started = false;
    // Se espera el guardado: con el debounce de 2 s se podía cerrar la app
    // justo antes de escribir y perder el último mensaje.
    await _persistNow();
    _notify();
  }

  /// Cambia entre radio real y demo en caliente (sin reiniciar la app).
  Future<void> switchTransport(MeshTransport next, {required bool demo}) async {
    final wasStarted = _started;
    if (wasStarted) await stop();
    _transport = next;
    _useDemo = demo;
    // Las tramas vistas por la radio anterior no dicen nada de la nueva.
    _router.dedup.clear();
    _scheduler.setMode(_radioMode);
    if (wasStarted) {
      await start();
    } else {
      _notify();
    }
    _scheduleSave();
  }

  Future<void> restartRadio() async {
    if (_started) await stop();
    await start();
  }

  /// Agrega a la libreta el contacto descrito por un código escaneado o pegado.
  ///
  /// El código incluye la clave pública y su id; si no encajan se rechaza, así
  /// que no se puede suplantar a un contacto conocido con un QR falso.
  Future<AddContactResult> addContact(String rawCode, {String? alias}) async {
    final invite = ContactInvite.decode(rawCode);
    if (invite == null) return AddContactResult.invalid;
    if (!await invite.verify()) return AddContactResult.invalid;
    if (invite.nodeId == identity.id) return AddContactResult.ownCode;

    final existing = _router.peers[invite.nodeId];
    if (existing != null && existing.isContact) return AddContactResult.already;

    final name = ContactInvite.clampName(alias ?? invite.name);
    if (existing == null) {
      _router.peers[invite.nodeId] = PeerRecord(
        id: invite.nodeId,
        name: name.isEmpty ? invite.name : name,
        publicKey: invite.publicKey,
        lastSeen: DateTime.fromMillisecondsSinceEpoch(0),
        isContact: true,
        contactSince: DateTime.now(),
      );
    } else {
      existing
        ..isContact = true
        ..contactSince = DateTime.now();
      if (name.isNotEmpty) existing.name = name;
    }
    // Se guarda en el acto: el usuario acaba de agregar el contacto y cerrar
    // la app no debe perderlo.
    await _persistNow();
    _refreshReachability(notify: false);
    _notify();
    return AddContactResult.added;
  }

  /// Saca a alguien de la libreta (sigue apareciendo como nodo de la malla).
  void removeContact(String id) {
    final peer = _router.peers[id];
    if (peer == null || !peer.isContact) return;
    peer
      ..isContact = false
      ..contactSince = null;
    _contactsInRange.remove(id);
    _lastNotifiedAt.remove(id);
    _notify();
    _scheduleSave();
  }

  /// Compara quién de la libreta está al alcance y emite un aviso al aparecer.
  void _refreshReachability({bool notify = true}) {
    if (_disposed) return;
    final now = DateTime.now();
    for (final peer in _router.peers.values) {
      if (!peer.isContact) continue;
      if (!isReachable(peer)) {
        _contactsInRange.remove(peer.id);
        continue;
      }
      if (!_contactsInRange.add(peer.id)) continue;
      if (!notify) continue;
      final last = _lastNotifiedAt[peer.id];
      if (last != null && now.difference(last) < notifyCooldown) continue;
      _lastNotifiedAt[peer.id] = now;
      _contactReachable.add(peer);
    }
  }

  void setDisplayName(String name) {
    // Se recorta igual que el anuncio de presencia: si no, tú verías un nombre
    // de 60 caracteres y los demás recibirían otro distinto.
    final clean = ContactInvite.clampName(name);
    if (clean.isEmpty || clean == _displayName) return;
    _displayName = clean;
    _notify();
    unawaited(_announceToAllLinks());
    _scheduleSave();
  }

  void setRadioMode(RadioMode mode) {
    if (_radioMode == mode) return;
    _radioMode = mode;
    _scheduler.setMode(mode);
    _applyIdlePolicy();
    _notify();
    _scheduleSave();
  }

  /// Un enlace BLE abierto cuesta batería aunque nadie escriba. En los modos de
  /// ahorro se sueltan los que llevan rato callados y se vuelven a abrir en la
  /// siguiente ventana de escaneo; el repetidor, en cambio, vive de tenerlos.
  Duration? get idleLinkTimeout {
    if (_relayMode) return null;
    return switch (_radioMode) {
      RadioMode.supervivencia => const Duration(minutes: 1),
      RadioMode.ahorro => const Duration(minutes: 2),
      RadioMode.equilibrado || RadioMode.rapido => null,
    };
  }

  void _applyIdlePolicy() => _transport.setIdleLinkTimeout(idleLinkTimeout);

  // -------------------------------------------------------------- ubicación

  /// Nueva posición del GPS. La fuente (y el permiso) los gestiona la capa de
  /// plataforma; aquí solo se guarda y, si toca, se comparte.
  void updateMyLocation(GeoPoint point) {
    if (!point.isValid) return;
    final previous = _myLocation;
    _myLocation = point;
    final moved =
        previous == null ||
        distanceMeters(previous, point) >= locationMinMoveMeters;
    // La posición mostrada se refresca siempre; compartirla, solo si de verdad
    // se movió (el GPS tiembla unos metros aunque el teléfono esté quieto).
    _notify();
    if (moved && _shareLocation) unawaited(shareLocationNow());
  }

  /// Activa o desactiva compartir la ubicación con los contactos.
  ///
  /// El permiso lo pide la UI antes de llamar aquí: si el usuario lo niega, el
  /// interruptor no debe quedarse encendido mintiendo.
  Future<void> setShareLocation(bool enabled) async {
    if (_shareLocation == enabled) return;
    _shareLocation = enabled;
    if (enabled) {
      _locationTimer ??= Timer.periodic(
        locationShareEvery,
        (_) => unawaited(shareLocationNow()),
      );
      await shareLocationNow();
    } else {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
    _notify();
    _scheduleSave();
  }

  void setShowProximity(bool enabled) {
    if (_showProximity == enabled) return;
    _showProximity = enabled;
    _notify();
    _scheduleSave();
  }

  // ------------------------------------------------------ canal y repetidor

  /// Activa el modo repetidor: la radio escucha casi todo el tiempo.
  ///
  /// Pensado para un teléfono enchufado en una ventana o un techo. Gasta
  /// mucha más batería que el modo normal, así que es decisión del usuario.
  Future<void> setRelayMode(bool enabled) async {
    if (_relayMode == enabled) return;
    _relayMode = enabled;
    _scheduler.setAlwaysListen(enabled);
    _applyIdlePolicy();
    _notify();
    _scheduleSave();
    if (enabled) await _announceToAllLinks();
  }

  /// Conversación del canal abierto. No hay contacto: es "todos".
  List<ChatMessage> get channelMessages => messagesFor(channelId);

  ChatMessage? get lastChannelMessage {
    final list = channelMessages;
    return list.isEmpty ? null : list.last;
  }

  /// Avisos del canal que merecen una notificación (estados y SOS).
  Stream<ChannelAlert> get channelAlerts => _channelAlerts.stream;

  /// Aviso para cualquiera que esté en la malla.
  Future<void> sendChannelMessage(String text) =>
      _sendChannel(text, ChannelKind.message);

  /// Publica un aviso en el tablero de emergencia.
  ///
  /// Va por el canal abierto (lo lee quien esté cerca, sin destinatario) y se
  /// guarda en cola: a diferencia de un mensaje de chat, un "necesito agua" o
  /// "busco a mi hermano" sigue sirviendo cuando alguien aparezca más tarde.
  Future<void> sendBoardPost(BoardCategory category, String text) =>
      _sendChannel(text, ChannelKind.message, board: category);

  /// Publicaciones vigentes del tablero (caducadas aparte).
  List<ChatMessage> boardPosts(BoardCategory category, {DateTime? now}) =>
      activeBoardPosts(channelMessages, category: category, now: now);

  /// Estado rápido de una familia o un vecino.
  Future<void> sendQuickStatus(QuickStatus status) =>
      _sendChannel(status.label, ChannelKind.status);

  /// Petición de auxilio. Se guarda en cola y se reintenta porque sigue
  /// siendo útil si alguien llega al rato.
  ///
  /// [point] permite adjuntar una posición recién pedida al GPS cuando la app
  /// aún no tenía ninguna (compartir ubicación apagado, app recién abierta).
  Future<void> sendSos({String text = 'Necesito ayuda', GeoPoint? point}) =>
      _sendChannel(text, ChannelKind.sos, point: point);

  Future<void> _sendChannel(
    String text,
    ChannelKind kind, {
    GeoPoint? point,
    BoardCategory? board,
  }) async {
    final clean = clampUtf8Bytes(text.trim(), ChannelMessage.maxTextBytes);
    if (clean.isEmpty) return;
    final expiresAt = board == null ? null : DateTime.now().add(board.validFor);
    final message = ChannelMessage(
      name: _displayName,
      text: clean,
      kind: kind,
      battery: _scheduler.batteryLevel,
      point: kind == ChannelKind.sos ? (point ?? _myLocation) : null,
      board: board,
      expiresAt: expiresAt,
    );
    final frame = await _router.buildChannelFrame(message);
    final hasLinks = _transport.connectedLinks > 0;
    _appendMessage(
      ChatMessage(
        id: frame.idHex,
        peerId: channelId,
        outgoing: true,
        text: clean,
        timestamp: DateTime.now(),
        status: hasLinks
            ? MessageStatus.sent
            : kind == ChannelKind.message && board == null
            ? MessageStatus.failed
            : MessageStatus.queued,
        kind: board != null ? MessageKind.board : _kindOf(kind),
        senderName: _displayName,
        board: board,
        expiresAt: expiresAt,
      ),
    );
    // Un aviso de chat sin nadie cerca no se guarda: un boletín viejo engaña.
    // Los estados, el SOS y el tablero sí: "estoy atrapado aquí" o "busco a
    // mi hermano" siguen sirviendo mañana, y el tablero además caduca solo.
    if (kind != ChannelKind.message || board != null) {
      _router.outbox.enqueueChannel(frame);
    }
    await _broadcast(frame);
    _notify();
    _scheduleSave();
  }

  static MessageKind _kindOf(ChannelKind kind) => switch (kind) {
    ChannelKind.message => MessageKind.text,
    ChannelKind.status => MessageKind.status,
    ChannelKind.sos => MessageKind.sos,
  };

  void _handleChannel(String sourceId, ChannelMessage message, int hops) {
    final peer = _router.peers[sourceId];
    final name = message.name.isNotEmpty
        ? message.name
        : (peer?.name ?? 'Nodo ${shortId(sourceId)}');
    if (peer != null) peer.lastSeen = DateTime.now();

    final now = DateTime.now();
    _appendMessage(
      ChatMessage(
        id: '${now.microsecondsSinceEpoch}-canal-${_messages.length}',
        peerId: channelId,
        outgoing: false,
        text: message.text,
        timestamp: now,
        status: MessageStatus.delivered,
        hops: hops,
        kind: message.board != null ? MessageKind.board : _kindOf(message.kind),
        location: message.point,
        senderName: name,
        board: message.board,
        expiresAt: message.expiresAt,
      ),
    );

    final point = message.point;
    if (point != null && _showProximity) {
      _appendMessage(
        ChatMessage(
          id: '${now.microsecondsSinceEpoch}-canal-bot-${_messages.length}',
          peerId: channelId,
          outgoing: false,
          text: describeProximity(mine: _myLocation, theirs: point, name: name),
          timestamp: now,
          status: MessageStatus.delivered,
          kind: MessageKind.assistant,
          senderName: name,
        ),
      );
    }

    if (message.kind != ChannelKind.message) {
      _channelAlerts.add(
        ChannelAlert(
          name: name,
          text: message.text,
          kind: message.kind,
          hops: hops,
        ),
      );
    }
    _notify();
    _scheduleSave();
  }

  /// Reenvía la posición actual a los contactos que estén al alcance.
  Future<void> shareLocationNow() async {
    final point = _myLocation;
    if (!_shareLocation || point == null) return;
    for (final peer in _router.peers.values) {
      if (!peer.isContact || peer.id == identity.id) continue;
      if (!isReachable(peer)) continue;
      try {
        final frame = await _router.buildLocationFrame(
          peer: peer,
          point: point,
        );
        await _broadcast(frame);
      } catch (error) {
        debugPrint('Ubicación: no se pudo enviar a ${peer.shortCode} ($error)');
      }
    }
  }

  /// Envía la posición a un chat concreto (botón rápido del chat).
  ///
  /// No se guarda en la cola: una ubicación vieja entregada mañana sería
  /// peor que ninguna. Si no hay enlace, se marca como fallida.
  Future<bool> sendMyLocation(String peerId, {GeoPoint? point}) async {
    final target = _router.peers[peerId];
    final geo = point ?? _myLocation;
    if (target == null || geo == null || !geo.isValid) return false;

    final frame = await _router.buildLocationFrame(peer: target, point: geo);
    final hasLinks = _transport.connectedLinks > 0;
    _appendMessage(
      ChatMessage(
        id: frame.idHex,
        peerId: peerId,
        outgoing: true,
        text: 'Mi ubicación',
        timestamp: DateTime.now(),
        status: hasLinks ? MessageStatus.sent : MessageStatus.failed,
        kind: MessageKind.location,
        location: geo,
      ),
    );
    await _broadcast(frame);
    _notify();
    _scheduleSave();
    return hasLinks;
  }

  /// Texto corto para la UI y los avisos: "≈30 m al NE".
  ///
  /// Sin coordenadas del otro teléfono no hay dirección posible; solo se
  /// ofrece el rango grueso que da el RSSI.
  String? proximityLabel(PeerRecord peer) {
    if (!_showProximity) return null;
    final theirs = peer.location;
    if (theirs != null) {
      final mine = _myLocation;
      if (mine == null) return 'compartió su ubicación';
      return '≈${formatDistance(distanceMeters(mine, theirs))} al '
          '${cardinalShort(bearingDegrees(mine, theirs))}';
    }
    return rssiRangeLabel(peer.rssi);
  }

  /// Cuerpo de la notificación de contacto al alcance.
  String notifyBody(PeerRecord peer) {
    final label = proximityLabel(peer);
    if (peer.directLink) {
      return label == null
          ? 'Enlace directo: puedes escribirle ahora.'
          : 'Enlace directo · $label';
    }
    return label == null
        ? 'Está en la malla: tu mensaje ya puede llegar.'
        : 'En la malla · $label';
  }

  /// Agrega a la libreta a alguien que ya conocemos por su anuncio.
  ///
  /// La clave pública vino verificada en la presencia (id ↔ clave), así que
  /// agregarlo desde el chat no relaja ninguna garantía.
  Future<bool> addContactFromPeer(String id) async {
    final peer = _router.peers[id];
    if (peer == null || peer.id == identity.id) return false;
    if (peer.isContact) return true;
    peer
      ..isContact = true
      ..contactSince = DateTime.now();
    await _persistNow();
    _refreshReachability(notify: false);
    _notify();
    return true;
  }

  void restore(AppSnapshot snapshot) {
    _displayName = snapshot.displayName;
    _radioMode = snapshot.radioMode;
    _useDemo = snapshot.useDemo;
    _shareLocation = snapshot.shareLocation;
    _showProximity = snapshot.showProximity;
    _relayMode = snapshot.relayMode;
    _messages
      ..clear()
      ..addAll(snapshot.messages);
    for (final peer in snapshot.peers) {
      _router.peers[peer.id] = peer;
    }
    _router.outbox.restore(snapshot.outbox);
    _scheduler.setMode(_radioMode);
    _scheduler.setAlwaysListen(_relayMode);
    _refreshReachability(notify: false);
    _notify();
  }

  // ------------------------------------------------------------------ envío

  Future<void> sendMessage(String peerId, String text) async {
    final target = _router.peers[peerId];
    final clean = clampUtf8Bytes(text.trim(), maxMessageBytes);
    if (clean.isEmpty || target == null) return;

    final frame = await _router.buildMessageFrame(peer: target, text: clean);
    _appendMessage(
      ChatMessage(
        id: frame.idHex,
        peerId: peerId,
        outgoing: true,
        text: clean,
        timestamp: DateTime.now(),
        status: MessageStatus.queued,
      ),
    );
    _router.outbox.enqueueOwn(frame);
    await _broadcast(frame);
    if (_transport.connectedLinks > 0) {
      _markStatus(frame.idHex, MessageStatus.sent);
    }
    _notify();
    _scheduleSave();
  }

  // ------------------------------------------------------------- callbacks

  void _subscribeToTransport() {
    _subscriptions
      ..add(
        _transport.inbound.listen((packet) {
          unawaited(_router.handlePacket(packet.bytes, linkId: packet.linkId));
        }),
      )
      ..add(_transport.linkEvents.listen(_handleLinkEvent));
  }

  Future<void> _broadcast(MeshFrame frame, {String? exceptLink}) async {
    try {
      await _transport.send(frame.encode(), exceptLink: exceptLink);
    } catch (error) {
      debugPrint('Malla: error de envío ($error)');
    }
  }

  Future<void> _handleLinkEvent(LinkEvent event) async {
    if (event.connected) {
      _linkToPeer.putIfAbsent(event.linkId, () => '');
      if (event.rssi != null) _linkRssi[event.linkId] = event.rssi!;
      // Presencia inmediata: es lo que permite descubrirse sin escanear más.
      try {
        await _transport.send(
          _router.presenceFrame(_displayName).encode(),
          onlyLink: event.linkId,
        );
      } catch (error) {
        debugPrint('Malla: presencia falló ($error)');
      }
      await _router.flushOnNewLink();
      // Los avisos de canal pendientes ya salieron por este enlace.
      if (_transport.connectedLinks > 0) {
        for (final entry in _router.outbox.ownPending) {
          if (entry.frame.type == FrameType.channel) {
            _markStatus(entry.frame.idHex, MessageStatus.sent);
          }
        }
      }
    } else {
      _linkToPeer.remove(event.linkId);
      _linkRssi.remove(event.linkId);
    }
    _recomputeDirectLinks();
    _refreshReachability();
    _scheduler.setHasLinks(_transport.connectedLinks > 0);
    _notify();
  }

  Future<void> _announceToAllLinks() async {
    try {
      await _transport.send(_router.presenceFrame(_displayName).encode());
    } catch (_) {}
  }

  void _handlePresence(PeerRecord peer, String? linkId) {
    if (linkId != null) {
      _linkToPeer[linkId] = peer.id;
      peer.rssi = _linkRssi[linkId];
    }
    _recomputeDirectLinks();
    _scheduler.onScanResult(found: true);
    _refreshReachability();
    _notify();
    _scheduleSave();
  }

  Future<void> _handleIncoming(PeerRecord from, String text, int hops) async {
    _appendMessage(
      ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        peerId: from.id,
        outgoing: false,
        text: text,
        timestamp: DateTime.now(),
        status: MessageStatus.delivered,
        hops: hops,
      ),
    );
    _notify();
    _scheduleSave();
  }

  void _handleLocation(PeerRecord from, GeoPoint point, int hops) {
    from.location = point;
    final now = DateTime.now();
    _appendMessage(
      ChatMessage(
        id: '${now.microsecondsSinceEpoch}-geo',
        peerId: from.id,
        outgoing: false,
        text: 'Ubicación compartida',
        timestamp: now,
        status: MessageStatus.delivered,
        hops: hops,
        kind: MessageKind.location,
        location: point,
      ),
    );
    // El "asistente" es aritmética local: sin modelos, sin red, sin cuentas.
    if (_showProximity) {
      _appendMessage(
        ChatMessage(
          id: '${now.microsecondsSinceEpoch}-bot',
          peerId: from.id,
          outgoing: false,
          text: describeProximity(
            mine: _myLocation,
            theirs: point,
            name: from.name,
          ),
          timestamp: now,
          status: MessageStatus.delivered,
          kind: MessageKind.assistant,
        ),
      );
    }
    _notify();
    _scheduleSave();
  }

  void _handleAck(String frameKey, String fromPeerId) {
    final frameId = frameKey.split(':').last;
    _markStatus(frameId, MessageStatus.delivered);
    _notify();
    _scheduleSave();
  }

  /// Tope del historial en memoria y en disco.
  ///
  /// Sin tope, el archivo de estado se reescribe entero cada 2 s con todo el
  /// historial: con miles de mensajes eso es jank en la UI y un JSON enorme
  /// que puede tardar más de lo que el sistema deja vivir al proceso.
  static const int maxHistory = 3000;

  void _appendMessage(ChatMessage message) {
    _messages.add(message);
    if (_messages.length <= maxHistory) return;
    final excess = _messages.length - maxHistory;
    _messages.removeRange(0, excess);
  }

  void _markStatus(String messageId, MessageStatus status) {
    for (final message in _messages) {
      if (message.id == messageId && message.outgoing) {
        message.status = status;
      }
    }
  }

  void _recomputeDirectLinks() {
    final directIds = _linkToPeer.values.where((id) => id.isNotEmpty).toSet();
    for (final peer in _router.peers.values) {
      peer.directLink = directIds.contains(peer.id);
    }
  }

  void _onSchedulerChanged() => _notify();

  void _retryPending() {
    final expired = _router.outbox.pruneExpired();
    for (final key in expired) {
      _markStatus(key.split(':').last, MessageStatus.failed);
    }
    if (_transport.connectedLinks > 0) {
      // Solo lo que ya toca según el backoff: con 200 pendientes, reintentar
      // todo cada 20 s solo gasta radio.
      for (final entry in _router.outbox.dueForRetry()) {
        _router.outbox.markAttempt(entry.key);
        // Un fallo de radio no debe convertirse en un error asíncrono suelto.
        unawaited(_broadcast(entry.frame));
      }
    }
    // Sin avisos aquí: solo actualiza quién sigue al alcance.
    _refreshReachability(notify: false);
    _notify();
    _scheduleSave();
  }

  // ------------------------------------------------------------- persistencia

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _saveNow);
  }

  void _saveNow() => unawaited(_persistNow());

  Future<void> _persistNow() => store.save(
    AppSnapshot(
      displayName: _displayName,
      privateKey: identity.privateKeyBytes,
      messages: List<ChatMessage>.from(_messages),
      peers: _router.peers.values.toList(),
      outbox: _router.outbox.encode(),
      radioMode: _radioMode,
      useDemo: _useDemo,
      shareLocation: _shareLocation,
      showProximity: _showProximity,
      relayMode: _relayMode,
    ),
  );

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Crea la identidad (o la recupera) y elige la radio guardada.
  static Future<MeshNode> bootstrap({bool monitorBattery = true}) async {
    final store = StateStore();
    final snapshot = await store.load();
    final identity = snapshot == null
        ? await NodeIdentity.generate()
        : await NodeIdentity.fromPrivateKey(snapshot.privateKey);
    final useDemo = snapshot?.useDemo ?? false;
    final transport = useDemo
        ? DemoMeshTransport(owner: identity)
        : BleMeshTransport(identity: identity);
    final node = MeshNode(
      identity: identity,
      store: store,
      transport: transport,
      displayName: snapshot?.displayName ?? 'Yo',
      mode: snapshot?.radioMode ?? RadioMode.equilibrado,
      monitorBattery: monitorBattery,
      useDemo: useDemo,
      shareLocation: snapshot?.shareLocation ?? false,
      showProximity: snapshot?.showProximity ?? false,
      relayMode: snapshot?.relayMode ?? false,
    );
    if (snapshot != null) node.restore(snapshot);
    return node;
  }

  MeshTransport createDemoTransport() => DemoMeshTransport(owner: identity);

  MeshTransport createBleTransport() => BleMeshTransport(identity: identity);

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _saveTimer?.cancel();
    _presenceTimer?.cancel();
    _locationTimer?.cancel();
    _scheduler.removeListener(_onSchedulerChanged);
    _scheduler.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _contactReachable.close();
    _channelAlerts.close();
    super.dispose();
  }
}
