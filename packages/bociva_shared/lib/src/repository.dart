import 'basic_foods.dart';
import 'goals.dart';
import 'models.dart';
import 'store.dart';

/// Typisierter Zugriff auf die Daten eines Geräts.
class BocivaRepository {
  BocivaRepository(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalStore store;
  final DateTime Function() _clock;

  int get nowMs => _clock().millisecondsSinceEpoch;

  /// Der Zeitstempel steigt pro Datensatz immer an, auch wenn die Geräteuhr
  /// zurückgestellt wurde.
  Future<void> _put(
    String kind,
    String id,
    Map<String, Object?> data, {
    bool deleted = false,
  }) async {
    final existing = await store.get(kind, id);
    var stamp = nowMs;
    if (existing != null && existing.updatedAt >= stamp) {
      stamp = existing.updatedAt + 1;
    }
    await store.put(
      SyncRecord(
        kind: kind,
        id: id,
        updatedAt: stamp,
        data: deleted ? const {} : data,
        deleted: deleted,
      ),
      dirty: true,
    );
  }

  Future<void> _delete(String kind, String id) =>
      _put(kind, id, const {}, deleted: true);

  // Profil

  Future<Profile?> profile() async {
    final r = await store.get(RecordKind.profile, 'me');
    return r == null || r.deleted ? null : Profile.fromJson(r.data);
  }

  Future<void> saveProfile(Profile p) =>
      _put(RecordKind.profile, 'me', p.toJson());

  // Tagebuch

  Future<List<DiaryEntry>> diary(String date) async {
    final records = await store.byDate(RecordKind.diary, date, date);
    final list = [for (final r in records) DiaryEntry.fromJson(r.data)]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> saveDiary(DiaryEntry e) =>
      _put(RecordKind.diary, e.id, e.toJson());

  Future<void> deleteDiary(String id) => _delete(RecordKind.diary, id);

  /// Trägt [amount] von [food] ein und merkt sich das Lebensmittel.
  Future<DiaryEntry> logFood(
    Food food, {
    required String date,
    required Meal meal,
    required double amount,
  }) async {
    final entry = DiaryEntry(
      id: newId(),
      date: date,
      meal: meal,
      name: food.name,
      brand: food.brand,
      foodId: food.id,
      amount: amount,
      unit: food.unit,
      nutrients: food.forAmount(amount),
      createdAt: nowMs,
      estimated: food.source == FoodSource.ai,
    );
    await saveDiary(entry);
    await saveFood(food.copyWith(lastUsedAt: nowMs));
    return entry;
  }

  // Lebensmittel

  Future<void> saveFood(Food f) => _put(RecordKind.food, f.id, f.toJson());

  Future<void> deleteFood(String id) => _delete(RecordKind.food, id);

  Future<List<Food>> savedFoods() async => [
    for (final r in await store.all(RecordKind.food)) Food.fromJson(r.data),
  ];

  Future<List<Food>> recentFoods({int limit = 30}) async {
    final foods = (await savedFoods()).where((f) => f.lastUsedAt > 0).toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return foods.take(limit).toList();
  }

  Future<List<Food>> customFoods() async =>
      (await savedFoods()).where((f) => f.source == FoodSource.custom).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  Future<Food?> foodByBarcode(String barcode) async {
    for (final f in await savedFoods()) {
      if (f.barcode == barcode) return f;
    }
    return null;
  }

  /// Sucht offline in eigenen, zuletzt genutzten und Grundnahrungsmitteln.
  Future<List<Food>> searchLocal(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final saved = await savedFoods();
    final seen = saved.map((f) => f.id).toSet();
    final all = [...saved, ...basicFoods.where((f) => !seen.contains(f.id))];
    int score(Food f) {
      final n = f.name.toLowerCase();
      return n == q
          ? 0
          : n.startsWith(q)
          ? 1
          : 2;
    }

    return all
        .where(
          (f) =>
              f.name.toLowerCase().contains(q) ||
              (f.brand?.toLowerCase().contains(q) ?? false),
        )
        .toList()
      ..sort((a, b) {
        final s = score(a).compareTo(score(b));
        return s != 0 ? s : b.lastUsedAt.compareTo(a.lastUsedAt);
      });
  }

  // Wasser

  Future<List<WaterEntry>> water(String date) async {
    final records = await store.byDate(RecordKind.water, date, date);
    final list = [for (final r in records) WaterEntry.fromJson(r.data)]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Jede Portion ist ein eigener Datensatz, damit offline auf mehreren
  /// Geräten Eingetragenes beim Abgleich zusammenkommt.
  Future<WaterEntry> addWater(String date, int ml) async {
    final e = WaterEntry(id: newId(), date: date, ml: ml, createdAt: nowMs);
    await _put(RecordKind.water, e.id, e.toJson());
    return e;
  }

  Future<WaterEntry?> undoLastWater(String date) async {
    final list = await water(date);
    if (list.isEmpty) return null;
    await _delete(RecordKind.water, list.last.id);
    return list.last;
  }

  // Gewicht

  Future<List<WeightEntry>> weights(String from, String to) async {
    final records = await store.byDate(RecordKind.weight, from, to);
    final list = [for (final r in records) WeightEntry.fromJson(r.data)]
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Der neueste Wert des Tages ersetzt den vorherigen. Trägt das aktuelle
  /// Gewicht auch ins Profil ein, damit die Ziele mitgehen.
  Future<void> saveWeight(WeightEntry e) async {
    await _put(RecordKind.weight, e.date, e.toJson());
    final latest = await weights('0000-00-00', '9999-99-99');
    final p = await profile();
    if (p != null && latest.isNotEmpty && latest.last.date == e.date) {
      await saveProfile(Profile.fromJson({...p.toJson(), 'weightKg': e.kg}));
    }
  }

  Future<void> deleteWeight(String date) => _delete(RecordKind.weight, date);

  // Aktivität

  Future<void> saveActivity(ActivityEntry a) =>
      _put(RecordKind.activity, a.id, a.toJson());

  Future<void> deleteActivity(String id) => _delete(RecordKind.activity, id);

  Future<List<ActivityEntry>> activities(String date) async => [
    for (final r in await store.byDate(RecordKind.activity, date, date))
      ActivityEntry.fromJson(r.data),
  ];

  // Zusammenfassung

  Future<DaySummary> summary(String date, Profile profile) async => DaySummary(
    date: date,
    entries: await diary(date),
    water: await water(date),
    activities: await activities(date),
    goals: calculateGoals(profile, year: parseDateKey(date).year),
    addActivityToBudget: profile.addActivityToBudget,
  );

  Future<List<DaySummary>> summaries(
    String lastDate,
    int days,
    Profile profile,
  ) async {
    final last = parseDateKey(lastDate);
    return [
      for (var i = days - 1; i >= 0; i--)
        await summary(
          dateKey(DateTime(last.year, last.month, last.day - i)),
          profile,
        ),
    ];
  }

  /// Alle Daten als einfache Struktur für den Export.
  Future<Map<String, Object?>> exportAll() async => {
    'format': 'bociva-export',
    'version': 1,
    'exportedAt': _clock().toUtc().toIso8601String(),
    for (final kind in RecordKind.all)
      kind: [for (final r in await store.all(kind)) r.data],
  };
}
