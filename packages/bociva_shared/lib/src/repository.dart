import 'dart:math';

import 'basic_foods.dart';
import 'goals.dart';
import 'models.dart';
import 'store.dart';
import 'streak.dart';

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
    final record = SyncRecord(
      kind: kind,
      id: id,
      updatedAt: stamp,
      data: deleted ? const {} : data,
      deleted: deleted,
    );
    // Was der Server ablehnen würde, wird gar nicht erst gespeichert.
    if (recordProblem(record) case final problem?) {
      throw InvalidRecordException(problem);
    }
    await store.put(record, dirty: true);
  }

  Future<void> _delete(String kind, String id) =>
      _put(kind, id, const {}, deleted: true);

  // Profil

  /// Das Gewicht kommt aus dem jüngsten Gewichtseintrag. So muss ein neuer
  /// Eintrag das Profil nicht umschreiben, was auf einem zweiten Gerät neuere
  /// Ziele mit einer alten Kopie überschreiben könnte.
  Future<Profile?> profile() async {
    final r = await store.get(RecordKind.profile, 'me');
    if (r == null || r.deleted) return null;
    final latest = await latestWeight();
    return Profile.fromJson({
      ...r.data,
      if (latest != null) 'weightKg': latest.kg,
    });
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
    // Nur beim ersten Mal speichern. Wie oft und wann ein Lebensmittel genutzt
    // wird, steht im Tagebuch; ein Neuschreiben hier überschriebe Änderungen
    // von anderen Geräten oder holte Gelöschtes zurück.
    if (await store.get(RecordKind.food, food.id) == null) {
      await saveFood(food.copyWith(lastUsedAt: entry.createdAt));
    }
    return entry;
  }

  // Lebensmittel

  Future<void> saveFood(Food f) => _put(RecordKind.food, f.id, f.toJson());

  Future<void> deleteFood(String id) => _delete(RecordKind.food, id);

  Future<List<Food>> savedFoods() async => [
    for (final r in await store.all(RecordKind.food)) Food.fromJson(r.data),
  ];

  /// Wann jedes Lebensmittel zuletzt eingetragen wurde, aus dem Tagebuch der
  /// letzten 90 Tage, sonst aus dem Zeitpunkt der ersten Nutzung.
  Future<Map<String, int>> _lastUse(List<Food> foods) async {
    final now = _clock();
    final from = dateKey(DateTime(now.year, now.month, now.day - 90));
    final used = {for (final f in foods) f.id: f.lastUsedAt};
    for (final r in await store.byDate(RecordKind.diary, from, '9999-12-31')) {
      final foodId = r.data['foodId'];
      final at = r.data['createdAt'];
      if (foodId is String && at is num && used.containsKey(foodId)) {
        used[foodId] = max(used[foodId]!, at.toInt());
      }
    }
    return used;
  }

  Future<List<Food>> recentFoods({int limit = 30}) async {
    final saved = await savedFoods();
    final used = await _lastUse(saved);
    final foods = saved.where((f) => used[f.id]! > 0).toList()
      ..sort((a, b) => used[b.id]!.compareTo(used[a.id]!));
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
    final used = await _lastUse(saved);
    final seen = used.keys.toSet();
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
        return s != 0 ? s : (used[b.id] ?? 0).compareTo(used[a.id] ?? 0);
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

  /// Der neueste Wert des Tages ersetzt den vorherigen. Die Ziele gehen über
  /// [profile] mit.
  Future<void> saveWeight(WeightEntry e) =>
      _put(RecordKind.weight, e.date, e.toJson());

  Future<WeightEntry?> latestWeight() async {
    WeightEntry? latest;
    for (final r in await store.all(RecordKind.weight)) {
      final e = WeightEntry.fromJson(r.data);
      if (e.kg > 0 && (latest == null || e.date.compareTo(latest.date) > 0)) {
        latest = e;
      }
    }
    return latest;
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

  // Rezepte

  Future<List<Recipe>> recipes() async => [
    for (final r in await store.all(RecordKind.recipe)) Recipe.fromJson(r.data),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Speichert das Rezept und sein Gegenstück als Lebensmittel. Bereits
  /// Eingetragenes bleibt unverändert, weil das Tagebuch eigene Werte hat.
  Future<void> saveRecipe(Recipe recipe) async {
    await _put(RecordKind.recipe, recipe.id, recipe.toJson());
    final previous = await store.get(
      RecordKind.food,
      Recipe.foodIdFor(recipe.id),
    );
    final lastUsedAt = previous == null || previous.deleted
        ? 0
        : Food.fromJson(previous.data).lastUsedAt;
    await saveFood(recipe.toFood(lastUsedAt: lastUsedAt));
  }

  Future<void> deleteRecipe(String id) async {
    await _delete(RecordKind.recipe, id);
    await deleteFood(Recipe.foodIdFor(id));
  }

  // Fasten

  Future<List<FastingSession>> fastingSessions() async => [
    for (final r in await store.all(RecordKind.fasting))
      FastingSession.fromJson(r.data),
  ]..sort((a, b) => b.startAt.compareTo(a.startAt));

  /// Wurde offline auf zwei Geräten gestartet, gilt das jüngste Fasten.
  Future<FastingSession?> activeFasting() async {
    for (final s in await fastingSessions()) {
      if (s.isActive) return s;
    }
    return null;
  }

  Future<FastingSession> startFasting(
    int targetHours, {
    DateTime? startAt,
  }) async {
    final now = _clock();
    final start = startAt == null || startAt.isAfter(now) ? now : startAt;
    final session = FastingSession(
      id: newId(),
      date: dateKey(start),
      startAt: start.millisecondsSinceEpoch,
      targetHours: targetHours,
    );
    await _put(RecordKind.fasting, session.id, session.toJson());
    return session;
  }

  Future<void> endFasting(FastingSession session) =>
      _put(RecordKind.fasting, session.id, session.ended(nowMs).toJson());

  Future<void> deleteFasting(String id) => _delete(RecordKind.fasting, id);

  // Serie

  /// Wie viele Tage bis [today] in Folge Essen eingetragen wurde.
  Future<Streak> streak(String today) async =>
      Streak.fromDates(await store.datesWith(RecordKind.diary), today);

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
