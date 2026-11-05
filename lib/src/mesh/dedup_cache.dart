import 'dart:collection';

/// Caché de tramas ya vistas. Evita que una inundación se amplifique y que
/// reenviemos el mismo mensaje dos veces por distintos enlaces.
class DedupCache {
  DedupCache({this.maxEntries = 4096, this.ttl = const Duration(hours: 12)});

  final int maxEntries;
  final Duration ttl;

  final LinkedHashMap<String, DateTime> _seen = LinkedHashMap<String, DateTime>();

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

  void _prune(DateTime now) {
    _seen.removeWhere((_, at) => now.difference(at) > ttl);
    while (_seen.length > maxEntries) {
      _seen.remove(_seen.keys.first);
    }
  }
}
