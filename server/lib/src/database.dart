import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:sqlite3/sqlite3.dart';

class DataKeyException implements Exception {
  const DataKeyException(this.message);
  final String message;
  @override
  String toString() => message;
}

String randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Holt den Datenbankschlüssel oder legt einen neuen an. Fehlt er, obwohl
/// verschlüsselte Daten da sind, startet der Server nicht: Ein verlorener
/// Schlüssel darf nicht unbemerkt zu einem leeren Server führen.
String loadOrCreateKey(String path, File database) {
  final file = File(path);
  if (file.existsSync()) {
    if (!Platform.isWindows && FileStat.statSync(file.path).mode & 0x3f != 0) {
      throw DataKeyException(
        'Schlüsseldatei $path darf nur für ihren Besitzer lesbar sein '
        '(chmod 600).',
      );
    }
    final key = file.readAsStringSync().trim();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(key)) {
      throw DataKeyException('Schlüsseldatei $path ist ungültig.');
    }
    return key;
  }
  if (database.existsSync() && database.lengthSync() > 0) {
    throw DataKeyException(
      'Schlüsseldatei $path fehlt, die Datenbank existiert aber. Bitte die '
      'gesicherte Schlüsseldatei zurücklegen.',
    );
  }
  final key = randomHex(32);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$key\n', flush: true);
  if (!Platform.isWindows) {
    try {
      Process.runSync('chmod', ['600', file.path]);
    } on ProcessException {
      // Im Docker-Image gibt es kein chmod; dort gilt umask 077, die Prüfung
      // unten stellt das sicher.
    }
    if (FileStat.statSync(file.path).mode & 0x3f != 0) {
      throw DataKeyException('Schlüsseldatei $path muss die Rechte 600 haben.');
    }
  }
  return key;
}

Database openDatabase(String path, {String? hexKey}) {
  if (path == ':memory:') return sqlite3.openInMemory();
  final db = sqlite3.open(path);
  if (hexKey != null) {
    try {
      db.execute("PRAGMA hexkey = '$hexKey'");
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException {
      db.close();
      throw DataKeyException(
        'Die Datenbank $path lässt sich mit dem Schlüssel nicht öffnen.',
      );
    }
  }
  db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA busy_timeout = 5000');
  return db;
}

const _schemaVersion = 1;

void migrate(Database db) {
  final version = db.select('PRAGMA user_version').first.values.first as int;
  if (version >= _schemaVersion) return;
  db.execute('''
    CREATE TABLE users (
      id TEXT PRIMARY KEY,
      username TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL,
      is_admin INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      seq INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE sessions (
      token_hash TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at INTEGER NOT NULL
    );
    CREATE TABLE invites (
      code_hash TEXT PRIMARY KEY,
      expires_at INTEGER NOT NULL
    );
    CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE records (
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      id TEXT NOT NULL,
      seq INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      deleted INTEGER NOT NULL,
      data TEXT NOT NULL,
      PRIMARY KEY (user_id, kind, id)
    );
    CREATE INDEX records_seq ON records (user_id, seq);
    CREATE TABLE food_cache (
      barcode TEXT PRIMARY KEY,
      json TEXT,
      fetched_at INTEGER NOT NULL
    );
    PRAGMA user_version = $_schemaVersion;
  ''');
}

/// Serverseitiger Abgleich. Der Server kennt nur die Hülle der Datensätze.
class RecordService {
  RecordService(this.db);

  final Database db;

  static const pageSize = 1000;
  static const maxChanges = 2000;
  static const maxRecordBytes = 64 * 1024;

  /// Eine falsch gehende Uhr soll nicht auf Dauer jede Änderung schlagen.
  static const maxClockSkewMs = 5 * 60 * 1000;

  SyncResponse sync(
    String userId,
    int since,
    List<SyncRecord> changes,
    int nowMs,
  ) {
    db.execute('BEGIN IMMEDIATE');
    try {
      var seq =
          db.select('SELECT seq FROM users WHERE id = ?', [userId]).first['seq']
              as int;
      final getStamp = db.prepare(
        'SELECT updated_at FROM records WHERE user_id = ? AND kind = ? AND id = ?',
      );
      final upsert = db.prepare('''
        INSERT INTO records (user_id, kind, id, seq, updated_at, deleted, data)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (user_id, kind, id) DO UPDATE SET
          seq = excluded.seq, updated_at = excluded.updated_at,
          deleted = excluded.deleted, data = excluded.data
      ''');
      try {
        for (final c in changes) {
          final stamp = min(c.updatedAt, nowMs + maxClockSkewMs);
          final existing = getStamp.select([userId, c.kind, c.id]);
          if (existing.isNotEmpty &&
              (existing.first['updated_at'] as int) >= stamp) {
            continue;
          }
          seq++;
          upsert.execute([
            userId,
            c.kind,
            c.id,
            seq,
            stamp,
            c.deleted ? 1 : 0,
            c.deleted ? '{}' : jsonEncode(c.data),
          ]);
        }
      } finally {
        getStamp.close();
        upsert.close();
      }
      db.execute('UPDATE users SET seq = ? WHERE id = ?', [seq, userId]);
      final rows = db.select(
        'SELECT kind, id, seq, updated_at, deleted, data FROM records '
        'WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?',
        [userId, since, pageSize],
      );
      db.execute('COMMIT');
      return SyncResponse(
        cursor: rows.isEmpty ? max(since, 0) : rows.last['seq'] as int,
        hasMore: rows.length == pageSize,
        changes: [
          for (final r in rows)
            SyncRecord(
              kind: r['kind'] as String,
              id: r['id'] as String,
              updatedAt: r['updated_at'] as int,
              deleted: r['deleted'] == 1,
              data: (jsonDecode(r['data'] as String) as Map)
                  .cast<String, Object?>(),
            ),
        ],
      );
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, Object?> export(String userId) {
    final out = <String, List<Object?>>{for (final k in RecordKind.all) k: []};
    for (final r in db.select(
      'SELECT kind, data FROM records WHERE user_id = ? AND deleted = 0 '
      'ORDER BY kind, id',
      [userId],
    )) {
      out[r['kind'] as String]?.add(jsonDecode(r['data'] as String));
    }
    return {'format': 'bociva-export', 'version': 1, ...out};
  }
}
