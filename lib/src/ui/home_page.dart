import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../mesh/mesh_node.dart';
import 'add_contact_page.dart';
import 'chat_page.dart';
import 'contacts_page.dart';
import 'nodes_page.dart';
import 'settings_page.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('SinRed', style: TextStyle(fontWeight: FontWeight.w700)),
            _StatusLine(node: node),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reiniciar radio',
            onPressed: node.running
                ? () async {
                    await node.restartRadio();
                    if (context.mounted && node.error != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(node.error!)),
                      );
                    }
                  }
                : null,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          _ChatsTab(),
          ContactsPage(),
          NodesPage(),
          SettingsPage(),
        ],
      ),
      floatingActionButton: switch (_tab) {
        0 => FloatingActionButton.extended(
            onPressed: () => _openNewChat(context),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Nuevo chat'),
          ),
        1 => FloatingActionButton.extended(
            onPressed: () => openAddContact(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Agregar'),
          ),
        _ => null,
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.contacts_outlined),
            selectedIcon: Icon(Icons.contacts),
            label: 'Contactos',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'Nodos',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Future<void> _openNewChat(BuildContext context) async {
    final node = context.read<MeshNode>();
    final peers = node.peers;
    if (peers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aún no hay nodos cerca. La app escucha la malla por ventanas; '
            'también puedes probar el modo demo en Ajustes.',
          ),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Nodos al alcance',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final peer in peers)
              ListTile(
                leading: PeerAvatar(
                  name: peer.name,
                  online: peer.directLink,
                ),
                title: Text(peer.name),
                subtitle: Text(
                  '${peer.directLink ? 'Enlace directo' : peer.hops > 0 ? '${peer.hops} saltos' : 'Sin señal'}'
                  ' · ${peer.shortCode}',
                ),
                trailing: SignalBars(rssi: peer.rssi),
                onTap: () => Navigator.of(sheetContext).pop(peer.id),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatPage(peerId: selected),
        ),
      );
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String text;
    Color color;
    if (node.error != null) {
      text = 'Radio sin conexión';
      color = const Color(0xFFE0645B);
    } else if (node.relayMode) {
      text = 'Repetidor · ${node.relayedCount} reenviados';
      color = const Color(0xFF7C5CFF);
    } else if (node.usingDemo) {
      text = 'Modo demo · ${node.connectedLinks} nodos simulados';
      color = scheme.primary;
    } else if (node.connectedLinks > 0) {
      text = 'Malla activa · ${node.connectedLinks} '
          '${node.connectedLinks == 1 ? 'enlace' : 'enlaces'}';
      color = const Color(0xFF2FD37A);
    } else if (node.scanning) {
      text = 'Buscando nodos…';
      color = scheme.primary;
    } else {
      text = 'En reposo · escucha cada ${node.scanPlan.interval.inSeconds}s';
      color = scheme.onSurfaceVariant;
    }
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _ChatsTab extends StatelessWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final conversations = node.conversations;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: conversations.isEmpty ? 2 : conversations.length + 1,
      separatorBuilder: (_, index) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        if (index == 0) return _ChannelTile(node: node);
        if (conversations.isEmpty) return _EmptyChats(node: node);
        final peer = conversations[index - 1];
        final last = node.lastMessageFor(peer.id);
        return ListTile(
          leading: PeerAvatar(name: peer.name, online: peer.directLink),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  peer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (last != null)
                Text(
                  formatRelative(last.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: last.status == MessageStatus.delivered || !last.outgoing
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          subtitle: Row(
            children: [
              if (last != null && last.outgoing) ...[
                DeliveryTicks(status: last.status),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  last?.text ?? 'Sin mensajes todavía',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatPage(peerId: peer.id),
            ),
          ),
        );
      },
    );
  }
}

/// Entrada fija del canal abierto, arriba de todas las conversaciones.
class _ChannelTile extends StatelessWidget {
  const _ChannelTile({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = node.lastChannelMessage;
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.primaryContainer,
        child: Icon(
          Icons.campaign_outlined,
          color: scheme.onPrimaryContainer,
        ),
      ),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Todos',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (last != null)
            Text(
              formatRelative(last.timestamp),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
      subtitle: Text(
        last == null
            ? 'Canal abierto: avisos, estados y SOS para quien esté cerca'
            : '${last.senderName ?? 'Alguien'}: ${last.text}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ChatPage(peerId: MeshNode.channelId),
        ),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = node.scanPlan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Icon(Icons.forum_outlined, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Text(
          'Chatea sin internet',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          'Los mensajes viajan de teléfono en teléfono por Bluetooth LE. '
          'No hay servidor ni operador: si no hay nadie cerca, el mensaje '
          'queda guardado y sale cuando alguien aparece.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
        ),
        const SizedBox(height: 24),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.battery_saver, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Consumo controlado',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Escucha ${plan.window.inSeconds}s cada ${plan.interval.inSeconds}s '
                '(${(plan.dutyCycle * 100).toStringAsFixed(1)}% del tiempo). '
                'El resto, la radio descansa.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_outline, color: scheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Cifrado de extremo a extremo',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Cada teléfono tiene su par de claves X25519. El nodo que '
                'repite un mensaje no puede leerlo.',
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => node.switchTransport(
            node.createDemoTransport(),
            demo: true,
          ),
          icon: const Icon(Icons.smart_toy_outlined),
          label: const Text('Probar con nodos simulados'),
        ),
        ],
      ),
    );
  }
}
