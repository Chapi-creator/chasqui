import 'dart:collection';

/// Caché de tramas ya vistas. Evita que una inundación se amplifique y que
/// reenviemos el mismo mensaje dos veces por distintos enlaces.
class DedupCache {
  /// El TTL de la caché cubre todo lo que una trama puede seguir siendo
  /// válida: el mensajero la puede soltar horas después, y si ya no la
  /// recordáramos la entregaríamos repetida.
  DedupCache({this.maxEntries = 8192, this.ttl = const Duration(hours: 48)});

  final int maxEntries;
  final Duration ttl;

  final LinkedHashMap<String, DateTime> _seen =
      LinkedHashMap<String, DateTime>();

  /// Marca la trama como vista. Devuelve false si ya la habíamos procesado.
  bool markSeen(String key, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final previous = _seen.remove(key);
    if (previous != null && at.difference(previous) < ttl) {
      _seen[key] = previous;
      return false;
    }
    _seen[key] = at;
    _prune(at);
    return true;
  }

  bool contains(String key) => _seen.containsKey(key);

  int get length => _seen.length;

  /// Se vacía al cambiar de radio: las tramas vistas por un transporte no
  /// dicen nada del otro, y así no se descarta tráfico legítimo tras el cambio.
  void clear() => _seen.clear();

  void _prune(DateTime now) {
    _seen.removeWhere((_, at) => now.difference(at) > ttl);
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
  }
}
