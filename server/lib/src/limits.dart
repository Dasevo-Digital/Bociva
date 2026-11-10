import 'dart:async';
import 'dart:collection';

import 'api_error.dart';

/// Zählt Versuche pro Schlüssel in einem festen Zeitfenster. Die Zahl der
/// Schlüssel ist begrenzt, damit wechselnde Schlüssel keinen Speicher füllen.
class RateLimiter {
  RateLimiter(this.limit, this.window, {this.maxKeys = 10000});

  final int limit;
  final Duration window;
  final int maxKeys;

  /// In Einfügereihenfolge: die ältesten stehen vorn.
  final _hits = <String, (int, DateTime)>{};

  int get size => _hits.length;

  bool hit(String key) {
    final now = DateTime.now();
    if (_hits.length >= maxKeys) {
      _hits.removeWhere((_, v) => now.isAfter(v.$2));
      // Sind noch alle gültig, gehen die ältesten, und zwar gleich ein Zehntel,
      // damit das Aufräumen nicht bei jedem Aufruf läuft.
      if (_hits.length >= maxKeys) {
        final drop = _hits.keys.take(maxKeys ~/ 10 + 1).toList();
        drop.forEach(_hits.remove);
      }
    }
    final current = _hits[key];
    if (current == null || now.isAfter(current.$2)) {
      _hits.remove(key);
      _hits[key] = (1, now.add(window));
      return true;
    }
    if (current.$1 >= limit) return false;
    _hits[key] = (current.$1 + 1, current.$2);
    return true;
  }

  void reset(String key) => _hits.remove(key);
}

/// Lässt höchstens [concurrency] Aufgaben gleichzeitig laufen und höchstens
/// [maxQueue] warten. Darüber hinaus meldet der Server „ausgelastet“, statt
/// immer mehr Arbeit anzunehmen.
class Gate {
  Gate(this.concurrency, {required this.maxQueue});

  final int concurrency, maxQueue;
  int _running = 0;
  final _waiting = Queue<Completer<void>>();

  static const busy = ApiError(
    503,
    'busy',
    'Der Server ist gerade ausgelastet. Bitte gleich noch einmal versuchen.',
  );

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= concurrency) {
      if (_waiting.length >= maxQueue) throw busy;
      final ticket = Completer<void>();
      _waiting.add(ticket);
      await ticket.future;
    } else {
      _running++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        // Der Platz geht direkt an den nächsten.
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
