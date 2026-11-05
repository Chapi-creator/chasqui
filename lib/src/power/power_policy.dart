/// Modo de radio elegido por el usuario.
enum RadioMode {
  ahorro('Ahorro máximo', 'Escucha en ventanas cortas y espaciadas.'),
  equilibrado('Equilibrado', 'Buen alcance con consumo moderado.'),
  rapido('Rápido', 'Descubre nodos casi al instante. Gasta más batería.');

  const RadioMode(this.label, this.description);
  final String label;
  final String description;

  static RadioMode fromName(String? name) => RadioMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => RadioMode.equilibrado,
      );
}

/// Ventana de escucha y periodo entre ventanas.
class ScanPlan {
  const ScanPlan(this.window, this.interval);

  final Duration window;
  final Duration interval;

  /// Porcentaje de tiempo con el escáner BLE encendido.
  double get dutyCycle =>
      (window.inMilliseconds / interval.inMilliseconds).clamp(0.0, 1.0);

  @override
  String toString() =>
      'escucha ${window.inSeconds}s cada ${(interval.inSeconds)}s '
      '(${(dutyCycle * 100).toStringAsFixed(1)}%)';
}

/// Calcula cuánto tiempo escuchar según batería, modo y estado de la malla.
///
/// Todo el gasto de una malla BLE está en el escaneo; el advertising es
/// prácticamente gratis. Por eso la política solo apaga/enciende el escáner.
class PowerPolicy {
  const PowerPolicy();

  static const Duration _minInterval = Duration(seconds: 10);
  static const Duration _maxInterval = Duration(minutes: 5);

  ScanPlan plan({
    required RadioMode mode,
    required int batteryLevel,
    required bool charging,
    required int emptyStreak,
    required bool hasLinks,
  }) {
    var window = switch (mode) {
      RadioMode.ahorro => const Duration(seconds: 3),
      RadioMode.equilibrado => const Duration(seconds: 4),
      RadioMode.rapido => const Duration(seconds: 5),
    };
    var interval = switch (mode) {
      RadioMode.ahorro => const Duration(seconds: 120),
      RadioMode.equilibrado => const Duration(seconds: 45),
      RadioMode.rapido => const Duration(seconds: 20),
    };

    if (charging) {
      window = const Duration(seconds: 6);
      interval = const Duration(seconds: 15);
    } else {
      // Sin descubrimientos recientes: espaciar (máx. 2^5 = 32x).
      final factor = 1 << emptyStreak.clamp(0, 5);
      interval = Duration(
        milliseconds:
            (interval.inMilliseconds * factor).clamp(
          _minInterval.inMilliseconds,
          _maxInterval.inMilliseconds,
        ),
      );

      if (batteryLevel <= 15) {
        window = const Duration(seconds: 2);
        interval = Duration(
          milliseconds: (interval.inMilliseconds * 2).clamp(
            _minInterval.inMilliseconds,
            _maxInterval.inMilliseconds,
          ),
        );
      }
    }

    // Si ya hay enlaces, solo escaneamos de vez en cuando para admitir nodos
    // nuevos: el tráfico existente ya fluye por las conexiones abiertas.
    if (hasLinks && !charging) {
      window = Duration(seconds: window.inSeconds.clamp(2, 3));
      interval = Duration(
        milliseconds: (interval.inMilliseconds * 2).clamp(
          _minInterval.inMilliseconds,
          _maxInterval.inMilliseconds,
        ),
      );
    }

    return ScanPlan(window, interval);
  }
}
