import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rescue/light_sampler.dart';
import '../rescue/morse_decoder.dart';
import 'widgets.dart';

/// Recibir morse: apuntar la cámara al destello y leer el mensaje en texto.
///
/// La cámara entrega brillo, no morse: acá se mide cuánto dura cada encendido
/// y cada pausa, y el decodificador arma las letras. Para cuando la cámara no
/// sirve —de noche, muy lejos, o un teléfono sin cámara libre— queda el modo
/// por toques: se toca al ritmo que se ve.
class MorseReceiverPage extends StatefulWidget {
  const MorseReceiverPage({super.key, this.enableCamera = true});

  /// Las pruebas la apagan: sin teléfono no hay cámara que abrir, y el modo
  /// por toques necesita la pantalla igual.
  final bool enableCamera;

  @override
  State<MorseReceiverPage> createState() => _MorseReceiverPageState();
}

class _MorseReceiverPageState extends State<MorseReceiverPage>
    with WidgetsBindingObserver {
  static const Color _night = Color(0xFF05090C);

  /// Cada cuánto se mira un fotograma. A 30 por segundo alcanza para puntos de
  /// 120 ms y no recalienta el teléfono como mirar todos.
  static const int _frameStepMs = 33;

  final MorseDecoder _decoder = MorseDecoder();
  final LightSampler _sampler = LightSampler();
  final Stopwatch _clock = Stopwatch()..start();

  CameraController? _camera;
  late bool _cameraWanted = widget.enableCamera;
  bool _cameraReady = false;
  bool _starting = false;
  String? _cameraError;

  bool _disposed = false;

  int _lastFrameMs = 0;
  int _lastPaintMs = 0;

  /// Último brillo medido, para mostrar que la cámara ve algo.
  double _luma = 0;

  bool _pressing = false;
  int _pressStartMs = 0;
  int? _lastReleaseMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_cameraWanted) unawaited(_startCamera());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    // Sin setState: el árbol ya se está desarmando.
    final controller = _camera;
    _camera = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Con la app de fondo la cámara seguiría encendida y gastando batería.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (_cameraReady) unawaited(_stopCamera());
    } else if (state == AppLifecycleState.resumed &&
        _cameraWanted &&
        !_cameraReady) {
      unawaited(_startCamera());
    }
  }

  Future<void> _startCamera() async {
    if (_starting || _cameraReady) return;
    setState(() {
      _starting = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('este teléfono no reporta cámaras');
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!_cameraWanted) {
        // Apagaron la cámara mientras abría: no se deja encendida.
        await controller.dispose();
        if (mounted && !_disposed) setState(() => _starting = false);
        return;
      }
      await controller.startImageStream(_onFrame);
      if (!mounted || _disposed) {
        await controller.dispose();
        return;
      }
      _sampler.reset();
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _starting = false;
      });
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _starting = false;
        _cameraReady = false;
        _cameraError = _explain(error);
      });
    }
  }

  String _explain(Object error) {
    final text = error.toString();
    if (text.contains('CameraAccessDenied') ||
        text.contains('permission') ||
        text.contains('Permission')) {
      return 'Sin permiso de cámara. Se puede dar desde Ajustes de Android, '
          'o usar el modo por toques.';
    }
    if (text.contains('cameraInUse') || text.contains('en uso')) {
      return 'Otra app está usando la cámara. Cerrá esa app y reintentá, '
          'o usá el modo por toques.';
    }
    return 'La cámara no arrancó: $text. El modo por toques sigue disponible.';
  }

  Future<void> _stopCamera() async {
    final controller = _camera;
    _camera = null;
    if (mounted && !_disposed) setState(() => _cameraReady = false);
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    } catch (_) {
      // La cámara ya estaba cerrada: no hay nada que hacer.
    }
  }

  void _onFrame(CameraImage image) {
    final now = _clock.elapsedMilliseconds;
    if (now - _lastFrameMs < _frameStepMs) return;
    _lastFrameMs = now;

    final luma = _meanLuma(image);
    final change = _sampler.addSample(luma, now);
    final needsPaint = (luma - _luma).abs() > 0.02;
    _luma = luma;

    if (change != null) {
      if (change.on) {
        _decoder.mark(change.ms);
      } else {
        _decoder.gap(change.ms);
      }
      _lastPaintMs = now;
      if (mounted) setState(() {});
    } else if (needsPaint && mounted && now - _lastPaintMs > 100) {
      // La barra de brillo no necesita 30 refrescos por segundo: a diez se ve
      // igual y la cámara no compite con la interfaz por el hilo principal.
      _lastPaintMs = now;
      setState(() {});
    }
  }

  /// Brillo medio del plano de luminancia, muestreado: leer todos los píxeles
  /// de cada fotograma calentaría el teléfono sin ganar precisión.
  double _meanLuma(CameraImage image) {
    if (image.planes.isEmpty) return 0;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 0;
    final step = math.max(1, bytes.length ~/ 800);
    var sum = 0;
    var count = 0;
    for (var i = 0; i < bytes.length; i += step) {
      sum += bytes[i];
      count++;
    }
    return count == 0 ? 0 : (sum / count) / 255.0;
  }

  void _toggleCamera(bool value) {
    setState(() => _cameraWanted = value);
    if (value) {
      _sampler.reset();
      unawaited(_startCamera());
    } else {
      unawaited(_stopCamera());
    }
  }

  void _onPressStart() {
    final now = _clock.elapsedMilliseconds;
    if (_lastReleaseMs != null) {
      final gap = now - _lastReleaseMs!;
      if (gap >= 40) _decoder.gap(gap);
    }
    setState(() {
      _pressing = true;
      _pressStartMs = now;
    });
  }

  void _onPressEnd() {
    final now = _clock.elapsedMilliseconds;
    final ms = now - _pressStartMs;
    if (ms >= 40) _decoder.mark(ms);
    setState(() {
      _pressing = false;
      _lastReleaseMs = now;
    });
  }

  /// Cierra la letra en curso: sin esto, la última letra del mensaje a mano
  /// quedaría sin terminar hasta el próximo toque.
  void _closeLetter({bool word = false}) {
    final unit = _decoder.reading.unitMs ?? 120;
    _decoder.gap(unit * (word ? 7 : 3));
    _lastReleaseMs = null;
    setState(() {});
  }

  void _clear() {
    _decoder.clear();
    _sampler.reset();
    _lastReleaseMs = null;
    setState(() {});
  }

  Future<void> _copy() async {
    final text = _decoder.reading.message;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reading = _decoder.reading;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recibir morse',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _introCard(scheme),
          const SizedBox(height: 12),
          _cameraCard(scheme),
          const SizedBox(height: 12),
          _readingCard(scheme, reading),
          const SizedBox(height: 12),
          _manualCard(scheme),
          const SizedBox(height: 12),
          _limitsCard(scheme),
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

  Widget _introCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.visibility_outlined, 'Leer un destello'),
          const SizedBox(height: 8),
          Text(
            'Apuntá la cámara a la luz que parpadea y dejá el teléfono quieto. '
            'El brillo se convierte en letras acá, sin internet y sin saber '
            'morse.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _cameraCard(ColorScheme scheme) {
    final controller = _camera;
    final preview = controller != null && controller.value.isInitialized
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: _brightnessOverlay(scheme, CameraPreview(controller)),
            ),
          )
        : Container(
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _starting
                ? const CircularProgressIndicator()
                : Text(
                    _cameraError ?? 'Cámara apagada',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
          );

    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _cardTitle(
                  scheme,
                  Icons.photo_camera_outlined,
                  'Cámara',
                ),
              ),
              Switch(value: _cameraWanted, onChanged: _toggleCamera),
            ],
          ),
          const SizedBox(height: 8),
          preview,
          const SizedBox(height: 10),
          _lumaBar(scheme),
          const SizedBox(height: 8),
          Text(
            _cameraError ??
                (_cameraReady
                    ? 'Si el brillo no se mueve, acercate o tapá la luz con la '
                          'mano: la cámara necesita ver el encendido y el '
                          'apagado para medir.'
                    : 'Encendé la cámara para leer.'),
            style: TextStyle(
              fontSize: 12,
              color: _cameraError != null
                  ? scheme.error
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _brightnessOverlay(ColorScheme scheme, Widget child) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _night.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _sampler.isOn ? 'LUZ' : '—',
              style: TextStyle(
                color: _sampler.isOn ? const Color(0xFF16C489) : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _lumaBar(ColorScheme scheme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: _luma.clamp(0.0, 1.0),
        minHeight: 6,
        backgroundColor: scheme.surfaceContainerHighest,
      ),
    );
  }

  Widget _readingCard(ColorScheme scheme, MorseReading reading) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.subtitles_outlined, 'Lo que dice'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 96),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _night,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reading.hasAttention)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Llamada de atención',
                      style: TextStyle(
                        color: const Color(0xFFFFB020),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                SelectableText(
                  reading.message.isEmpty ? '· · ·' : reading.message,
                  style: TextStyle(
                    color: reading.message.isEmpty
                        ? Colors.white38
                        : const Color(0xFF16C489),
                    fontFamily: 'monospace',
                    fontSize: 26,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (reading.pending.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    reading.pending,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontFamily: 'monospace',
                      fontSize: 18,
                      letterSpacing: 3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            reading.marks == 0
                ? 'Todavía no llegó ninguna marca.'
                : '${reading.marks} marcas · ritmo ~${reading.unitMs ?? '?'} ms '
                      'por punto',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: reading.isEmpty ? null : () => unawaited(_copy()),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Copiar'),
              ),
              OutlinedButton.icon(
                onPressed: reading.isEmpty ? null : _clear,
                icon: const Icon(Icons.backspace_outlined, size: 18),
                label: const Text('Borrar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _manualCard(ColorScheme scheme) {
    final unit = _decoder.reading.unitMs ?? 120;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.touch_app_outlined, 'Sin cámara: a mano'),
          const SizedBox(height: 8),
          Text(
            'Mirá la luz y apretá el botón mientras está encendida: suelto '
            'para las pausas. Un toque corto es punto, uno largo es raya. '
            'Pausando un poco más se cierra la letra.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 12),
          Listener(
            onPointerDown: (_) => _onPressStart(),
            onPointerUp: (_) => _onPressEnd(),
            onPointerCancel: (_) => _onPressEnd(),
            child: Container(
              height: 96,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _pressing ? const Color(0xFF16C489) : _night,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.light_mode,
                    color: _pressing ? Colors.black : Colors.white54,
                    size: 28,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _pressing ? '...' : 'Mantené apretado con la luz',
                    style: TextStyle(
                      color: _pressing ? Colors.black : Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => _closeLetter(),
                child: const Text('Cerrar letra'),
              ),
              OutlinedButton(
                onPressed: () => _closeLetter(word: true),
                child: const Text('Nueva palabra'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ritmo de referencia: $unit ms por punto.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _limitsCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'La cámara necesita ver el encendido y el apagado. Si la luz '
              'llena todo el cuadro, alejate un poco; si es de noche y el '
              'fondo es negro, apuntá a que la luz ocupe la mitad. Un mensaje '
              'hecho solo de rayas (T, M, O) se lee como puntos: sin un punto '
              'no hay con qué medir el ritmo.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
