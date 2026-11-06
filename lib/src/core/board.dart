import 'models.dart';

/// Categorías del tablero de emergencia.
///
/// Cada una caduca con su propio plazo, porque no toda la información envejece
/// igual: un peligro de hace dos horas ya no sirve para decidir por dónde
/// caminar, y una persona desaparecida sigue interesando al día siguiente.
/// El plazo es un tope: quien publica no tiene que acordarse de borrar nada.
enum BoardCategory {
  need(
    code: 'need',
    label: 'Necesito',
    hint: 'agua, medicinas, rescate',
    validFor: Duration(hours: 12),
  ),
  offer(
    code: 'offer',
    label: 'Ofrezco',
    hint: 'comida, refugio, transporte',
    validFor: Duration(hours: 12),
  ),
  missing(
    code: 'missing',
    label: 'Desaparecidos',
    hint: 'a quién buscas o dónde lo viste',
    validFor: Duration(hours: 48),
  ),
  danger(
    code: 'danger',
    label: 'Peligro',
    hint: 'derrumbe, zona insegura, incendio',
    validFor: Duration(hours: 2),
  );

  const BoardCategory({
    required this.code,
    required this.label,
    required this.hint,
    required this.validFor,
  });

  /// Cómo viaja en el protocolo (corto: cada byte cuenta en BLE).
  final String code;

  /// Nombre para la interfaz.
  final String label;

  /// Ejemplos que se muestran al publicar, para que el aviso sea útil.
  final String hint;

  /// Tiempo máximo que el aviso se muestra como vigente.
  final Duration validFor;

  static BoardCategory? fromCode(Object? code) {
    for (final category in values) {
      if (category.code == code) return category;
    }
    return null;
  }
}

/// Publicaciones del tablero que siguen vigentes, de la más nueva a la más
/// vieja.
///
/// Un aviso caducado no desaparece del historial del canal (sigue ahí como
/// mensaje, con su hora), pero deja de mostrarse como información actual: en
/// una emergencia, dar por bueno un dato viejo es peor que no tenerlo.
List<ChatMessage> activeBoardPosts(
  Iterable<ChatMessage> messages, {
  BoardCategory? category,
  DateTime? now,
}) {
  final moment = now ?? DateTime.now();
  final posts = messages.where((message) {
    if (message.kind != MessageKind.board) return false;
    if (category != null && message.board != category) return false;
    final expiresAt = message.expiresAt;
    if (expiresAt == null) return false;
    return expiresAt.isAfter(moment);
  }).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return posts;
}

/// Cuánto le queda de vida a un aviso, en palabras.
String formatBoardRemaining(DateTime expiresAt, {DateTime? now}) {
  final left = expiresAt.difference(now ?? DateTime.now());
  if (left.isNegative) return 'caducado';
  if (left.inMinutes < 1) return 'caduca ya';
  if (left.inMinutes < 60) return 'caduca en ${left.inMinutes} min';
  if (left.inHours < 48) return 'caduca en ${left.inHours} h';
  return 'caduca en ${left.inDays} d';
}
