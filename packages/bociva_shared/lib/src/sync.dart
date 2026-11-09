import 'store.dart';

class SyncResponse {
  const SyncResponse({
    required this.cursor,
    required this.changes,
    required this.hasMore,
  });

  factory SyncResponse.fromJson(Map<String, Object?> j) => SyncResponse(
    cursor: (j['cursor'] as num).toInt(),
    hasMore: j['hasMore'] == true,
    changes: [
      for (final c in j['changes'] as List)
        SyncRecord.fromJson((c as Map).cast<String, Object?>()),
    ],
  );

  final int cursor;
  final bool hasMore;
  final List<SyncRecord> changes;

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'hasMore': hasMore,
    'changes': [for (final c in changes) c.toJson()],
  };
}

abstract class SyncTransport {
  Future<SyncResponse> exchange(int since, List<SyncRecord> changes);
}

/// Gleicht ein Gerät mit dem Server ab: geänderte Datensätze hoch, neue
/// herunter. Bei Konflikten gewinnt die jüngere Änderung.
class SyncEngine {
  SyncEngine(this.store, this.transport);

  static const _cursorKey = 'sync.cursor';
  static const batchSize = 500;

  final LocalStore store;
  final SyncTransport transport;
  bool _running = false;

  /// Führt einen Abgleich aus und meldet die Zahl übernommener Datensätze.
  /// Läuft schon einer, passiert nichts.
  Future<int> run() async {
    if (_running) return 0;
    _running = true;
    try {
      var cursor = int.tryParse(await store.meta(_cursorKey) ?? '') ?? 0;
      var applied = 0;
      while (true) {
        final batch = await store.dirty(limit: batchSize);
        final response = await transport.exchange(cursor, batch);
        await store.clearDirty(batch);
        for (final incoming in response.changes) {
          if (await _apply(incoming)) applied++;
        }
        cursor = response.cursor;
        await store.setMeta(_cursorKey, '$cursor');
        if (batch.length < batchSize && !response.hasMore) break;
      }
      return applied;
    } finally {
      _running = false;
    }
  }

  Future<bool> _apply(SyncRecord incoming) async {
    final local = await store.get(incoming.kind, incoming.id);
    if (local != null) {
      final localDirty = await store.isDirty(incoming.kind, incoming.id);
      if (localDirty && local.updatedAt > incoming.updatedAt) return false;
      if (local.updatedAt == incoming.updatedAt &&
          local.deleted == incoming.deleted) {
        return false;
      }
    }
    await store.put(incoming, dirty: false);
    return true;
  }

  /// Beim ersten Verbinden: Alles Lokale muss noch auf den Server.
  Future<void> prepareFirstSync() async {
    await store.setMeta(_cursorKey, '0');
    await store.markAllDirty();
  }
}
