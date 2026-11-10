import 'store.dart';

class SyncResponse {
  const SyncResponse({
    required this.cursor,
    required this.changes,
    required this.hasMore,
    this.rejected = 0,
  });

  /// Wirft [FormatException], wenn die Antwort nicht passt, z. B. weil ein
  /// Proxy davor etwas anderes liefert.
  factory SyncResponse.fromJson(Map<String, Object?> j) {
    final cursor = j['cursor'];
    final changes = j['changes'];
    if (cursor is! num || changes is! List) {
      throw const FormatException('Unerwartete Antwort beim Abgleich.');
    }
    try {
      return SyncResponse(
        cursor: cursor.toInt(),
        hasMore: j['hasMore'] == true,
        rejected: (j['rejected'] as num?)?.toInt() ?? 0,
        changes: [
          for (final c in changes)
            SyncRecord.fromJson((c as Map).cast<String, Object?>()),
        ],
      );
    } on TypeError {
      throw const FormatException('Unerwartete Antwort beim Abgleich.');
    }
  }

  final int cursor;
  final bool hasMore;
  final List<SyncRecord> changes;

  /// Datensätze, die der Server nicht angenommen hat.
  final int rejected;

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'hasMore': hasMore,
    'changes': [for (final c in changes) c.toJson()],
    if (rejected > 0) 'rejected': rejected,
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

  /// Datensätze des letzten Laufs, die nicht übertragen werden konnten. Sie
  /// bleiben auf dem Gerät, blockieren den Abgleich aber nicht.
  int rejected = 0;

  /// Führt einen Abgleich aus und meldet die Zahl übernommener Datensätze.
  /// Läuft schon einer, passiert nichts.
  Future<int> run() async {
    if (_running) return 0;
    _running = true;
    rejected = 0;
    try {
      var cursor = int.tryParse(await store.meta(_cursorKey) ?? '') ?? 0;
      var applied = 0;
      while (true) {
        final batch = await store.dirty(limit: batchSize);
        final sendable = [
          for (final r in batch)
            if (recordProblem(r) == null) r,
        ];
        rejected += batch.length - sendable.length;
        final response = await transport.exchange(cursor, sendable);
        rejected += response.rejected;
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
