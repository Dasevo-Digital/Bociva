import 'dart:convert';

/// Ein synchronisierbarer Datensatz. Lebensmittel, Tagebuch, Wasser usw. sind
/// alle von dieser Form; der Server versteht nur diese Hülle.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.id,
    required this.updatedAt,
    required this.data,
    this.deleted = false,
  });

  factory SyncRecord.fromJson(Map<String, Object?> j) => SyncRecord(
    kind: j['kind'] as String,
    id: j['id'] as String,
    updatedAt: (j['updatedAt'] as num).toInt(),
    deleted: j['deleted'] == true,
    data: (j['data'] as Map?)?.cast<String, Object?>() ?? const {},
  );

  final String kind, id;
  final int updatedAt;
  final bool deleted;
  final Map<String, Object?> data;

  String? get date => data['date'] as String?;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'updatedAt': updatedAt,
    'deleted': deleted,
    'data': data,
  };
}

/// Alle Datensatzarten, die ein Server annimmt.
abstract final class RecordKind {
  static const food = 'food';
  static const diary = 'diary';
  static const water = 'water';
  static const weight = 'weight';
  static const activity = 'activity';
  static const profile = 'profile';
  static const recipe = 'recipe';
  static const fasting = 'fasting';
  static const all = {
    food,
    diary,
    water,
    weight,
    activity,
    profile,
    recipe,
    fasting,
  };
}

/// Grenzen, die Server und Geräte gleich prüfen.
abstract final class SyncLimits {
  static const maxIdLength = 80;
  static const maxRecordBytes = 64 * 1024;
}

/// Warum ein Datensatz nicht übertragen werden kann, oder `null`.
String? recordProblem(SyncRecord r) {
  if (!RecordKind.all.contains(r.kind)) return 'unbekannte Art';
  if (r.id.isEmpty || r.id.length > SyncLimits.maxIdLength) {
    return 'ungültige Kennung';
  }
  if (r.updatedAt < 0) return 'ungültiger Zeitstempel';
  final String encoded;
  try {
    encoded = jsonEncode(r.data);
  } on Object {
    // Zum Beispiel NaN oder Infinity.
    return 'ungültige Zahl';
  }
  if (encoded.length > SyncLimits.maxRecordBytes) return 'zu groß';
  return null;
}

/// Ein Datensatz, den weder Gerät noch Server speichern würden.
class InvalidRecordException implements Exception {
  const InvalidRecordException(this.reason);
  final String reason;

  @override
  String toString() => reason == 'zu groß'
      ? 'Der Eintrag ist zu groß. Bitte kürzen.'
      : 'Der Eintrag enthält ungültige Werte.';
}

/// Datenablage eines Geräts. Native Apps speichern in SQLite, im Browser
/// bleiben die Daten nur im Speicher und liegen auf dem Server.
abstract class LocalStore {
  Future<SyncRecord?> get(String kind, String id);
  Future<void> put(SyncRecord record, {required bool dirty});
  Future<bool> isDirty(String kind, String id);

  /// Nicht gelöschte Datensätze zwischen [from] und [to] (einschließlich).
  Future<List<SyncRecord>> byDate(String kind, String from, String to);

  /// Alle nicht gelöschten Datensätze einer Art.
  Future<List<SyncRecord>> all(String kind);

  /// Die Tage, an denen es nicht gelöschte Datensätze der Art gibt.
  Future<Set<String>> datesWith(String kind);

  Future<List<SyncRecord>> dirty({int limit = 500});

  /// Nimmt die Markierung nur, wenn sich der Datensatz seit dem Lesen nicht
  /// geändert hat; eine Eingabe während des Sync geht so nicht verloren.
  Future<void> clearDirty(List<SyncRecord> sent);

  Future<void> markAllDirty();

  /// Anzahl noch nicht übertragener Datensätze.
  Future<int> countDirty();
  Future<void> clearAll();
  Future<int> countLive();
  Future<String?> meta(String key);
  Future<void> setMeta(String key, String? value);
}

/// Für den Browser und für Tests.
class MemoryStore implements LocalStore {
  final _records = <String, SyncRecord>{};
  final _dirty = <String>{};
  final _meta = <String, String>{};

  String _k(String kind, String id) => '$kind/$id';

  @override
  Future<SyncRecord?> get(String kind, String id) async =>
      _records[_k(kind, id)];

  @override
  Future<void> put(SyncRecord record, {required bool dirty}) async {
    final key = _k(record.kind, record.id);
    _records[key] = record;
    dirty ? _dirty.add(key) : _dirty.remove(key);
  }

  @override
  Future<bool> isDirty(String kind, String id) async =>
      _dirty.contains(_k(kind, id));

  @override
  Future<List<SyncRecord>> byDate(String kind, String from, String to) async =>
      _records.values
          .where(
            (r) =>
                r.kind == kind &&
                !r.deleted &&
                r.date != null &&
                r.date!.compareTo(from) >= 0 &&
                r.date!.compareTo(to) <= 0,
          )
          .toList();

  @override
  Future<List<SyncRecord>> all(String kind) async =>
      _records.values.where((r) => r.kind == kind && !r.deleted).toList();

  @override
  Future<Set<String>> datesWith(String kind) async => {
    for (final r in _records.values)
      if (r.kind == kind && !r.deleted && r.date != null) r.date!,
  };

  @override
  Future<List<SyncRecord>> dirty({int limit = 500}) async => [
    for (final key in _dirty.take(limit)) _records[key]!,
  ];

  @override
  Future<void> clearDirty(List<SyncRecord> sent) async {
    for (final r in sent) {
      final key = _k(r.kind, r.id);
      if (_records[key]?.updatedAt == r.updatedAt) _dirty.remove(key);
    }
  }

  @override
  Future<void> markAllDirty() async => _dirty.addAll(_records.keys);

  @override
  Future<int> countDirty() async => _dirty.length;

  @override
  Future<void> clearAll() async {
    _records.clear();
    _dirty.clear();
    _meta.clear();
  }

  @override
  Future<int> countLive() async =>
      _records.values.where((r) => !r.deleted).length;

  @override
  Future<String?> meta(String key) async => _meta[key];

  @override
  Future<void> setMeta(String key, String? value) async {
    value == null ? _meta.remove(key) : _meta[key] = value;
  }
}
