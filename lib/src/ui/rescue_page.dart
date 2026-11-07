import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/rescue_service.dart';
import '../rescue/morse.dart';
import '../rescue/sighting.dart';
import 'signal_panel_page.dart';
import 'widgets.dart';

/// Panel de señales de rescate: luz SOS, sirena, símbolos de suelo a aire y
/// contador de tiempo desde el último avistamiento.
///
/// Todo es local: pantalla, linterna y altavoz. La radio no se toca en ningún
/// momento, así que la malla sigue escuchando y enviando con el panel abierto.
class RescuePage extends StatefulWidget {
  const RescuePage({super.key});

  @override
  State<RescuePage> createState() => _RescuePageState();
}

class _RescuePageState extends State<RescuePage> {
  /// Fondo del SOS cuando la pantalla no está en la fase blanca. Casi negro,
  /// para que el contraste con el destello sea el máximo.
  static const Color _night = Color(0xFF05090C);

  final SightingLog _log = SightingLog();
  late final SosBlinker _blinker;
  Timer? _ageTicker;

  bool _sos = false;
  bool _light = false;
  int _step = 0;
  bool _torchAvailable = false;
  bool _useTorch = true;
  bool _useScreen = true;
  bool _siren = false;
  bool _torchFailed = false;
  DateTime? _lastSighting;

  @override
  void initState() {
    super.initState();
    _blinker = SosBlinker(onStep: _onStep);
    // Un rebuild por segundo para el contador. Frente a una pantalla al máximo
    // es ruido, y solo corre mientras hay una marca que mostrar.
    _ageTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _lastSighting == null) return;
      setState(() {});
    });
    _probeTorch();
    _loadSighting();
  }

  @override
  void dispose() {
    _blinker.stop();
    _ageTicker?.cancel();
    // Apaga linterna, sirena y el brillo forzado aunque el usuario salga con
    // el botón atrás del sistema.
    unawaited(RescueService.release());
    super.dispose();
  }

  Future<void> _probeTorch() async {
    final available = await RescueService.hasTorch();
    if (!mounted) return;
    setState(() {
      _torchAvailable = available;
      if (!available) _useTorch = false;
    });
  }

  Future<void> _loadSighting() async {
    final loaded = await _log.load();
    if (!mounted || loaded == null) return;
    setState(() => _lastSighting = loaded);
  }

  Future<void> _markSighting() async {
    final now = DateTime.now();
    setState(() => _lastSighting = now);
    await _log.save(now);
  }

  Future<void> _startSos() async {
    if (_sos) return;
    // Brillo al máximo y pantalla sin apagarse: el patrón tiene que poder
    // verse al sol y no cortarse a los treinta segundos.
    await RescueService.keepAwake(true);
    if (!mounted) return;
    setState(() {
      _sos = true;
      _light = false;
      _step = 0;
    });
    _blinker.start();
  }

  Future<void> _stopSos() async {
    _blinker.stop();
    await RescueService.setTorch(false);
    await RescueService.keepAwake(false);
    if (!mounted) return;
    setState(() {
      _sos = false;
      _light = false;
    });
  }

  void _onStep(int index, LightStep step) {
    if (!mounted) return;
    setState(() {
      _step = index;
      _light = step.on;
    });
    if (_useTorch && _torchAvailable) {
      unawaited(_driveTorch(step.on));
    }
  }

  Future<void> _driveTorch(bool on) async {
    final ok = await RescueService.setTorch(on);
    // Si la linterna falló una vez (otra app con la cámara), se sigue con la
    // pantalla en lugar de reintentar diecisiete veces por ciclo.
    if (!ok && on && mounted && !_torchFailed) {
      _torchFailed = true;
      setState(() {
        _torchAvailable = false;
        _useTorch = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La linterna no se pudo encender (¿otra app usa la cámara?). '
            'El SOS sigue con la pantalla.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleTorch(bool value) async {
    setState(() {
      _useTorch = value;
      _torchFailed = false;
    });
    if (_sos) await RescueService.setTorch(value && _light);
  }

  void _toggleScreen(bool value) {
    setState(() => _useScreen = value);
  }

  Future<void> _toggleSiren(bool value) async {
    final ok = await RescueService.setSiren(value);
    if (!mounted) return;
    setState(() => _siren = value && ok);
    if (value && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo encender la sirena: el altavoz está ocupado.'),
        ),
      );
    }
  }

  void _openSignal(GroundSignal signal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SignalPanelPage(signal: signal, lastSighting: _lastSighting),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_sos) return _buildSosScreen();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Señales de rescate',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _localCard(scheme),
          const SizedBox(height: 12),
          _sosCard(scheme),
          const SizedBox(height: 12),
          _sirenCard(scheme),
          const SizedBox(height: 12),
          _signalsCard(scheme),
          const SizedBox(height: 12),
          _sightingCard(scheme),
          const SizedBox(height: 12),
          _batteryNote(scheme),
        ],
      ),
    );
  }

  Widget _cardTitle(ColorScheme scheme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: scheme.primary),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _localCard(ColorScheme scheme) {
    return InfoCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.offline_bolt_outlined, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Todo esto ocurre en el teléfono: sin datos, sin servidor y sin '
              'tocar la radio. La malla sigue escuchando y enviando mientras '
              'tenés este panel abierto.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sosCard(ColorScheme scheme) {
    final canSignal = _useTorch || _useScreen;
    final seconds = sosCycleDuration().inMilliseconds / 1000;
    final cycle = seconds.toStringAsFixed(1).replaceAll('.', ',');
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.sos, 'SOS con luz'),
          const SizedBox(height: 10),
          Text(
            'Tres cortos, tres largos, tres cortos: el patrón que busca un '
            'rescatista. La pantalla y la linterna parpadean juntas, en un '
            'ciclo de $cycle s que se repite solo.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 14),
          _MorseStrip(dim: scheme.primary.withValues(alpha: 0.35)),
          const SizedBox(height: 2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Linterna'),
            subtitle: Text(
              _torchAvailable
                  ? 'La de atrás, la que se ve de lejos'
                  : 'Este teléfono no reporta linterna',
            ),
            value: _useTorch,
            onChanged: _torchAvailable
                ? (value) => unawaited(_toggleTorch(value))
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Pantalla blanca'),
            subtitle: const Text(
              'A brillo máximo, aunque el teléfono esté en modo oscuro',
            ),
            value: _useScreen,
            onChanged: _toggleScreen,
          ),
          if (!canSignal)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Elegí al menos una luz: sin linterna ni pantalla no hay señal.',
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canSignal ? _startSos : null,
              icon: const Icon(Icons.flare),
              label: const Text('Empezar SOS'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sirenCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.volume_up_outlined, 'Sirena'),
          const SizedBox(height: 8),
          Text(
            'Dos tonos alternos por el altavoz, al volumen de alarma: suena '
            'aunque el teléfono esté en silencio.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Encender sirena'),
            subtitle: Text(_siren ? 'Sonando' : 'Apagada'),
            value: _siren,
            onChanged: (value) => unawaited(_toggleSiren(value)),
          ),
        ],
      ),
    );
  }

  Widget _signalsCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.wb_sunny_outlined, 'Señalización'),
          const SizedBox(height: 8),
          Text(
            'Símbolos de suelo a aire en negro sobre blanco: la pantalla se ve '
            'desde el aire y no gasta radio. Mostrala al sol, sin reflejos.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 4),
          for (final signal in GroundSignal.values) _signalTile(signal, scheme),
        ],
      ),
    );
  }

  Widget _signalTile(GroundSignal signal, ColorScheme scheme) {
    final subtitle = switch (signal) {
      GroundSignal.medical => 'La X pide médico: no mover al herido.',
      GroundSignal.help => 'La V pide ayuda o rescate.',
      GroundSignal.direction => 'La flecha indica por dónde vas.',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.onSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: signal == GroundSignal.direction
            ? Icon(Icons.arrow_upward, color: scheme.surface, size: 22)
            : Text(
                signal.glyph,
                style: TextStyle(
                  color: scheme.surface,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
      ),
      title: Text(signal.label),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openSignal(signal),
    );
  }

  Widget _sightingCard(ColorScheme scheme) {
    final last = _lastSighting;
    final age = last == null ? null : DateTime.now().difference(last);
    final stale = age != null && age.inHours >= 6;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.visibility_outlined, 'Último avistamiento'),
          const SizedBox(height: 12),
          Text(
            age == null ? 'Sin marcar' : formatSightingAge(age),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: stale ? const Color(0xFFE0645B) : null,
            ),
          ),
          if (last != null)
            Text(
              'A las ${formatClock(last)} · ${last.day}/${last.month}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          Text(
            'Marcá cada vez que veas un avión, un helicóptero o gente. Si el '
            'número crece, cambiá de señal, de lugar o de hora.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => unawaited(_markSighting()),
            icon: const Icon(Icons.visibility),
            label: const Text('Vi algo ahora'),
          ),
        ],
      ),
    );
  }

  Widget _batteryNote(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.battery_alert_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'El SOS es lo que más gasta: linterna y pantalla al máximo vacían '
              'la batería en horas. Si el avión no está pasando, apagalo; la '
              'malla sigue funcionando y el teléfono dura mucho más.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Pantalla completa del SOS: destello blanco en los pulsos, negro en las
  /// pausas. Sin barra de la app, para que no haya nada más iluminado.
  Widget _buildSosScreen() {
    final lit = _useScreen && _light;
    final bg = lit ? Colors.white : _night;
    final fg = lit ? Colors.black : Colors.white;
    final subtitle = _useTorch && _useScreen
        ? 'Linterna y pantalla'
        : _useScreen
        ? 'Solo pantalla'
        : 'Solo linterna';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_stopSos());
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sos, color: fg, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'SOS · ... --- ...',
                      style: TextStyle(
                        color: fg,
                        fontSize: 13,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MorseStrip(
                          active: sosMarkIndex(_step),
                          color: fg,
                          dim: fg.withValues(alpha: 0.25),
                          scale: 1.4,
                        ),
                        const SizedBox(height: 26),
                        Text(
                          'SOS',
                          style: TextStyle(
                            color: fg,
                            fontSize: 56,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 10,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: fg.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: lit ? Colors.black : Colors.white,
                      foregroundColor: lit ? Colors.white : Colors.black,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => unawaited(_stopSos()),
                    child: const Text(
                      'Detener SOS',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Si ya te vieron, apagalo: la luz encendida tapa a las personas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Los nueve elementos del SOS (puntos y rayas), con el que está sonando
/// resaltado. En el panel se muestra quieto como vista previa del patrón.
class _MorseStrip extends StatelessWidget {
  const _MorseStrip({this.active, this.color, this.dim, this.scale = 1});

  final int? active;
  final Color? color;
  final Color? dim;
  final double scale;

  /// Punto o raya, en orden: S (tres puntos), O (tres rayas), S (tres puntos).
  static const List<bool> _dots = [
    true,
    true,
    true,
    false,
    false,
    false,
    true,
    true,
    true,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bright = color ?? scheme.primary;
    final faint = dim ?? scheme.outlineVariant;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _dots.length; i++)
          Padding(
            padding: EdgeInsets.only(
              left: i == 0
                  ? 0
                  : (i == 3 || i == 6 ? 10 : 4) * scale,
            ),
            child: Container(
              width: (_dots[i] ? 10 : 28) * scale,
              height: 10 * scale,
              decoration: BoxDecoration(
                color: active == i ? bright : faint,
                borderRadius: BorderRadius.circular(5 * scale),
              ),
            ),
          ),
      ],
    );
  }
}
