import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/contact_code.dart';
import '../mesh/mesh_node.dart';
import 'widgets.dart';

/// Abre la pantalla de "mi código / escanear" y avisa del resultado.
Future<void> openAddContact(BuildContext context) async {
  final result = await Navigator.of(context).push<AddContactResult>(
    MaterialPageRoute<AddContactResult>(
      builder: (_) => const AddContactPage(),
    ),
  );
  if (result == null || !context.mounted) return;
  final message = switch (result) {
    AddContactResult.added => 'Contacto agregado a tu libreta',
    AddContactResult.already => 'Ese contacto ya estaba en tu libreta',
    AddContactResult.ownCode => 'Ese código es el de este mismo teléfono',
    AddContactResult.invalid => 'El código no es válido o está dañado',
    AddContactResult.notFound => 'Ese código no está en la malla ahora',
    AddContactResult.ambiguous => 'Hay dos nodos con ese código: usa el QR',
  };
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Agrega a alguien dictando su código corto: alternativa al QR sin cámara.
///
/// El código solo identifica a quien ya está anunciándose en la malla; la
/// clave pública se toma del anuncio de presencia, que viene verificado.
Future<void> openAddByCode(BuildContext context) async {
  final node = context.read<MeshNode>();
  final controller = TextEditingController();
  final raw = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Agregar por código'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              LengthLimitingTextInputFormatter(9),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
            ],
            decoration: const InputDecoration(
              hintText: 'ABC-DEF',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          const SizedBox(height: 10),
          Text(
            'Es el código que aparece bajo el nombre de la otra persona. '
            'Solo funciona si su teléfono está en la malla ahora mismo.',
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Buscar'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (raw == null || !context.mounted) return;

  final code = normalizeContactCode(raw);
  if (!isValidContactCode(code)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('El formato es ABC-DEF')),
    );
    return;
  }
  final peer = node.peerByContactCode(code);
  if (peer == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nadie con el código ${formatContactCode(code)} está en la malla '
          'ahora. Acercaos o usa el QR.',
        ),
      ),
    );
    return;
  }
  if (peer.isContact) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${peer.name} ya está en tu libreta')),
    );
    return;
  }

  // Se confirma con el nombre a la vista: el código es corto y dos personas
  // distintas podrían compartir uno.
  final confirm = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¿Agregar contacto?'),
      content: Text(
        '${peer.name}\n${formatContactCode(code)}\n\n'
        'Comprueba que es la persona correcta antes de agregarla.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Agregar'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  final result = await node.addContactByCode(code);
  if (!context.mounted) return;
  final message = switch (result) {
    AddContactResult.added => '${peer.name} agregado a tu libreta',
    AddContactResult.already => '${peer.name} ya estaba en tu libreta',
    AddContactResult.ownCode => 'Ese es tu propio código',
    AddContactResult.ambiguous => 'Hay dos nodos con ese código: usa el QR',
    AddContactResult.notFound => 'Ese nodo ya no está en la malla',
    AddContactResult.invalid => 'Ese código no es válido',
  };
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Agregar un contacto: mostrar el QR propio y escanear (o pegar) el del otro.
class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final MobileScannerController _scanner;

  bool _scanHandled = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_onTabChanged);
    _scanner = MobileScannerController(
      // Solo QR y sin repetir el mismo código: menos CPU y batería.
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scanner.dispose();
    super.dispose();
  }

  ContactInvite _myInvite(MeshNode node) => ContactInvite(
        nodeId: node.identity.id,
        publicKey: node.identity.publicKeyBytes,
        name: node.displayName,
      );

  Future<void> _add(MeshNode node, String code) async {
    if (_adding) return;
    setState(() => _adding = true);
    final result = await node.addContact(code);
    if (!mounted) return;
    setState(() => _adding = false);
    if (result == AddContactResult.invalid) {
      // Se deja seguir escaneando: el siguiente QR puede ser el bueno.
      _scanHandled = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ese QR no es un código válido de Chasqui')),
      );
      return;
    }
    Navigator.of(context).pop(result);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanHandled || _adding) return;
    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        raw = value;
        break;
      }
    }
    if (raw == null) return;
    _scanHandled = true;
    await _add(context.read<MeshNode>(), raw);
  }

  Future<void> _pasteCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pegar código'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'SINRED1:…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    await _add(context.read<MeshNode>(), code);
  }

  Future<void> _copyCode(MeshNode node) async {
    await Clipboard.setData(ClipboardData(text: _myInvite(node).encode()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Código copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final node = context.watch<MeshNode>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agregar contacto'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Mi código'),
            Tab(text: 'Escanear'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MyCodeTab(
            invite: _myInvite(node),
            displayName: node.displayName,
            onCopy: () => _copyCode(node),
            onPaste: _adding ? null : _pasteCode,
          ),
          _scanTab(),
        ],
      ),
    );
  }

  Widget _scanTab() {
    // El escáner solo se monta cuando la pestaña está visible: si no, la
    // cámara quedaría encendida mientras el usuario mira su propio código.
    if (_tabs.index != 1) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(
                controller: _scanner,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(
                  error: error,
                  onRetry: () => unawaited(_scanner.start()),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            children: [
              Text(
                'Apunta al QR de la otra persona. Al leerlo se guarda como '
                'contacto y te avisará cuando esté al alcance.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _adding ? null : _pasteCode,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('Pegar el código en su lugar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MyCodeTab extends StatelessWidget {
  const _MyCodeTab({
    required this.invite,
    required this.displayName,
    required this.onCopy,
    required this.onPaste,
  });

  final ContactInvite invite;
  final String displayName;
  final VoidCallback onCopy;
  final VoidCallback? onPaste;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: QrImageView(
              data: invite.encode(),
              version: QrVersions.auto,
              size: 220,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu código de contacto',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        Center(
          child: ActionChip(
            avatar: const Icon(Icons.copy_all, size: 18),
            label: Text(
              formatContactCode(contactCodeOf(invite.nodeId)),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                fontSize: 18,
              ),
            ),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text: formatContactCode(contactCodeOf(invite.nodeId)),
              ));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Código corto copiado')),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Díctalo o escríbelo: sirve para agregarte sin cámara cuando estés '
          'cerca. Para alguien que no está en la malla, comparte el QR.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 18),
        InfoCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.qr_code_2, color: scheme.primary),
                  const SizedBox(width: 10),
                  const Text(
                    'Cómo funciona',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'El QR lleva tu id y tu clave pública. Quien lo escanee te '
                'agrega a su libreta y puede escribirte aunque no estés cerca: '
                'el mensaje espera en su teléfono. Compártelo solo con quien '
                'quieras que te agregue.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (displayName == 'Yo') ...[
                const SizedBox(height: 8),
                Text(
                  'Ponle tu nombre en Ajustes para que te reconozcan.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: scheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy_all, size: 18),
          label: const Text('Copiar mi código'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onPaste,
          icon: const Icon(Icons.content_paste, size: 18),
          label: const Text('Pegar el código de otra persona'),
        ),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography_outlined,
                  size: 44, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                denied
                    ? 'Sin permiso de cámara'
                    : 'No se pudo abrir la cámara',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                denied
                    ? 'Concede el permiso de cámara en los ajustes de Android '
                        'o usa el código pegado.'
                    : 'Puedes pegar el código a mano con el botón de abajo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ),
        ),
      ),
    );
  }
}
