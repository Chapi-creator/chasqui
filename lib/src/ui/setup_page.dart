import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mesh/mesh_node.dart';
import 'guide_page.dart';

/// Primera pantalla de la app: el nombre es obligatorio.
///
/// En la malla no hay números de teléfono ni cuentas: el nombre es lo único
/// que ve el otro lado. Antes todos arrancaban como "Yo" y nadie lo cambiaba,
/// así que en una emergencia había cinco "Yo" en el canal y no se sabía quién
/// pedía ayuda. Por eso ahora se pide una vez, al instalar.
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final TextEditingController _name = TextEditingController();
  int _step = 0;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() {
      if (_error != null && _clean(_name.text).length >= 2) {
        setState(() => _error = null);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  static String _clean(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  void _next() {
    final name = _clean(_name.text);
    if (name.length < 2) {
      setState(() => _error = 'Escribí tu nombre (al menos 2 letras).');
      return;
    }
    if (name.length > 24) {
      setState(() => _error = 'Máximo 24 caracteres.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _finish() async {
    if (_saving) return;
    final name = _clean(_name.text);
    if (name.length < 2) {
      setState(() => _step = 0);
      return;
    }
    setState(() => _saving = true);
    await context.read<MeshNode>().completeSetup(name);
    // No hace falta navegar: la app se reconstruye cuando el nodo avisa que
    // ya tiene nombre (ver ChasquiApp).
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _step == 0
              ? _nameStep(context, scheme)
              : _introStep(context, scheme),
        ),
      ),
    );
  }

  Widget _nameStep(BuildContext context, ColorScheme scheme) {
    return Padding(
      key: const ValueKey('nombre'),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.badge_outlined,
                color: scheme.onPrimaryContainer,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '¿Cómo te llamas?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Es el nombre que van a ver los demás cuando pidas ayuda o mandes '
            'un mensaje. No es una cuenta: se queda en tu teléfono y viaja '
            'solo cuando escribís algo.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 24),
          TextField(
            key: const Key('setup-nombre'),
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.words,
            maxLength: 24,
            onSubmitted: (_) => _next(),
            decoration: InputDecoration(
              labelText: 'Tu nombre',
              hintText: 'Ej: Ana, Bombero 3, Vecino del 2B',
              errorText: _error,
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                'Consejo: si sos parte de una brigada, poné el nombre y el '
                'grupo ("Ana · Cuadrilla 3"). Si no, tu nombre de pila alcanza.',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ),
          FilledButton(
            key: const Key('setup-continuar'),
            onPressed: _next,
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  Widget _introStep(BuildContext context, ColorScheme scheme) {
    final cards = <(IconData, String, String)>[
      (
        Icons.forum_outlined,
        'Mensajes sin internet',
        'Chats, fotos y avisos que saltan de teléfono en teléfono por '
            'Bluetooth. Si no hay nadie cerca, quedan guardados.',
      ),
      (
        Icons.sos,
        'Emergencia',
        'SOS, estados rápidos, tablero de necesito/ofrezco/desaparecidos y '
            'señales de rescate con linterna y sirena.',
      ),
      (
        Icons.tag,
        'Canales y grupos',
        'Creá un canal con nombre ("Refugio Norte") y que los demás entren. '
            'Con clave, solo lo lee quien la sepa.',
      ),
      (
        Icons.flashlight_on_outlined,
        'Morse',
        'Mandá y leé mensajes por luz parpadeante. No usa la radio ni los datos '
            'y funciona aunque todo lo demás esté apagado.',
      ),
    ];
    return Padding(
      key: const ValueKey('intro'),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hola, ${_clean(_name.text)}',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Esto es lo que tenés adentro. Todo funciona sin señal.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                for (final card in cards)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(card.$1, color: scheme.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                card.$2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                card.$3,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const GuidePage(intro: true),
                    ),
                  ),
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Ver la guía completa de funciones'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('setup-empezar'),
            onPressed: _saving ? null : _finish,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Empezar'),
          ),
          TextButton(
            onPressed: _saving ? null : () => setState(() => _step = 0),
            child: const Text('Cambiar el nombre'),
          ),
        ],
      ),
    );
  }
}
