import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/channel.dart';
import '../core/geo.dart';
import '../core/models.dart';
import '../mesh/mesh_node.dart';
import '../platform/compass_service.dart';
import '../platform/location_service.dart';
import 'active_chat.dart';
import 'board_page.dart';
import 'widgets.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.peerId});

  /// Id del nodo, o [MeshNode.channelId] para el canal abierto "Todos".
  final String peerId;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;

  StreamSubscription<double>? _compassSubscription;
  double? _heading;
  bool _compassTried = false;
  bool _compassScheduled = false;

  bool get _isChannel => widget.peerId == MeshNode.channelId;

  @override
  void initState() {
    super.initState();
    activeChatPeerId = widget.peerId;
  }

  @override
  void dispose() {
    if (activeChatPeerId == widget.peerId) activeChatPeerId = null;
    _compassSubscription?.cancel();
    if (_compassTried) unawaited(CompassService.stop());
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(MeshNode node) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final limit = _isChannel
        ? MeshNode.maxChannelBytes
        : MeshNode.maxMessageBytes;
    if (utf8.encode(text).length > limit) {
      // Se avisa en vez de recortar a escondidas: el usuario decide qué quitar.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mensaje demasiado largo (máx. $limit bytes). Divídelo en dos.',
          ),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    _controller.clear();
    if (_isChannel) {
      await node.sendChannelMessage(text);
    } else {
      await node.sendMessage(widget.peerId, text);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _scrollToLatest();
  }

  /// Botón rápido: manda la posición de este teléfono al chat abierto.
  Future<void> _sendLocation(MeshNode node) async {
    if (_sending) return;
    var point = node.myLocation;
    if (point == null) {
      final granted = await LocationService.requestPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para enviar coordenadas hace falta el permiso de ubicación.',
            ),
          ),
        );
        return;
      }
      point = await LocationService.current();
    }
    if (!mounted) return;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Todavía no hay posición del GPS. Prueba al aire libre en unos '
            'segundos.',
          ),
        ),
      );
      return;
    }
    node.updateMyLocation(point);
    final sent = await node.sendMyLocation(widget.peerId, point: point);
    if (!mounted) return;
    if (sent) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Sin enlace ahora mismo: una ubicación vieja no se guarda en cola.',
        ),
      ),
    );
  }

  Future<void> _sendSos(MeshNode node) async {
    if (_sending) return;
    setState(() => _sending = true);
    // Un SOS sin coordenadas sirve mucho menos. Si aún no hay posición, se
    // pide la última conocida al GPS (sin abrir un diálogo de permisos en
    // mitad de una emergencia: si no está concedido, sale sin posición).
    var point = node.myLocation;
    if (point == null && await LocationService.hasPermission()) {
      point = await LocationService.current();
    }
    await node.sendSos(point: point);
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          node.connectedLinks > 0
              ? 'SOS enviado a la malla. Se repetirá por si alguien más llega.'
              : 'Nadie al alcance ahora: el SOS queda en cola y solo.',
        ),
      ),
    );
    _scrollToLatest();
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.minScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// La brújula solo se enciende si hay a quién apuntar.
  void _ensureCompass(MeshNode node) {
    if (_isChannel || _compassTried) return;
    final peer = node.peer(widget.peerId);
    if (peer?.location == null || node.myLocation == null) return;
    _compassTried = true;
    _compassSubscription = CompassService.headings.listen((heading) {
      if (mounted) setState(() => _heading = heading);
    });
    unawaited(CompassService.start());
  }

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final peer = _isChannel ? null : node.peer(widget.peerId);
    final messages = node.messagesFor(widget.peerId).reversed.toList();
    final scheme = Theme.of(context).colorScheme;

    if (!_isChannel && peer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nodo desconocido')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Este nodo ya no está en la malla. Espera a que vuelva a '
              'anunciarse para escribirle.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (peer != null && !_compassScheduled) {
      // Un solo callback pendiente: antes cada rebuild apilaba otro.
      _compassScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _compassScheduled = false;
        _ensureCompass(node);
      });
    }

    final myPoint = node.myLocation;
    final peerPoint = peer?.location;
    final showCompass = peer != null && peerPoint != null && myPoint != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: _isChannel ? null : 0,
        title: _isChannel
            ? _ChannelTitle(node: node)
            : Row(
                children: [
                  PeerAvatar(
                    name: peer!.name,
                    radius: 18,
                    online: peer.directLink,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          peer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          _subtitle(peer, node),
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        actions: [
          if (_isChannel)
            IconButton(
              tooltip: 'Tablero de emergencia',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BoardPage()),
              ),
              icon: const Icon(Icons.dashboard_outlined),
            ),
          if (_isChannel)
            IconButton(
              tooltip: 'Qué es el canal',
              onPressed: () => _showChannelInfo(context),
              icon: const Icon(Icons.info_outline),
            ),
          // Alguien con quien ya hablas puede pasar a la libreta sin salir.
          if (peer != null && !peer.isContact)
            IconButton(
              tooltip: 'Agregar a contactos',
              onPressed: () async {
                // Se captura antes del await para no usar el context después.
                final messenger = ScaffoldMessenger.of(context);
                final added = await node.addContactFromPeer(peer.id);
                if (!added) return;
                messenger.showSnackBar(
                  SnackBar(content: Text('${peer.name} está en tus contactos')),
                );
              },
              icon: const Icon(Icons.person_add_alt_1_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          if (showCompass)
            _CompassStrip(
              bearing: bearingDegrees(myPoint, peerPoint),
              heading: _heading,
              distance: distanceMeters(myPoint, peerPoint),
            ),
          Expanded(
            child: messages.isEmpty
                ? (_isChannel ? const _EmptyChannel() : _EmptyChat(peer: peer!))
                : ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final newer = index == 0 ? null : messages[index - 1];
                      final showDay =
                          newer == null ||
                          !_sameDay(newer.timestamp, message.timestamp);
                      return Column(
                        children: [
                          if (showDay) _DayDivider(time: message.timestamp),
                          _Bubble(
                            message: message,
                            myLocation: myPoint,
                            channel: _isChannel,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_isChannel)
            _ChannelComposer(
              controller: _controller,
              sending: _sending,
              connectedLinks: node.connectedLinks,
              onSend: () => _send(node),
              onStatus: (status) {
                node.sendQuickStatus(status);
                _scrollToLatest();
              },
              onSos: () => _sendSos(node),
            )
          else
            _Composer(
              controller: _controller,
              sending: _sending,
              enabled: peer!.directLink || node.connectedLinks > 0,
              onSend: () => _send(node),
              onLocation: () => _sendLocation(node),
            ),
        ],
      ),
    );
  }

  String _subtitle(PeerRecord peer, MeshNode node) {
    final proximity = node.proximityLabel(peer);
    if (peer.directLink) {
      return proximity == null
          ? 'Enlace directo · cifrado de extremo a extremo'
          : 'Enlace directo · $proximity';
    }
    if (peer.hops > 0) {
      return proximity == null
          ? '${peer.hops} saltos en la malla · cifrado'
          : '${peer.hops} saltos · $proximity';
    }
    return proximity == null
        ? 'Sin señal ahora · el mensaje queda en cola'
        : 'Sin señal · $proximity';
  }

  Future<void> _showChannelInfo(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Canal Todos'),
        content: const Text(
          'Es el canal abierto de la malla: lo lee cualquiera que esté cerca y '
          'se reenvía hasta 5 saltos.\n\n'
          '• No hay destinatario ni confirmación de entrega.\n'
          '• El texto va cifrado con una clave de grupo, no en claro.\n'
          '• El nombre y la batería que ves los declaró el emisor.\n'
          '• El SOS lleva tu posición si la tienes y se reintenta solo.\n\n'
          'Úsalo para avisos cortos: agua, refugio, peligro, "estoy bien".\n\n'
          'El icono del tablero, arriba, separa los avisos por categoría '
          '(necesito, ofrezco, desaparecidos, peligro) y los caduca solo, para '
          'que nadie salga a buscar agua donde ya no hay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ChannelTitle extends StatelessWidget {
  const _ChannelTitle({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final links = node.connectedLinks;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: scheme.primaryContainer,
          child: Icon(
            Icons.campaign_outlined,
            size: 20,
            color: scheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Todos',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                links > 0
                    ? 'Canal abierto · $links ${links == 1 ? 'enlace' : 'enlaces'}'
                    : 'Canal abierto · sin enlaces ahora',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Flecha hacia la otra persona usando el rumbo calculado y la brújula.
///
/// Sin magnetómetro se muestra igual la sigla y la distancia: la flecha es un
/// extra, no la única forma de entender el dato.
class _CompassStrip extends StatelessWidget {
  const _CompassStrip({
    required this.bearing,
    required this.heading,
    required this.distance,
  });

  final double bearing;
  final double? heading;
  final double distance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = heading;
    final rotation = current == null
        ? 0.0
        : (bearing - current) * math.pi / 180;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          Transform.rotate(
            angle: rotation,
            child: Icon(
              Icons.navigation_rounded,
              size: 22,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'A ${formatDistance(distance)} al ${cardinalShort(bearing)}'
              '${current == null ? ' · brújula no disponible' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.myLocation, this.channel = false});

  final ChatMessage message;
  final GeoPoint? myLocation;
  final bool channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final outgoing = message.outgoing;
    final assistant = message.kind == MessageKind.assistant;
    final sos = message.kind == MessageKind.sos;
    final status = message.kind == MessageKind.status;

    final background = sos
        ? scheme.errorContainer
        : status
        ? scheme.tertiaryContainer
        : assistant
        ? scheme.secondaryContainer
        : outgoing
        ? (dark ? const Color(0xFF125C4B) : const Color(0xFFD9FDD3))
        : (dark ? const Color(0xFF1F2C33) : Colors.white);
    final textColor = sos
        ? scheme.onErrorContainer
        : status
        ? scheme.onTertiaryContainer
        : assistant
        ? scheme.onSecondaryContainer
        : outgoing && dark
        ? Colors.white
        : scheme.onSurface;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(outgoing ? 14 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (channel && !outgoing && message.senderName != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: textColor.withValues(alpha: 0.75),
                  ),
                ),
              ),
            if (message.board != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      boardIcon(message.board!),
                      size: 13,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      message.board!.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            if (message.kind == MessageKind.location &&
                message.location != null)
              _LocationContent(
                message: message,
                mine: myLocation,
                color: textColor,
              )
            else if (assistant)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 16, color: textColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              )
            else if (sos || status)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    sos ? Icons.emergency_outlined : Icons.volunteer_activism,
                    size: 18,
                    color: textColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(
                message.text,
                style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!outgoing && message.hops > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${message.hops} saltos',
                      style: TextStyle(
                        fontSize: 10,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                Text(
                  formatClock(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
                if (outgoing) ...[
                  const SizedBox(width: 4),
                  DeliveryTicks(
                    status: message.status,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de un mensaje con coordenadas. Tocar copia el par lat,lon.
class _LocationContent extends StatelessWidget {
  const _LocationContent({
    required this.message,
    required this.mine,
    required this.color,
  });

  final ChatMessage message;
  final GeoPoint? mine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final geo = message.location!;
    final myPoint = mine;
    final distance = myPoint == null ? null : distanceMeters(myPoint, geo);
    final direction = myPoint == null
        ? null
        : cardinalShort(bearingDegrees(myPoint, geo));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Clipboard.setData(
          ClipboardData(
            text:
                '${geo.lat.toStringAsFixed(6)}, '
                '${geo.lon.toStringAsFixed(6)}',
          ),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Coordenadas copiadas')));
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.place_outlined, size: 17, color: color),
              const SizedBox(width: 5),
              Text(
                message.outgoing ? 'Mi ubicación' : 'Ubicación compartida',
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${geo.lat.toStringAsFixed(5)}, ${geo.lon.toStringAsFixed(5)}',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Precisión ±${geo.accuracy.round()} m · toca para copiar',
            style: TextStyle(
              color: color.withValues(alpha: 0.65),
              fontSize: 10,
            ),
          ),
          if (!message.outgoing && distance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '≈${formatDistance(distance)} al $direction desde aquí',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          formatRelative(time) == formatClock(time)
              ? 'Hoy'
              : formatRelative(time),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.peer});

  final PeerRecord peer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Los mensajes con ${peer.name} viajan cifrados por la malla.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sin internet, sin número de teléfono y sin servidores.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChannel extends StatelessWidget {
  const _EmptyChannel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 44, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              'El canal de la malla',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Escribe un aviso corto y lo recibirá cualquiera que esté cerca, '
              'aunque no sea tu contacto. Con el botón SOS mandas tu posición '
              'y se repite hasta que alguien lo escuche.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra del canal: estados rápidos, SOS y texto.
class _ChannelComposer extends StatelessWidget {
  const _ChannelComposer({
    required this.controller,
    required this.sending,
    required this.connectedLinks,
    required this.onSend,
    required this.onStatus,
    required this.onSos,
  });

  final TextEditingController controller;
  final bool sending;
  final int connectedLinks;
  final VoidCallback onSend;
  final void Function(QuickStatus status) onStatus;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 6),
                children: [
                  for (final status in QuickStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: Icon(
                          status == QuickStatus.ok
                              ? Icons.check_circle_outline
                              : status == QuickStatus.help
                              ? Icons.front_hand_outlined
                              : Icons.warning_amber_outlined,
                          size: 16,
                        ),
                        label: Text(
                          status.label,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onPressed: sending ? null : () => onStatus(status),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Pulsación larga: un SOS por accidente asusta a todo el barrio.
                GestureDetector(
                  onLongPress: sending ? null : onSos,
                  child: Container(
                    width: 52,
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sos, size: 20, color: scheme.onError),
                        Text(
                          'SOS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: scheme.onError,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: connectedLinks > 0
                          ? 'Aviso para la malla'
                          : 'Sin enlaces: el SOS se guarda en cola',
                      suffixIcon: Icon(
                        Icons.campaign_outlined,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: FilledButton(
                    onPressed: sending ? null : onSend,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Mantén pulsado SOS para pedir auxilio con tu posición.',
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.enabled,
    required this.onSend,
    required this.onLocation,
  });

  final TextEditingController controller;
  final bool sending;
  final bool enabled;
  final VoidCallback onSend;
  final VoidCallback onLocation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Enviar mi ubicación',
              onPressed: sending ? null : onLocation,
              icon: const Icon(Icons.my_location, size: 20),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: enabled
                      ? 'Mensaje por la malla'
                      : 'Sin enlaces: se enviará al recuperar señal',
                  suffixIcon: Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              height: 48,
              child: FilledButton(
                onPressed: sending ? null : onSend,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                ),
                child: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
