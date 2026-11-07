/// Modo de radio elegido por el usuario.
enum RadioMode {
  supervivencia(
    'Máxima batería',
    'Escucha 4 s cada 5 min, en el mismo instante que los demás teléfonos. '
        'Días de malla con una carga; los mensajes pueden tardar hasta 5 min.',
  ),
  ahorro(
    'Ahorro',
    'Escucha 3 s cada 2 min y suelta los enlaces que no tienen tráfico. '
        'Mensajes con minutos de retraso, mucha menos batería.',
  ),
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

  /// Nunca se reabre una ventana antes de esto: si no, al cerrar una justo
  /// antes de la frontera se encadenaban dos seguidas.
  static const Duration minRest = Duration(seconds: 2);

  /// Cuánto falta para la próxima ventana, alineada con el reloj de pared.
  ///
  /// Todas las copias de la app calculan **las mismas fronteras** (múltiplos
  /// de [interval] contados desde la época Unix), así que dos teléfonos que
  /// nunca se han visto abren su ventana en el mismo instante. Antes cada
  /// teléfono llevaba su propia fase desde que arrancaba: dos vecinos podían
  /// escuchar en momentos distintos **para siempre** y no encontrarse nunca,
  /// aunque los dos escucharan. Con la fase común se puede dormir más rato sin
  /// perder encuentros, que es justo lo que gasta batería.
  ///
  /// Depende de que la hora del teléfono sea más o menos correcta: la hora del
  /// sistema se conserva sin red, y desfases de segundos caben dentro de la
  /// ventana.
  Duration delayUntilNextWindow(DateTime now) {
    final period = interval.inMilliseconds;
    if (period <= 0) return Duration.zero;
    final remainder = now.millisecondsSinceEpoch % period;
    var wait = remainder == 0 ? period : period - remainder;
    if (wait < minRest.inMilliseconds) wait += period;
    return Duration(milliseconds: wait);
  }

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
      RadioMode.supervivencia => const Duration(seconds: 4),
      RadioMode.ahorro => const Duration(seconds: 3),
      RadioMode.equilibrado => const Duration(seconds: 4),
      RadioMode.rapido => const Duration(seconds: 5),
    };
    var interval = switch (mode) {
      RadioMode.supervivencia => const Duration(minutes: 5),
      RadioMode.ahorro => const Duration(seconds: 120),
      RadioMode.equilibrado => const Duration(seconds: 45),
      RadioMode.rapido => const Duration(seconds: 20),
    };

    // Batería al 5 % o menos: se pasa a la rejilla de 5 minutos sin importar
    // el modo elegido. La alternativa es un teléfono muerto, que no es malla.
    if (!charging && batteryLevel <= 5) {
      return const ScanPlan(Duration(seconds: 4), Duration(minutes: 5));
    }

    if (charging) {
      window = const Duration(seconds: 6);
      interval = const Duration(seconds: 15);
    } else {
      // Sin descubrimientos recientes: espaciar (máx. 2^5 = 32x).
      final factor = 1 << emptyStreak.clamp(0, 5);
      interval = Duration(
        milliseconds: (interval.inMilliseconds * factor).clamp(
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
