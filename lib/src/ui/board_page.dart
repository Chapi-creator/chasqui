import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/board.dart';
import '../core/models.dart';
import '../mesh/mesh_node.dart';
import 'widgets.dart';

/// Tablero de emergencia: cuatro listas con lo que la gente necesita saber
/// ahora (agua, refugio, desaparecidos, peligro), cada aviso con su hora y su
/// caducidad a la vista.
///
/// Todo viaja por el canal abierto, así que funciona con los mismos enlaces,
/// relevos y acarreados que el resto de la malla: no hay servidor detrás.
class BoardPage extends StatefulWidget {
  const BoardPage({super.key, this.initialCategory});

  /// Pestaña con la que abre (por ejemplo, desde el botón de un SOS).
  final BoardCategory? initialCategory;

  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: BoardCategory.values.length,
    vsync: this,
    initialIndex: widget.initialCategory?.index ?? 0,
  );

  @override
  void initState() {
    super.initState();
    // El botón de publicar dice la categoría abierta: hay que repintarlo.
    _tabs.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _publish(MeshNode node) async {
    final category = BoardCategory.values[_tabs.index];
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _ComposeDialog(category: category),
    );
    if (text == null || text.trim().isEmpty) return;
    await node.sendBoardPost(category, text);
    if (!mounted) return;
    final queued = node.connectedLinks == 0;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          queued
              ? 'Guardado: sale solo cuando aparezca alguien con la app'
              : 'Aviso publicado en ${category.label}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final scheme = Theme.of(context).colorScheme;
    final current = BoardCategory.values[_tabs.index];
    final counts = {
      for (final category in BoardCategory.values)
        category: node.boardPosts(category).length,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tablero de emergencia'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final category in BoardCategory.values)
              Tab(text: '${category.label} (${counts[category]})'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _publish(node),
        icon: Icon(boardIcon(current)),
        label: Text('Publicar en ${current.label.toLowerCase()}'),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: scheme.surfaceContainerHighest,
            child: Text(
              'Lo más nuevo arriba. Cada aviso caduca solo: peligro en 2 h, '
              'necesito y ofrezco en 12 h, desaparecidos en 48 h.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final category in BoardCategory.values)
                  _BoardList(category: category),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardList extends StatelessWidget {
  const _BoardList({required this.category});

  final BoardCategory category;

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    final scheme = Theme.of(context).colorScheme;
    final active = node.boardPosts(category);
    final total = node.channelMessages
        .where((m) => m.kind == MessageKind.board && m.board == category)
        .length;
    final expired = total - active.length;

    if (active.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 96),
        children: [
          Icon(
            boardIcon(category),
            size: 56,
            color: boardColor(category, scheme).withValues(alpha: 0.6),
          ),
          const SizedBox(height: 14),
          Text(
            'Nada en «${category.label}» todavía',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            category.hint,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Text(
            'Se comparte con quien esté al alcance y con los teléfonos que pasen '
            'después, aunque no haya internet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (expired > 0) ...[
            const SizedBox(height: 20),
            Text(
              expired == 1
                  ? '1 aviso caducado oculto'
                  : '$expired avisos caducados ocultos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: active.length + (expired > 0 ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == active.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              expired == 1
                  ? '1 aviso caducado oculto'
                  : '$expired avisos caducados ocultos',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          );
        }
        return _BoardCard(post: active[index], category: category);
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.post, required this.category});

  final ChatMessage post;
  final BoardCategory category;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = boardColor(category, scheme);
    final expiresAt = post.expiresAt;
    final author = post.senderName ?? 'Alguien';
    final hops = post.hops == 0 ? 'directo' : '${post.hops} saltos';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: tint, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(post.text, style: const TextStyle(fontSize: 14, height: 1.35)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(boardIcon(category), size: 13, color: tint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$author · ${formatLastSeen(post.timestamp)} · $hops',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (expiresAt != null)
                Text(
                  formatBoardRemaining(expiresAt),
                  style: TextStyle(fontSize: 11, color: tint),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComposeDialog extends StatefulWidget {
  const _ComposeDialog({required this.category});

  final BoardCategory category;

  @override
  State<_ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<_ComposeDialog> {
  final TextEditingController _controller = TextEditingController();
  int _bytes = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _tooLong => _bytes > MeshNode.maxChannelBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = boardColor(widget.category, scheme);
    return AlertDialog(
      title: Row(
        children: [
          Icon(boardIcon(widget.category), size: 20, color: tint),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.category.label)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.category.hint,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) =>
                setState(() => _bytes = utf8.encode(value.trim()).length),
            decoration: const InputDecoration(
              hintText: 'Corto y concreto: qué, dónde y desde cuándo.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$_bytes / ${MeshNode.maxChannelBytes} bytes · caduca en '
            '${widget.category.validFor.inHours} h',
            style: TextStyle(
              fontSize: 11,
              color: _tooLong ? scheme.error : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _bytes == 0 || _tooLong
              ? null
              : () => Navigator.of(context).pop(_controller.text),
          child: const Text('Publicar'),
        ),
      ],
    );
  }
}

IconData boardIcon(BoardCategory category) => switch (category) {
  BoardCategory.need => Icons.water_drop_outlined,
  BoardCategory.offer => Icons.inventory_2_outlined,
  BoardCategory.missing => Icons.person_search_outlined,
  BoardCategory.danger => Icons.warning_amber_rounded,
};

Color boardColor(BoardCategory category, ColorScheme scheme) =>
    switch (category) {
      BoardCategory.need => const Color(0xFFE0A23A),
      BoardCategory.offer => const Color(0xFF2FA36B),
      BoardCategory.missing => const Color(0xFF3D8FD1),
      BoardCategory.danger => scheme.error,
    };
