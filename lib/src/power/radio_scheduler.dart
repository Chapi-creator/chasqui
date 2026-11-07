import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

import 'power_policy.dart';

/// Enciende y apaga el escáner BLE siguiendo [PowerPolicy].
///
/// La radio no escucha 24/7: abre ventanas cortas y las espacia cuando no hay
/// nadie cerca. Eso es lo que evita que la app se coma la batería como una
/// radio encendida permanentemente.
class RadioScheduler extends ChangeNotifier {
  RadioScheduler({
    required this.onScanGate,
    this.enableBatteryMonitor = true,
    this.policy = const PowerPolicy(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Callback hacia el transporte: true = escanear, false = descansar.
  final void Function(bool enabled) onScanGate;
  final bool enableBatteryMonitor;
  final PowerPolicy policy;

  /// Reloj inyectable: las ventanas se alinean con la hora del teléfono y los
  /// tests necesitan controlarla.
  final DateTime Function() _now;

  RadioMode _mode = RadioMode.equilibrado;
  int _batteryLevel = 100;
  bool _charging = false;
  int _emptyStreak = 0;
  bool _hasLinks = false;
  bool _scanning = false;
  bool _running = false;
  bool _foundThisWindow = false;
  bool _alwaysListen = false;

  Timer? _windowTimer;
  Timer? _cycleTimer;
  Timer? _batteryTimer;
  ScanPlan _currentPlan = const ScanPlan(
    Duration(seconds: 4),
    Duration(seconds: 45),
  );

  RadioMode get mode => _mode;
  int get batteryLevel => _batteryLevel;
  bool get charging => _charging;
  bool get scanning => _scanning;
  bool get running => _running;
  ScanPlan get plan => _currentPlan;
  int get emptyStreak => _emptyStreak;

  static final Battery _battery = Battery();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    if (enableBatteryMonitor) {
      await _refreshBattery();
      // Cada 5 min basta: el nivel no cambia más rápido y cada consulta
      // cruza al lado nativo.
      _batteryTimer = Timer.periodic(
        const Duration(minutes: 5),
        (_) => _refreshBattery(),
      );
    }
    _restartCycle();
  }

  void stop() {
    _running = false;
    _windowTimer?.cancel();
    _cycleTimer?.cancel();
    _batteryTimer?.cancel();
    _windowTimer = null;
    _cycleTimer = null;
    _batteryTimer = null;
    _scanning = false;
    onScanGate(false);
    notifyListeners();
  }

  void setMode(RadioMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _emptyStreak = 0;
    notifyListeners();
    if (_running) _restartCycle();
  }

  void setHasLinks(bool value) {
    if (_hasLinks == value) return;
    _hasLinks = value;
    notifyListeners();
    if (_running) _restartCycle();
  }

  /// Llamado cuando aparece (o desaparece) un nodo: ajusta el backoff.
  ///
  /// Importante: no reinicia la ventana en curso. Las presencias llegan en
  /// ráfaga por todos los enlaces, y reiniciar el temporizador con cada una
  /// dejaba el escáner encendido de forma indefinida (justo lo que la
  /// política de batería intenta evitar).
  void onScanResult({required bool found}) {
    if (found) {
      _foundThisWindow = true;
      final streak = 0;
      if (streak == _emptyStreak) return;
      _emptyStreak = streak;
      if (_running && !_scanning) _restartCycle();
      return;
    }
    final streak = (_emptyStreak + 1).clamp(0, 5);
    if (streak == _emptyStreak) return;
    _emptyStreak = streak;
    if (_running && !_scanning) _restartCycle();
  }

  /// Modo repetidor: escucha casi todo el tiempo en lugar de abrir ventanas
  /// cortas. Es lo que convierte a un teléfono viejo enchufado en la ventana
  /// en un repetidor de barrio, a costa de batería.
  void setAlwaysListen(bool value) {
    if (_alwaysListen == value) return;
    _alwaysListen = value;
    notifyListeners();
    if (_running) _restartCycle();
  }

  bool get alwaysListen => _alwaysListen;

  ScanPlan get _computePlan => _alwaysListen
      ? const ScanPlan(Duration(seconds: 8), Duration(seconds: 10))
      : policy.plan(
          mode: _mode,
          batteryLevel: _batteryLevel,
          charging: _charging,
          emptyStreak: _emptyStreak,
          hasLinks: _hasLinks,
        );

  void _restartCycle() {
    _windowTimer?.cancel();
    _cycleTimer?.cancel();
    final plan = _computePlan;
    _currentPlan = plan;
    _foundThisWindow = false;

    _scanning = true;
    onScanGate(true);
    notifyListeners();

    _windowTimer = Timer(plan.window, () {
      if (!_running) return;
      _scanning = false;
      onScanGate(false);
      // Nadie avisaba de las búsquedas sin resultados, así que el backoff
      // "sin nodos cerca" nunca se aplicaba y la radio escaneaba siempre al
      // mismo ritmo. Aquí se detecta solo: ventana cerrada sin ver a nadie.
      if (!_foundThisWindow) {
        _emptyStreak = (_emptyStreak + 1).clamp(0, 5);
      }
      _foundThisWindow = false;
      // Se descansa lo que marque el plan nuevo (con el backoff aplicado),
      // no el que tenía la ventana que acaba de cerrarse.
      final next = _computePlan;
      _currentPlan = next;
      notifyListeners();
      // Descanso hasta la próxima frontera del reloj, no "intervalo menos
      // ventana": así todos los teléfonos despiertan a la vez. Como la ventana
      // anterior empezó en una frontera, en régimen normal esto equivale a
      // intervalo − ventana; solo la primera ventana queda libre de fase.
      final rest = next.delayUntilNextWindow(_now());
      _cycleTimer = Timer(rest.isNegative ? Duration.zero : rest, () {
        if (_running) _restartCycle();
      });
    });
  }

  Future<void> _refreshBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final changed =
          level != _batteryLevel ||
          (state == BatteryState.charging) != _charging;
      _batteryLevel = level;
      _charging = state == BatteryState.charging || state == BatteryState.full;
      if (changed) {
        notifyListeners();
        if (_running) _restartCycle();
      }
    } catch (error) {
      // Escritorio o emulador sin batería real: seguimos con valores por defecto.
      debugPrint('Scheduler: batería no disponible ($error)');
    }
  }

  @override
  void dispose() {
    _running = false;
    _windowTimer?.cancel();
    _cycleTimer?.cancel();
    _batteryTimer?.cancel();
    super.dispose();
  }
}
