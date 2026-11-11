import 'dart:convert';
import 'dart:io';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'store_common.dart';

Future<File> _databaseFile() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return File(p.join(dir.path, 'bociva.db'));
}

Future<LocalStore> openLocalStore({
  required Future<String?> Function() readKey,
  required Future<String> Function() createKey,
}) async {
  return openLocalStoreAt(
    (await _databaseFile()).path,
    readKey: readKey,
    createKey: createKey,
  );
}

Future<LocalStore> openLocalStoreAt(
  String path, {
  required Future<String?> Function() readKey,
  required Future<String> Function() createKey,
}) async {
  final file = File(path);
  final exists = file.existsSync();
  var key = await readKey();
  if (key == null) {
    // Ohne Schlüssel ist eine vorhandene Datenbank nicht mehr lesbar. Ein
    // neuer Schlüssel würde das nur verdecken.
    if (exists) throw const LocalStoreLocked();
    key = await createKey();
  }
  final db = sqlite3.open(file.path);
  try {
    db.execute("PRAGMA hexkey = '$key'");
    db.select('SELECT count(*) FROM sqlite_master');
  } on SqliteException {
    db.close();
    throw const LocalStoreLocked();
  }
  return SqliteStore(db);
}

/// Entfernt die Datenbank samt Journal. Nur nach ausdrücklicher Bestätigung.
Future<void> deleteLocalStore() async {
  final file = await _databaseFile();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('${file.path}$suffix');
    if (f.existsSync()) await f.delete();
  }
}

/// Datenablage auf dem Gerät.
class SqliteStore implements LocalStore {
  SqliteStore(this.db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS records (
        kind TEXT NOT NULL,
        id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL,
        date TEXT,
        data TEXT NOT NULL,
        dirty INTEGER NOT NULL,
        PRIMARY KEY (kind, id)
      );
      CREATE INDEX IF NOT EXISTS records_date ON records (kind, date);
      CREATE INDEX IF NOT EXISTS records_dirty ON records (dirty);
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    ''');
  }

  final Database db;

  SyncRecord _row(Row r) => SyncRecord(
    kind: r['kind'] as String,
    id: r['id'] as String,
    updatedAt: r['updated_at'] as int,
    deleted: r['deleted'] == 1,
    data: (jsonDecode(r['data'] as String) as Map).cast<String, Object?>(),
  );

  @override
  Future<SyncRecord?> get(String kind, String id) async {
    final rows = db.select('SELECT * FROM records WHERE kind = ? AND id = ?', [
      kind,
      id,
    ]);
    return rows.isEmpty ? null : _row(rows.first);
  }

  @override
  Future<void> put(SyncRecord r, {required bool dirty}) async {
    db.execute('INSERT OR REPLACE INTO records VALUES (?, ?, ?, ?, ?, ?, ?)', [
      r.kind,
      r.id,
      r.updatedAt,
      r.deleted ? 1 : 0,
      r.date,
      jsonEncode(r.data),
      dirty ? 1 : 0,
    ]);
  }

  @override
  Future<bool> isDirty(String kind, String id) async => db.select(
    'SELECT 1 FROM records WHERE kind = ? AND id = ? AND dirty = 1',
    [kind, id],
  ).isNotEmpty;

  @override
  Future<List<SyncRecord>> byDate(String kind, String from, String to) async =>
      db
          .select(
            'SELECT * FROM records WHERE kind = ? AND deleted = 0 '
            'AND date >= ? AND date <= ?',
            [kind, from, to],
          )
          .map(_row)
          .toList();

  @override
  Future<Set<String>> datesWith(String kind) async => {
    for (final r in db.select(
      'SELECT DISTINCT date FROM records WHERE kind = ? AND deleted = 0 '
      'AND date IS NOT NULL',
      [kind],
    ))
      r['date'] as String,
  };

  @override
  Future<List<SyncRecord>> all(String kind) async => db
      .select('SELECT * FROM records WHERE kind = ? AND deleted = 0', [kind])
      .map(_row)
      .toList();

  @override
  Future<List<SyncRecord>> dirty({int limit = 500}) async => db
      .select('SELECT * FROM records WHERE dirty = 1 LIMIT ?', [limit])
      .map(_row)
      .toList();

  @override
  Future<void> clearDirty(List<SyncRecord> sent) async {
    db.execute('BEGIN');
    try {
      for (final r in sent) {
        db.execute(
          'UPDATE records SET dirty = 0 '
          'WHERE kind = ? AND id = ? AND updated_at = ?',
          [r.kind, r.id, r.updatedAt],
        );
      }
      db.execute('COMMIT');
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<void> markAllDirty() async =>
      db.execute('UPDATE records SET dirty = 1');

  @override
  Future<int> countDirty() async =>
      db.select('SELECT count(*) c FROM records WHERE dirty = 1').first['c']
          as int;

  @override
  Future<void> clearAll() async {
    db.execute('DELETE FROM records');
    db.execute('DELETE FROM meta');
  }

  @override
  Future<int> countLive() async =>
      db.select('SELECT count(*) c FROM records WHERE deleted = 0').first['c']
          as int;

  @override
  Future<String?> meta(String key) async {
    final rows = db.select('SELECT value FROM meta WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> setMeta(String key, String? value) async {
    if (value == null) {
      db.execute('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      db.execute('INSERT OR REPLACE INTO meta VALUES (?, ?)', [key, value]);
    }
  }
}
