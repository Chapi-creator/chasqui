import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/named_channel.dart';
import '../mesh/mesh_node.dart';
import 'chat_page.dart';
import 'guide_page.dart';

/// Lista de canales con nombre: crear, entrar y salir.
///
/// No hay servidor que busque canales: el nombre es el canal. Dos personas
/// escriben lo mismo y quedan conectadas sin haberse conocido.
class ChannelsPage extends StatelessWidget {
  const ChannelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final channels = node.channels;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Canales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openJoin(context, node),
        icon: const Icon(Icons.add),
        label: const Text('Crear o entrar'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            'Un canal agrupa a la gente que escribe el mismo nombre: '
            '"Refugio Norte", "Cuadrilla 3", "Edificio B". Cualquiera puede '
            'crearlo y los demás entran escribiendo el mismo nombre. Si le '
            'ponés clave, solo lo lee quien la sepa.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GuidePage()),
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Cómo funcionan los canales'),
          ),
          const SizedBox(height: 8),
          if (channels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.tag, size: 48, color: scheme.primary),
                  const SizedBox(height: 12),
                  const Text(
                    'Todavía no estás en ningún canal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Creá uno con el nombre de tu grupo, o entrá al que ya '
                    'existe en tu barrio.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            for (final channel in channels)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(
                      channel.isPrivate ? Icons.lock_outline : Icons.tag,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  title: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    _subtitle(node, channel),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'abrir') {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChatPage.channel(channel),
                          ),
                        );
                      } else if (value == 'salir') {
                        await _confirmLeave(context, node, channel);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'abrir', child: Text('Abrir')),
                      PopupMenuItem(
                        value: 'salir',
                        child: Text('Salir del canal'),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ChatPage.channel(channel),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  static String _subtitle(MeshNode node, NamedChannel channel) {
    final count = node.messagesFor(channel.peerId).length;
    final parts = <String>[
      channel.isPrivate ? 'Con clave' : 'Canal abierto',
      count == 0
          ? 'sin mensajes'
          : '$count ${count == 1 ? 'mensaje' : 'mensajes'}',
      'ID ${channel.id.substring(0, 6)}',
    ];
    return parts.join(' · ');
  }

  Future<void> _confirmLeave(
    BuildContext context,
    MeshNode node,
    NamedChannel channel,
  ) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Salir de ${channel.name}'),
        content: const Text(
          'Los mensajes de este canal se borran de tu teléfono. Si volvés a '
          'entrar con el mismo nombre, empiezas de cero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (leave == true) await node.leaveChannel(channel.id);
  }

  Future<void> _openJoin(BuildContext context, MeshNode node) async {
    final result = await showModalBottomSheet<NamedChannel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _JoinSheet(node: node),
    );
    if (result == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ChatPage.channel(result)),
    );
  }
}

class _JoinSheet extends StatefulWidget {
  const _JoinSheet({required this.node});

  final MeshNode node;

  @override
  State<_JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<_JoinSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (!NamedChannel.isValidName(name)) {
      setState(() => _error = 'El nombre necesita entre 2 y 32 caracteres.');
      return;
    }
    if (!NamedChannel.isValidPassphrase(_pass.text.trim())) {
      setState(() => _error = 'La clave no puede tener más de 64 caracteres.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final channel = await widget.node.joinChannel(
      name: name,
      passphrase: _pass.text,
    );
    if (!mounted) return;
    if (channel == null) {
      setState(() {
        _busy = false;
        _error = 'No se pudo crear el canal con ese nombre.';
      });
      return;
    }
    Navigator.of(context).pop(channel);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Crear o entrar a un canal',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Si el canal ya existe entre la gente que está cerca, al entrar con '
            'el mismo nombre te unís a la conversación que ya está en curso.',
            style: TextStyle(
              fontSize: 12.5,
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 32,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nombre del canal',
              hintText: 'Ej: Refugio Norte',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _pass,
            maxLength: 64,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _enter(),
            decoration: const InputDecoration(
              labelText: 'Clave (opcional)',
              helperText: 'Con clave, solo entra quien la sepa',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          FilledButton(
            onPressed: _busy ? null : _enter,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Entrar'),
          ),
        ],
      ),
    );
  }
}
