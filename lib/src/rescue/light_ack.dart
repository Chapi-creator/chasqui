// Confirmación por linterna: cuando el receptor termina de leer, contesta con
// dos destellos cortos para que el que transmite sepa que llegó sin acercarse.
//
// El destello se manda recién después de un silencio largo, no apenas termina
// la última letra: si saliera antes, el que transmite todavía podría estar
// mirando y confundirlo con otra marca del mensaje. Dos segundos son más que
// la pausa de fin de palabra, así que no hay ambigüedad.

/// Silencio mínimo antes de contestar.
const int ackSilenceMs = 2000;

/// Cantidad de destellos de la confirmación.
const int ackPulses = 2;

/// Duración de cada destello.
const int ackPulseMs = 120;

/// Pausa entre los dos destellos.
const int ackGapMs = 140;

/// Decide si corresponde contestar.
///
/// Fuera de la pantalla para poder probarlo: con cámara real no hay forma de
/// verificar los tiempos sin un teléfono.
bool ackDue({
  required bool hasText,
  required bool alreadyAcked,
  required bool lightOn,
  required int silenceMs,
}) {
  if (!hasText || alreadyAcked || lightOn) return false;
  return silenceMs >= ackSilenceMs;
}
