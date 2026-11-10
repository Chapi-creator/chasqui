import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/channel.dart';
import 'core/geo.dart';
import 'core/models.dart';
import 'mesh/mesh_node.dart';
import 'platform/location_service.dart';
import 'platform/power_service.dart';
import 'ui/active_chat.dart';
import 'ui/chat_page.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

class ChasquiApp extends StatefulWidget {
  const ChasquiApp({super.key, required this.node});

  final MeshNode node;

  @override
  State<ChasquiApp> createState() => _ChasquiAppState();
}

class _ChasquiAppState extends State<ChasquiApp> with WidgetsBindingObserver {
  StreamSubscription<PeerRecord>? _reachableSubscription;
  StreamSubscription<GeoPoint>? _locationSubscription;
  StreamSubscription<ChannelAlert>? _alertSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reachableSubscription = widget.node.contactReachable.listen((peer) {
      // Si el chat ya está abierto, un aviso encima sería ruido.
      if (activeChatPeerId == peer.id) return;
      unawaited(PowerService.notifyContact(
        peer.name,
        peerId: peer.id,
        body: widget.node.notifyBody(peer),
      ));
    });
    _alertSubscription = widget.node.channelAlerts.listen((alert) {
      // Si el canal ya está abierto, la burbuja llega a la vista: una
      // notificación encima solo estorba (salvo un SOS, que sí interrumpe).
      if (activeChatPeerId == MeshNode.channelId &&
          alert.kind != ChannelKind.sos) {
        return;
      }
      final sos = alert.kind == ChannelKind.sos;
      unawaited(PowerService.notifyChannel(
        title: sos ? 'SOS de ${alert.name}' : alert.name,
        body: alert.hops > 0 ? '${alert.text} · ${alert.hops} saltos' : alert.text,
        sos: sos,
      ));
    });
    // Tocar la notificación abre el chat de esa persona, aunque la app ya
    // estuviera abierta en otra pestaña.
    PowerService.setChatOpenHandler(_openChat);
    _locationSubscription =
        LocationService.updates.listen(widget.node.updateMyLocation);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapRadio());
  }

  void _openChat(String peerId) {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => ChatPage(peerId: peerId)),
    );
  }

  Future<void> _bootstrapRadio() async {
    final node = widget.node;
    // Primero los permisos y luego la radio: Android 14 cierra el proceso si
    // el servicio en primer plano arranca con el tipo connectedDevice sin
    // BLUETOOTH_CONNECT/SCAN/ADVERTISE concedidos.
    await PowerService.requestPermissions();
    await node.start();
    final links = node.connectedLinks;
    final foreground = await PowerService.startForeground(
      text: links > 0
          ? 'Malla activa · $links ${links == 1 ? 'enlace' : 'enlaces'}'
          : 'Escuchando la malla',
    );
    if (!foreground) {
      debugPrint('PowerService: la malla sigue sin servicio en primer plano');
    }
    // Si la ubicación estaba activada pero el permiso ya no está (o el GPS se
    // apagó), el interruptor no debe seguir diciendo que sí.
    if (node.shareLocation && !await LocationService.start()) {
      await node.setShareLocation(false);
    }
    // La app pudo abrirse tocando una notificación.
    final pendingChat = await PowerService.takePendingChat();
    if (pendingChat != null && mounted) _openChat(pendingChat);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver se refresca el texto del servicio; sin el contador de
      // enlaces la notificación perdía información útil.
      final links = widget.node.connectedLinks;
      unawaited(PowerService.updateText(
        links > 0
            ? 'Malla activa · $links ${links == 1 ? 'enlace' : 'enlaces'}'
            : 'Escuchando la malla',
      ));
    }
  }

  @override
  void dispose() {
    _reachableSubscription?.cancel();
    _locationSubscription?.cancel();
    _alertSubscription?.cancel();
    PowerService.setChatOpenHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<MeshNode>.value(
      value: widget.node,
      child: MaterialApp(
        title: 'Chasqui',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ChasquiTheme.light(),
        darkTheme: ChasquiTheme.dark(),
        themeMode: ThemeMode.system,
        home: const HomePage(),
      ),
    );
  }
}
