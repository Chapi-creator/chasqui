import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../mesh/mesh_node.dart';
import 'add_contact_page.dart';
import 'chat_page.dart';
import 'widgets.dart';

/// Libreta: los contactos guardados, estén o no al alcance ahora mismo.
class ContactsPage extends StatelessWidget {
  const ContactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final contacts = node.contacts;
    final scheme = Theme.of(context).colorScheme;
    final nearby = contacts.where(node.isReachable).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        InfoCard(
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
                      Icons.qr_code_2,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Agrega por QR',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Se guarda para siempre, aunque cierres la app',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Escanea el código de la otra persona o comparte el tuyo. '
                'Cuando un contacto entre en alcance, el teléfono te avisa: '
                'ya puedes escribirle.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: () => openAddContact(context),
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text('Agregar contacto'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => openAddByCode(context),
                    icon: const Icon(Icons.dialpad, size: 18),
                    label: const Text('Por código'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              'Contactos',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              nearby > 0
                  ? '${contacts.length} · $nearby al alcance'
                  : '${contacts.length}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (contacts.isEmpty)
          InfoCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Column(
                children: [
                  Icon(
                    Icons.contacts_outlined,
                    size: 40,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Todavía no tienes contactos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Toca "Agregar contacto" y escanea el QR de la otra '
                    'persona. A partir de ahí sabrás cuándo está cerca y '
                    'podrás escribirle.',
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
          for (final contact in contacts) ...[
            _ContactTile(node: node, contact: contact),
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
                    'Qué significa "al alcance"',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Enlace directo: su teléfono está lo bastante cerca como para '
                'hablar por Bluetooth. En la malla: se le puede escribir a '
                'través de otros teléfonos intermedios. Si no está, tu mensaje '
                'queda guardado y sale cuando aparezca.',
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.node, required this.contact});

  final MeshNode node;
  final PeerRecord contact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inRange = node.isReachable(contact);
    final proximity = node.proximityLabel(contact);
    final suffix = proximity == null ? '' : ' · $proximity';
    final subtitle = !inRange
        ? 'Sin señal · te avisamos cuando aparezca'
        : contact.directLink
        ? 'Al alcance · enlace directo$suffix'
        : 'Al alcance · ${contact.hops} saltos$suffix';

    return InfoCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          PeerAvatar(name: contact.name, online: inRange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  contact.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '$subtitle · ${contact.shortCode}',
                  style: TextStyle(
                    fontSize: 11,
                    color: inRange ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Un contacto alcanzable por 2 saltos no tiene señal propia: pintar
          // barras llenas ahí era una mentira visual.
          if (inRange)
            SignalBars(rssi: contact.rssi, active: contact.directLink),
          IconButton(
            tooltip: 'Escribir',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(peerId: contact.id),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (value) {
              if (value != 'remove') return;
              node.removeContact(contact.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${contact.name} salió de tus contactos'),
                ),
              );
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'remove',
                child: Text('Quitar de contactos'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
