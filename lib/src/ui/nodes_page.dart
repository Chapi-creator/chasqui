import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../mesh/mesh_node.dart';
import 'chat_page.dart';
import 'widgets.dart';

class NodesPage extends StatelessWidget {
  const NodesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final peers = node.peers;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        _RadioCard(node: node),
        if (node.error != null) ...[
          const SizedBox(height: 12),
          InfoCard(
            color: scheme.errorContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bluetooth_disabled, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Radio no disponible',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: scheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  node.error!,
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: node.restartRadio,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reintentar'),
                    ),
                    TextButton.icon(
                      onPressed: () => node.switchTransport(
                        node.createDemoTransport(),
                        demo: true,
                      ),
                      icon: const Icon(Icons.smart_toy_outlined, size: 18),
                      label: const Text('Modo demo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              'Nodos en la malla',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '${peers.length}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (peers.isEmpty)
          InfoCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Icon(Icons.radar, size: 40, color: scheme.primary),
                  const SizedBox(height: 10),
                  const Text(
                    'Nadie al alcance todavía',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'La malla se descubre por anuncios BLE. Con dos teléfonos '
                    'cerca, abre SinRed en ambos: se verán en segundos.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (final peer in peers) ...[
            _PeerTile(node: node, peer: peer),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 20),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Alcance real',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Cada salto Bluetooth cubre entre 10 y 100 m según el lugar. '
                'Con cadenas de teléfonos (un nodo repite al siguiente) el '
                'mensaje puede cruzar varios cientos de metros, y si alguien '
                'lo lleva encima, kilómetros. No es magia: sin teléfonos '
                'intermedios no hay milagro a 5 km.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = node.scanPlan;
    final duty = (plan.dutyCycle * 100).toStringAsFixed(1);

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  node.scanning ? Icons.bluetooth_searching : Icons.bluetooth,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.transportLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      node.scanning
                          ? 'Escuchando la malla ahora'
                          : 'Radio en reposo (ahorro)',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  node.radioMode.label,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(
                label: 'Enlaces',
                value: '${node.connectedLinks}',
                icon: Icons.link,
              ),
              _Metric(
                label: 'Escucha',
                value: '$duty%',
                icon: Icons.hearing,
              ),
              _Metric(
                label: 'Batería',
                value: '${node.batteryLevel}%',
                icon: node.charging ? Icons.battery_charging_full : Icons.battery_5_bar,
              ),
              _Metric(
                label: 'Pendientes',
                value: '${node.pendingCount}',
                icon: Icons.outbox,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: plan.dutyCycle.clamp(0.02, 1.0),
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ventana de ${plan.window.inSeconds}s cada '
            '${plan.interval.inSeconds}s · el advertising sigue activo '
            '(consume ~20 veces menos que escanear)',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.node, required this.peer});

  final MeshNode node;
  final PeerRecord peer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InfoCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          PeerAvatar(name: peer.name, online: peer.directLink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peer.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_linkLabel(peer)}'
                  ' · ${peer.shortCode} · ${formatLastSeen(peer.lastSeen)}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          SignalBars(rssi: peer.rssi, active: peer.directLink),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Abrir chat',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ChatPage(peerId: peer.id),
              ));
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
        ],
      ),
    );
  }
}

/// Cómo describir el enlace con un nodo sin inventar saltos: un contacto
/// guardado que ya no está al alcance tiene `hops == 0` y no es "0 saltos".
String _linkLabel(PeerRecord peer) {
  if (peer.directLink) return 'Enlace directo';
  if (peer.hops > 0) return '${peer.hops} saltos';
  return 'Sin señal';
}
