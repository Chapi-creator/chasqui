import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../rescue/light_ack.dart';
import '../rescue/light_calibration.dart';
import '../rescue/light_sampler.dart';
import '../rescue/morse_log.dart';
import '../rescue/sample_cadence.dart';
import '../rescue/morse_decoder.dart';
import 'widgets.dart';

/// Recibir morse: apuntar la cámara al destello y leer el mensaje en texto.
///
/// La cámara entrega brillo, no morse: acá se mide cuánto dura cada encendido
/// y cada pausa, y el decodificador arma las letras. Para cuando la cámara no
/// sirve —de noche, muy lejos, o un teléfono sin cámara libre— queda el modo
/// por toques: se toca al ritmo que se ve.
class MorseReceiverPage extends StatefulWidget {
  const MorseReceiverPage({
    super.key,
    this.enableCamera = true,
    this.calibration,
    this.onCalibrationChanged,
    this.history = const <MorseLogEntry>[],
    this.onSaveToHistory,
    this.onClearHistory,
    this.onSendToChat,
  });

  /// Las pruebas la apagan: sin teléfono no hay cámara que abrir, y el modo
  /// por toques necesita la pantalla igual.
  final bool enableCamera;

  /// Umbrales medidos en el lugar, si los hay. Llegan desde el estado de la
  /// app para que sobrevivan al cierre.
  final LightCalibration? calibration;

  /// Se llama al calibrar (o al quitar la calibración, con null). La pantalla
  /// no guarda nada por su cuenta: el estado es de la app.
  final ValueChanged<LightCalibration?>? onCalibrationChanged;

  /// Mensajes ya leídos, del más nuevo al más viejo.
  final List<MorseLogEntry> history;

  /// Guarda un mensaje terminado. El historial vive en el estado de la app.
  final ValueChanged<MorseLogEntry>? onSaveToHistory;

  final VoidCallback? onClearHistory;

  /// Manda el texto al canal de la malla ("todos"). Null si no hay malla.
  final Future<void> Function(String text)? onSendToChat;

  @override
  State<MorseReceiverPage> createState() => _MorseReceiverPageState();
}

class _MorseReceiverPageState extends State<MorseReceiverPage>
    with WidgetsBindingObserver {
  static const Color _night = Color(0xFF05090C);

  /// Cada cuánto se mira un fotograma. A 30 por segundo alcanza para puntos de
  /// 120 ms; cuando no hay nada que leer baja a 20 y vuelve al primer destello.
  final SampleCadence _cadence = SampleCadence();

  final MorseDecoder _decoder = MorseDecoder();
  final LightSampler _sampler = LightSampler();
  final Stopwatch _clock = Stopwatch()..start();

  CameraController? _camera;
  late bool _cameraWanted = widget.enableCamera;
  bool _cameraReady = false;
  bool _starting = false;
  String? _cameraError;

  bool _disposed = false;

  /// Mientras se calibra, el detector queda en pausa: los dos segundos con la
  /// luz encendida se leerían como una raya eterna y ensuciarían el mensaje.
  bool _calibrating = false;

  /// Último brillo, para que la hoja de calibración lo muestre en vivo.
  final ValueNotifier<double> _lumaNotifier = ValueNotifier<double>(0);

  /// Lo usa la hoja de calibración para recibir cada fotograma.
  void Function(double luma)? _calibrationCollector;

  int _lastFrameMs = 0;
  int _lastPaintMs = 0;

  /// Último brillo medido, para mostrar que la cámara ve algo.
  double _luma = 0;

  /// Evita guardar dos veces el mismo mensaje: el silencio vuelve a pasar por
  /// acá cada 300 ms mientras la pantalla siga abierta.
  bool _loggedThisMessage = false;

  /// Confirmación por linterna: activa por defecto y una sola vez por mensaje.
  bool _confirmWithLight = true;
  bool _ackedThisMessage = false;
  bool _torchFailed = false;

  /// Mientras la linterna de la confirmación está encendida, sus propios
  /// destellos entrarían por la cámara como si fueran un mensaje.
  bool _acking = false;

  bool _pressing = false;
  int _pressStartMs = 0;
  int? _lastReleaseMs;

  /// Cuándo se cerró el último tramo. Sirve para saber si el silencio ya es tan
  /// largo que la letra en curso terminó.
  int _lastChangeMs = 0;
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    _sampler.setCalibration(widget.calibration);
    WidgetsBinding.instance.addObserver(this);
    _silenceTimer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => _checkSilence(),
    );
    if (_cameraWanted) unawaited(_startCamera());
  }

  @override
  void dispose() {
    _disposed = true;
    _calibrationCollector = null;
    _lumaNotifier.dispose();
    _silenceTimer?.cancel();
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
      _cadence.start(_clock.elapsedMilliseconds);
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
    if (now - _lastFrameMs < _cadence.stepMs(now)) return;
    _lastFrameMs = now;

    final luma = _meanLuma(image);
    final needsPaint = (luma - _luma).abs() > 0.02;
    _luma = luma;
    _lumaNotifier.value = luma;
    _calibrationCollector?.call(luma);
    if (_calibrating || _acking) return;
    _cadence.observeLuma(luma, now, _sampler.calibration);
    final change = _sampler.addSample(luma, now);

    if (change != null) {
      _lastChangeMs = now;
      _cadence.noteActivity(now);
      if (change.on) {
        _decoder.mark(change.ms);
        // Empieza otro mensaje: lo que venga se vuelve a guardar y a confirmar.
        _loggedThisMessage = false;
        _ackedThisMessage = false;
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

  /// Brillo de "lo más claro" del recuadro central, entre 0 y 1.
  ///
  /// Promediar todo el fotograma era el error de fondo: a unos metros la
  /// linterna ocupa una parte chica y su encendido se diluye en el fondo, así
  /// que la cámara "no veía" nada. Tampoco alcanza con mirar solo algunos
  /// píxeles del recuadro: una luz lejana son unos pocos y la rejilla podía
  /// saltearlos, con lo cual el brillo saltaba entre "luz" y "fondo".
  ///
  /// Por eso se leen **todos** los píxeles del recuadro (unos 20 000 a la
  /// resolución baja) y se promedia el 1 % más claro: si la linterna está
  /// encendida, esos son sus píxeles; si está apagada, el fondo.
  double _meanLuma(CameraImage image) {
    if (image.planes.isEmpty) return 0;
    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 0;

    final width = image.width;
    final height = image.height;
    final stride = plane.bytesPerRow;
    if (width <= 0 || height <= 0 || stride <= 0) return 0;

    final x0 = (width * 0.25).round();
    final x1 = (width * 0.75).round();
    final y0 = (height * 0.25).round();
    final y1 = (height * 0.75).round();

    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var y = y0; y < y1; y++) {
      final row = y * stride;
      for (var x = x0; x < x1; x++) {
        final index = row + x;
        if (index >= bytes.length) break;
        histogram[bytes[index]]++;
        count++;
      }
    }
    if (count == 0) return 0;

    // El 1 % más claro, con un mínimo de 16 píxeles para que el ruido de un
    // recuadro casi negro no mande.
    final wanted = math.max(16, (count * 0.01).round());
    var seen = 0;
    var sum = 0;
    for (var level = 255; level >= 0 && seen < wanted; level--) {
      final hits = histogram[level];
      if (hits == 0) continue;
      final take = math.min(hits, wanted - seen);
      sum += level * take;
      seen += take;
    }
    return seen == 0 ? 0 : (sum / seen) / 255.0;
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
    _lastChangeMs = now;
    _cadence.noteActivity(now);
    _loggedThisMessage = false;
    _ackedThisMessage = false;
    setState(() {
      _pressing = true;
      _pressStartMs = now;
    });
  }

  void _onPressEnd() {
    final now = _clock.elapsedMilliseconds;
    final ms = now - _pressStartMs;
    if (ms >= 40) _decoder.mark(ms);
    _lastChangeMs = now;
    setState(() {
      _pressing = false;
      _lastReleaseMs = now;
    });
  }

  /// Cierra la letra cuando el silencio ya dura más que una pausa de letra.
  /// Sólo mira; no toca nada si la luz sigue encendida o no hay nada abierto.
  void _checkSilence() {
    if (_disposed || !mounted || _calibrating || _acking) return;
    if (_sampler.isOn || _pressing) return;
    final now = _clock.elapsedMilliseconds;
    final silence = now - _lastChangeMs;
    final reading = _decoder.reading;

    if (reading.pending.isNotEmpty) {
      final unit = reading.unitMs ?? 200;
      final threshold = math.max(900, (unit * 4.6).round());
      if (silence < threshold) return;
      _decoder.closeLetter();
      _saveReading();
      setState(() {});
      // La confirmación sale en el siguiente paso, con más silencio encima.
      return;
    }

    if (!_confirmWithLight) return;
    if (!ackDue(
      hasText: reading.text.trim().isNotEmpty,
      alreadyAcked: _ackedThisMessage,
      lightOn: _sampler.isOn,
      silenceMs: silence,
    )) {
      return;
    }
    _ackedThisMessage = true;
    unawaited(_flashAck());
  }

  /// Dos destellos cortos con la linterna de la cámara. Si el teléfono no tiene
  /// linterna o la tiene ocupada, se avisa y no se reintenta en cada mensaje.
  Future<void> _flashAck() async {
    final controller = _camera;
    if (controller == null || !_cameraReady || _torchFailed) return;
    _acking = true;
    var failed = false;
    try {
      for (var i = 0; i < ackPulses; i++) {
        // Si cierran la pantalla a mitad de la confirmación, se corta acá; el
        // finally se encarga de que la linterna no quede prendida.
        if (_disposed || !mounted) break;
        await controller.setFlashMode(FlashMode.torch);
        await Future<void>.delayed(const Duration(milliseconds: ackPulseMs));
        if (_disposed || !mounted) break;
        await controller.setFlashMode(FlashMode.off);
        if (i < ackPulses - 1) {
          await Future<void>.delayed(const Duration(milliseconds: ackGapMs));
        }
      }
    } catch (error) {
      failed = true;
      debugPrint('La linterna no respondió ($error)');
    } finally {
      // Apagado de cierre: un `break` o una excepción no pueden dejar la
      // linterna encendida comiéndose la batería.
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        // La cámara ya no está: no hay nada que apagar.
      }
      // Solo cuenta como "sin linterna" si el teléfono sigue siendo el mismo;
      // si falló porque la cámara se estaba cerrando, no es culpa del equipo.
      if (failed && _camera == controller) _torchFailed = true;
      _acking = false;
      // Lo que la linterna propia iluminó no era un mensaje.
      _sampler.reset();
      _lastChangeMs = _clock.elapsedMilliseconds;
      _cadence.noteActivity(_lastChangeMs);
      if (mounted && !_disposed) setState(() {});
    }
  }

  /// Guarda el mensaje terminado en el historial. Sin [announce] no muestra
  /// aviso: el guardado automático no tiene que interrumpir cada mensaje.
  void _saveReading({bool announce = false}) {
    if (_loggedThisMessage) return;
    final reading = _decoder.reading;
    final text = reading.text.trim();
    if (text.isEmpty) return;
    _loggedThisMessage = true;
    widget.onSaveToHistory?.call(
      MorseLogEntry(
        text: text,
        at: DateTime.now(),
        marks: reading.marks,
        unitMs: reading.unitMs,
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (announce) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Guardado en el historial')),
      );
    }
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
    _loggedThisMessage = false;
    _ackedThisMessage = false;
    setState(() {});
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mensaje copiado')));
  }

  Future<void> _sendToChat(MorseLogEntry entry) async {
    final send = widget.onSendToChat;
    if (send == null) return;
    await send(entry.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Enviado al canal')));
  }

  Future<void> _copy() => _copyText(_decoder.reading.text);

  /// Mide dos segundos con la luz apagada y dos con la luz encendida y guarda
  /// los umbrales. Es lo que evita el "no me lee" que en realidad es la
  /// cámara exponiendo distinto en cada lugar.
  Future<void> _openCalibration() async {
    if (!_cameraReady || _calibrating) return;
    setState(() => _calibrating = true);
    final result = await showModalBottomSheet<LightCalibration>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CalibrationSheet(
        luma: _lumaNotifier,
        register: (listener) => _calibrationCollector = listener,
      ),
    );
    _calibrationCollector = null;
    if (_disposed || !mounted) return;
    setState(() => _calibrating = false);
    // Lo que se veía durante la calibración no era un mensaje: se descarta.
    _sampler.reset();
    _cadence.noteActivity(_clock.elapsedMilliseconds);
    _decoder.clear();
    if (result == null) return;
    _sampler.setCalibration(result);
    widget.onCalibrationChanged?.call(result);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Umbrales guardados para este lugar')),
    );
  }

  void _clearCalibration() {
    _sampler.setCalibration(null);
    widget.onCalibrationChanged?.call(null);
    setState(() {});
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
          _historyCard(scheme),
          const SizedBox(height: 12),
          _ackCard(scheme),
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
            'Apuntá la cámara a la luz que parpadea, con la luz dentro del '
            'recuadro, y dejá el teléfono quieto. El brillo se convierte en '
            'letras acá, sin internet y sin saber morse.',
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
            _cameraError ?? _hintText(),
            style: TextStyle(
              fontSize: 12,
              color: _cameraError != null
                  ? scheme.error
                  : (_cameraReady &&
                            _sampler.calibration == null &&
                            !_sampler.hasSignal
                        ? const Color(0xFFB26A00)
                        : scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _cameraReady && !_calibrating
                    ? _openCalibration
                    : null,
                icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
                label: Text(
                  _sampler.calibration == null ? 'Calibrar' : 'Repetir',
                ),
              ),
              if (_sampler.calibration != null)
                TextButton(
                  onPressed: _clearCalibration,
                  child: const Text('Quitar calibración'),
                ),
            ],
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
        // El recuadro marca lo que se mide: solo el centro del cuadro. El
        // fondo de alrededor suele ser más grande que la luz y arruinaba la
        // lectura cuando se promediaba todo.
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _sampler.hasSignal
                        ? const Color(0xFF16C489)
                        : Colors.white54,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
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
              _sampler.isOn ? 'LUZ' : (_sampler.hasSignal ? '—' : 'sin señal'),
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

  /// Qué decirle al usuario sobre lo que ve la cámara. Con calibración el
  /// mensaje cambia: ya no hay que explicar el contraste, hay que confirmar
  /// que los umbrales de este lugar están puestos.
  String _hintText() {
    if (!_cameraReady) return 'Encendé la cámara para leer.';
    final calibration = _sampler.calibration;
    if (calibration != null) {
      final dark = (calibration.dark * 100).round();
      final bright = (calibration.bright * 100).round();
      return 'Calibrado para este lugar: fondo $dark % y luz $bright %. '
          'Si cambiás de lugar o de linterna, volvé a calibrar.';
    }
    if (!_sampler.hasSignal) {
      return 'La cámara no ve contraste: acercate, apuntá al recuadro o tapá '
          'la luz con la mano para que vea también el apagado. Si igual no '
          'lee, tocá Calibrar.';
    }
    return 'Poné la luz dentro del recuadro y dejá el teléfono quieto.';
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
                SelectableText(
                  reading.text.isEmpty ? '· · ·' : reading.text,
                  style: TextStyle(
                    color: reading.text.isEmpty
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
          // A 120 ms por punto la información existe en la imagen solo si la
          // cámara entrega 30 fotogramas por segundo. Con menos, o con
          // exposición lenta, hay puntos y pausas que no llegan a verse y dos
          // puntos se pegan en una raya: no es que la traducción falle, es que
          // falta el dato. Medido en simulación: a 200 ms no falla ninguna
          // lectura con 15 por segundo; a 120 empieza a fallar por debajo de 20.
          if ((reading.unitMs ?? 999) <= 140) ...[
            const SizedBox(height: 6),
            Text(
              'Va rápido. Si alguna letra sale cambiada, no es el mensaje: con '
              'cámara lenta se pierden puntos. Pedí que manden a 200 ms.',
              style: TextStyle(fontSize: 12, color: scheme.tertiary),
            ),
          ],
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
                onPressed: reading.isEmpty || _loggedThisMessage
                    ? null
                    : () => _saveReading(announce: true),
                icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                label: const Text('Guardar'),
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

  /// Historial de lo leído: sin esto el mensaje se iba con la pantalla.
  Widget _historyCard(ColorScheme scheme) {
    final history = widget.history;
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(scheme, Icons.history, 'Lo que ya leíste'),
          const SizedBox(height: 8),
          if (history.isEmpty)
            Text(
              'Acá quedan los mensajes cuando el silencio cierra el último. '
              'Se pueden copiar o mandar al canal de la malla.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            )
          else ...[
            for (final entry in history.take(5)) _historyRow(scheme, entry),
            if (history.length > 5)
              Text(
                'y ${history.length - 5} más guardados.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            if (widget.onClearHistory != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    widget.onClearHistory!();
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Borrar historial'),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _historyRow(ColorScheme scheme, MorseLogEntry entry) {
    final unit = entry.unitMs;
    final details = unit == null
        ? '${entry.whenLabel} · ${entry.marks} marcas'
        : '${entry.whenLabel} · ${entry.marks} marcas · ~$unit ms por punto';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  details,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar',
            onPressed: () => unawaited(_copyText(entry.text)),
            icon: const Icon(Icons.copy_outlined, size: 18),
          ),
          if (widget.onSendToChat != null)
            IconButton(
              tooltip: 'Mandar al canal',
              onPressed: () => unawaited(_sendToChat(entry)),
              icon: const Icon(Icons.send_outlined, size: 18),
            ),
        ],
      ),
    );
  }

  /// La confirmación por luz: el que transmite puede estar lejos y no ver la
  /// pantalla, así que el receptor le contesta con la linterna.
  Widget _ackCard(ColorScheme scheme) {
    return InfoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _cardTitle(
                  scheme,
                  Icons.flashlight_on_outlined,
                  'Confirmar la recepción',
                ),
              ),
              Switch(
                value: _confirmWithLight,
                onChanged: (value) =>
                    setState(() => _confirmWithLight = value),
              ),
            ],
          ),
          Text(
            'Cuando el mensaje termina, el teléfono contesta con dos destellos '
            'cortos para que el que transmite sepa que llegó sin acercarse. '
            'Necesita la cámara encendida y usa la linterna, así que gasta '
            'batería.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
          ),
          if (_torchFailed) ...[
            const SizedBox(height: 8),
            Text(
              'Este teléfono no respondió a la linterna. La confirmación queda '
              'apagada; el mensaje se lee igual.',
              style: TextStyle(fontSize: 12, color: scheme.error),
            ),
          ],
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
              'La app mide la parte más clara del recuadro: la luz tiene que '
              'entrar ahí, aunque sea chica. Si el fondo también es muy claro, '
              'tapalo o cambiate de lugar. Sin destellos la cámara mira menos '
              'fotogramas para gastar menos batería, y vuelve al ritmo normal '
              'apenas ve luz. Un mensaje '
              'de una sola raya (T) puede leerse como punto (E): no hay otra '
              'marca con la cual comparar el ritmo.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Medición guiada en dos pasos: primero el fondo con la luz apagada y después
/// la luz encendida. Cada paso dura [stepDuration] y usa la mediana, así un
/// reflejo o el momento en que la cámara ajusta la exposición no mueven el
/// resultado.
class _CalibrationSheet extends StatefulWidget {
  const _CalibrationSheet({required this.luma, required this.register});

  /// Brillo en vivo, el mismo que mide el receptor.
  final ValueListenable<double> luma;

  /// El receptor entrega su colector: la hoja recibe un fotograma por muestra.
  final void Function(void Function(double luma)?) register;

  @override
  State<_CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<_CalibrationSheet> {
  static const Duration stepDuration = Duration(seconds: 2);

  /// 0 = medir el fondo, 1 = medir la luz, 2 = listo.
  int _step = 0;
  bool _measuring = false;
  bool _failed = false;
  double? _dark;
  final List<double> _samples = <double>[];
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.register(_collect);
  }

  @override
  void dispose() {
    widget.register(null);
    _ticker?.cancel();
    super.dispose();
  }

  void _collect(double luma) {
    if (!_measuring) return;
    _samples.add(luma);
  }

  void _measure() {
    setState(() {
      _samples.clear();
      _failed = false;
      _measuring = true;
      _clock
        ..reset()
        ..start();
      _ticker?.cancel();
      _ticker = Timer.periodic(
        const Duration(milliseconds: 80),
        (_) => _tick(),
      );
    });
  }

  void _tick() {
    if (!mounted) return;
    if (_clock.elapsed < stepDuration) {
      setState(() {});
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    _measuring = false;
    _finishStep();
  }

  void _finishStep() {
    if (_samples.length < LightCalibration.minSamples) {
      setState(() => _failed = true);
      return;
    }
    final level = LightCalibration.median(_samples);
    if (_step == 0) {
      setState(() {
        _dark = level;
        _step = 1;
      });
      return;
    }
    final calibration = LightCalibration(dark: _dark!, bright: level);
    if (!calibration.isUsable) {
      setState(() => _failed = true);
      return;
    }
    Navigator.of(context).pop(calibration);
  }

  void _retry() {
    setState(() {
      _step = 0;
      _dark = null;
      _failed = false;
      _measuring = false;
      _samples.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = _measuring
        ? (_clock.elapsedMilliseconds / stepDuration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.center_focus_strong_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Calibrar el receptor',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _step == 0
                  ? 'Paso 1 de 2: apuntá la cámara al fondo con la luz '
                        'apagada, como quedaría entre destello y destello.'
                  : 'Paso 2 de 2: prendé la luz y apuntala al recuadro, a la '
                        'distancia a la que la vas a usar.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 14),
            ValueListenableBuilder<double>(
              valueListenable: widget.luma,
              builder: (context, luma, _) {
                final shown = _measuring
                    ? _liveLevel()
                    : (_step == 1 ? _dark ?? 0 : luma);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: shown.clamp(0.0, 1.0),
                        minHeight: 12,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Brillo medido: ${(shown * 100).round()} %',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            if (_measuring) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Midiendo… dejá el teléfono quieto.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ] else if (_failed) ...[
              Text(
                _samples.isEmpty
                    ? 'No llegaron fotogramas de la cámara. Cerrá y volvé a '
                          'intentar con la cámara encendida.'
                    : 'La diferencia entre el fondo y la luz es demasiado '
                          'chica. Acercate, tapá el fondo o probá con menos '
                          'luz ambiente.',
                style: TextStyle(color: scheme.error, height: 1.4),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _retry,
                child: const Text('Reintentar'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _measure,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _step == 0 ? 'Medir el fondo' : 'Medir la luz',
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Se guardan dos umbrales para este teléfono. Si cambiás de '
              'lugar o de linterna, se repite.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Lo último que se midió, para que la barra no salte con el ruido.
  double _liveLevel() {
    if (_samples.isEmpty) return 0;
    return _samples.last;
  }
}
