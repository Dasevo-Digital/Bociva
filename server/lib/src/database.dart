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
  final memory = path == ':memory:';
  final db = memory ? sqlite3.openInMemory() : sqlite3.open(path);
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
  if (!memory) db.execute('PRAGMA journal_mode = WAL');
  db.execute('PRAGMA foreign_keys = ON');
  db.execute('PRAGMA busy_timeout = 5000');
  // Gelöschtes wird überschrieben und bleibt nicht in freien Seiten stehen.
  db.execute('PRAGMA secure_delete = ON');
  return db;
}

/// Jede Stufe läuft in einer eigenen Transaktion: Ein Abbruch mittendrin
/// hinterlässt keine halb angelegte Datenbank.
const _migrations = <String>[
  // 1: Grundschema
  '''
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
  ''',
  // 2: Speicherverbrauch pro Konto, für die Quote
  '''
    ALTER TABLE users ADD COLUMN record_count INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE users ADD COLUMN data_bytes INTEGER NOT NULL DEFAULT 0;
    UPDATE users SET
      record_count = (SELECT count(*) FROM records r WHERE r.user_id = users.id),
      data_bytes = (SELECT coalesce(sum(length(data)), 0) FROM records r
                    WHERE r.user_id = users.id);
    CREATE INDEX food_cache_fetched ON food_cache (fetched_at);
  ''',
];

void migrate(Database db) {
  var version = db.select('PRAGMA user_version').first.values.first as int;
  while (version < _migrations.length) {
    db.execute('BEGIN IMMEDIATE');
    try {
      db.execute(_migrations[version]);
      version++;
      db.execute('PRAGMA user_version = $version');
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }
}

/// Das Konto hat seinen Speicherplatz ausgeschöpft.
class QuotaExceeded implements Exception {
  const QuotaExceeded();
}

/// Serverseitiger Abgleich. Der Server kennt nur die Hülle der Datensätze.
class RecordService {
  RecordService(
    this.db, {
    this.maxRecordsPerUser = 500000,
    this.maxBytesPerUser = 200 * 1024 * 1024,
  });

  final Database db;
  final int maxRecordsPerUser, maxBytesPerUser;

  static const pageSize = 1000;

  /// Auch große Datensätze sollen eine Antwort nicht unbegrenzt aufblähen.
  static const maxPageBytes = 4 * 1024 * 1024;
  static const maxChanges = 2000;
  static const maxRecordBytes = SyncLimits.maxRecordBytes;

  /// Eine falsch gehende Uhr soll nicht auf Dauer jede Änderung schlagen.
  static const maxClockSkewMs = 5 * 60 * 1000;

  SyncResponse sync(
    String userId,
    int since,
    List<SyncRecord> changes,
    int nowMs, {
    int rejected = 0,
  }) {
    db.execute('BEGIN IMMEDIATE');
    try {
      final user = db.select(
        'SELECT seq, record_count, data_bytes FROM users WHERE id = ?',
        [userId],
      ).first;
      var seq = user['seq'] as int;
      var count = user['record_count'] as int;
      var bytes = user['data_bytes'] as int;
      // Ein Cursor jenseits des Servers stammt von vor einer Wiederherstellung
      // aus einer Sicherung. Ohne Neubeginn fehlten dem Gerät still alle neuen
      // Datensätze, bis die Zählung es wieder eingeholt hat.
      if (since > seq) since = 0;
      final getStamp = db.prepare(
        'SELECT updated_at, length(data) AS size FROM records '
        'WHERE user_id = ? AND kind = ? AND id = ?',
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
          final data = c.deleted ? '{}' : jsonEncode(c.data);
          if (existing.isEmpty) count++;
          bytes += data.length - (existing.firstOrNull?['size'] as int? ?? 0);
          // Löschen geht immer, auch bei voller Quote.
          if (!c.deleted &&
              (count > maxRecordsPerUser || bytes > maxBytesPerUser)) {
            throw const QuotaExceeded();
          }
          seq++;
          upsert.execute([
            userId,
            c.kind,
            c.id,
            seq,
            stamp,
            c.deleted ? 1 : 0,
            data,
          ]);
        }
      } finally {
        getStamp.close();
        upsert.close();
      }
      db.execute(
        'UPDATE users SET seq = ?, record_count = ?, data_bytes = ? '
        'WHERE id = ?',
        [seq, count, bytes, userId],
      );
      final rows = db.select(
        'SELECT kind, id, seq, updated_at, deleted, data FROM records '
        'WHERE user_id = ? AND seq > ? ORDER BY seq LIMIT ?',
        [userId, since, pageSize],
      );
      db.execute('COMMIT');
      final page = <SyncRecord>[];
      var pageBytes = 0;
      var cursor = since;
      for (final r in rows) {
        final data = r['data'] as String;
        if (page.isNotEmpty && pageBytes + data.length > maxPageBytes) break;
        pageBytes += data.length;
        cursor = r['seq'] as int;
        page.add(
          SyncRecord(
            kind: r['kind'] as String,
            id: r['id'] as String,
            updatedAt: r['updated_at'] as int,
            deleted: r['deleted'] == 1,
            data: (jsonDecode(data) as Map).cast<String, Object?>(),
          ),
        );
      }
      return SyncResponse(
        cursor: cursor,
        hasMore: page.length < rows.length || rows.length == pageSize,
        changes: page,
        rejected: rejected,
      );
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Der Export in Häppchen, damit ein großes Konto weder den Speicher füllt
  /// noch andere Anfragen so lange aufhält.
  Stream<List<int>> export(String userId) async* {
    const pageSize = 500;
    yield utf8.encode('{"format":"bociva-export","version":1');
    for (final kind in RecordKind.all) {
      yield utf8.encode(',${jsonEncode(kind)}:[');
      var after = '';
      var first = true;
      while (true) {
        final rows = db.select(
          'SELECT id, data FROM records WHERE user_id = ? AND kind = ? '
          'AND deleted = 0 AND id > ? ORDER BY id LIMIT ?',
          [userId, kind, after, pageSize],
        );
        if (rows.isEmpty) break;
        final out = StringBuffer();
        for (final r in rows) {
          if (!first) out.write(',');
          first = false;
          out.write(r['data'] as String);
        }
        yield utf8.encode(out.toString());
        after = rows.last['id'] as String;
        if (rows.length < pageSize) break;
        // Anderen Anfragen Zeit lassen.
        await Future<void>.delayed(Duration.zero);
      }
      yield utf8.encode(']');
    }
    yield utf8.encode('}');
  }
}
