import 'dart:math';

double _d(Object? v, [double fallback = 0]) => switch (v) {
  num n when n.isFinite => n.toDouble(),
  String s => double.tryParse(s.replaceAll(',', '.')) ?? fallback,
  _ => fallback,
};

double? _dn(Object? v) => switch (v) {
  num n when n.isFinite => n.toDouble(),
  String s => double.tryParse(s.replaceAll(',', '.')),
  _ => null,
};

int _i(Object? v, [int fallback = 0]) => switch (v) {
  num n when n.isFinite => n.toInt(),
  String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Kalendertag in Ortszeit als `YYYY-MM-DD`.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

final _random = Random.secure();

/// Zufällige ID. Geräte erzeugen IDs offline, ohne sich abzustimmen.
String newId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyz';
  return List.generate(22, (_) => chars[_random.nextInt(chars.length)]).join();
}

/// Nährwerte. Je nach Zusammenhang für 100 g/ml oder für eine Portion.
class Nutrients {
  const Nutrients({
    this.kcal = 0,
    this.protein = 0,
    this.carbs = 0,
    this.fat = 0,
    this.sugar,
    this.fiber,
    this.saturatedFat,
    this.salt,
  });

  factory Nutrients.fromJson(Map<String, Object?> j) => Nutrients(
    kcal: _d(j['kcal']),
    protein: _d(j['protein']),
    carbs: _d(j['carbs']),
    fat: _d(j['fat']),
    sugar: _dn(j['sugar']),
    fiber: _dn(j['fiber']),
    saturatedFat: _dn(j['saturatedFat']),
    salt: _dn(j['salt']),
  );

  final double kcal, protein, carbs, fat;
  final double? sugar, fiber, saturatedFat, salt;

  static const zero = Nutrients();

  Nutrients scaled(double factor) => Nutrients(
    kcal: kcal * factor,
    protein: protein * factor,
    carbs: carbs * factor,
    fat: fat * factor,
    sugar: sugar == null ? null : sugar! * factor,
    fiber: fiber == null ? null : fiber! * factor,
    saturatedFat: saturatedFat == null ? null : saturatedFat! * factor,
    salt: salt == null ? null : salt! * factor,
  );

  Nutrients operator +(Nutrients o) => Nutrients(
    kcal: kcal + o.kcal,
    protein: protein + o.protein,
    carbs: carbs + o.carbs,
    fat: fat + o.fat,
    sugar: _sum(sugar, o.sugar),
    fiber: _sum(fiber, o.fiber),
    saturatedFat: _sum(saturatedFat, o.saturatedFat),
    salt: _sum(salt, o.salt),
  );

  static double? _sum(double? a, double? b) =>
      a == null && b == null ? null : (a ?? 0) + (b ?? 0);

  Map<String, Object?> toJson() => {
    'kcal': kcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'sugar': ?sugar,
    'fiber': ?fiber,
    'saturatedFat': ?saturatedFat,
    'salt': ?salt,
  };
}

enum Meal {
  breakfast('Frühstück'),
  lunch('Mittagessen'),
  dinner('Abendessen'),
  snack('Snacks');

  const Meal(this.label);
  final String label;

  /// Vorschlag nach Tageszeit.
  static Meal forTime(DateTime t) => switch (t.hour) {
    >= 4 && < 11 => Meal.breakfast,
    >= 11 && < 15 => Meal.lunch,
    >= 17 && < 22 => Meal.dinner,
    _ => Meal.snack,
  };
}

enum FoodSource { custom, openFoodFacts, builtin, ai, recipe }

class Serving {
  const Serving(this.name, this.amount);

  factory Serving.fromJson(Map<String, Object?> j) =>
      Serving('${j['name'] ?? ''}', _d(j['amount']));

  final String name;

  /// Menge in g bzw. ml.
  final double amount;

  Map<String, Object?> toJson() => {'name': name, 'amount': amount};
}

class Food {
  const Food({
    required this.id,
    required this.name,
    required this.per100,
    this.brand,
    this.barcode,
    this.unit = 'g',
    this.servings = const [],
    this.source = FoodSource.custom,
    this.lastUsedAt = 0,
  });

  factory Food.fromJson(Map<String, Object?> j) => Food(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    brand: j['brand'] as String?,
    barcode: j['barcode'] as String?,
    unit: j['unit'] == 'ml' ? 'ml' : 'g',
    per100: Nutrients.fromJson(_map(j['per100'])),
    servings: [
      for (final s in (j['servings'] as List? ?? const []))
        Serving.fromJson(_map(s)),
    ],
    source: _enum(FoodSource.values, j['source'], FoodSource.custom),
    lastUsedAt: _i(j['lastUsedAt']),
  );

  final String id, name, unit;
  final String? brand, barcode;
  final Nutrients per100;
  final List<Serving> servings;
  final FoodSource source;
  final int lastUsedAt;

  Nutrients forAmount(double amount) => per100.scaled(amount / 100);

  Food copyWith({int? lastUsedAt}) => Food(
    id: id,
    name: name,
    brand: brand,
    barcode: barcode,
    unit: unit,
    per100: per100,
    servings: servings,
    source: source,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brand': ?brand,
    'barcode': ?barcode,
    'unit': unit,
    'per100': per100.toJson(),
    'servings': [for (final s in servings) s.toJson()],
    'source': source.name,
    'lastUsedAt': lastUsedAt,
  };
}

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.cast<String, Object?>() : const {};

/// Tagebucheintrag. Die Nährwerte sind eine Momentaufnahme: Ändert sich ein
/// Lebensmittel später, bleibt die Vergangenheit unverändert.
class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.date,
    required this.meal,
    required this.name,
    required this.amount,
    required this.nutrients,
    required this.createdAt,
    this.unit = 'g',
    this.brand,
    this.foodId,
    this.estimated = false,
  });

  factory DiaryEntry.fromJson(Map<String, Object?> j) => DiaryEntry(
    id: '${j['id']}',
    date: '${j['date']}',
    meal: _enum(Meal.values, j['meal'], Meal.snack),
    name: '${j['name'] ?? ''}',
    brand: j['brand'] as String?,
    foodId: j['foodId'] as String?,
    amount: _d(j['amount']),
    unit: j['unit'] == 'ml' ? 'ml' : 'g',
    nutrients: Nutrients.fromJson(_map(j['nutrients'])),
    createdAt: _i(j['createdAt']),
    estimated: j['estimated'] == true,
  );

  final String id, date, name, unit;
  final String? brand, foodId;
  final Meal meal;
  final double amount;
  final Nutrients nutrients;
  final int createdAt;

  /// Geschätzt (KI), nicht aus einer Nährwerttabelle.
  final bool estimated;

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'meal': meal.name,
    'name': name,
    'brand': ?brand,
    'foodId': ?foodId,
    'amount': amount,
    'unit': unit,
    'nutrients': nutrients.toJson(),
    'createdAt': createdAt,
    'estimated': estimated,
  };
}

class WaterEntry {
  const WaterEntry({
    required this.id,
    required this.date,
    required this.ml,
    required this.createdAt,
  });

  factory WaterEntry.fromJson(Map<String, Object?> j) => WaterEntry(
    id: '${j['id']}',
    date: '${j['date']}',
    ml: _i(j['ml']),
    createdAt: _i(j['createdAt']),
  );

  final String id, date;
  final int ml, createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'ml': ml,
    'createdAt': createdAt,
  };
}

class WeightEntry {
  const WeightEntry({required this.date, required this.kg, this.source});

  factory WeightEntry.fromJson(Map<String, Object?> j) => WeightEntry(
    date: '${j['date']}',
    kg: _d(j['kg']),
    source: j['source'] as String?,
  );

  /// Ein Wert pro Tag: das Datum ist zugleich die ID.
  final String date;
  final double kg;
  final String? source;

  Map<String, Object?> toJson() => {
    'id': date,
    'date': date,
    'kg': kg,
    'source': ?source,
  };
}

enum ActivityKind { daySummary, workout }

/// Aktivität aus Apple Health / Health Connect oder einer FIT-Datei.
class ActivityEntry {
  const ActivityEntry({
    required this.id,
    required this.date,
    required this.kind,
    required this.source,
    this.activeKcal = 0,
    this.steps = 0,
    this.title,
    this.minutes = 0,
    this.distanceM = 0,
  });

  factory ActivityEntry.fromJson(Map<String, Object?> j) => ActivityEntry(
    id: '${j['id']}',
    date: '${j['date']}',
    kind: _enum(ActivityKind.values, j['kind'], ActivityKind.workout),
    source: '${j['source'] ?? ''}',
    activeKcal: _d(j['activeKcal']),
    steps: _i(j['steps']),
    title: j['title'] as String?,
    minutes: _i(j['minutes']),
    distanceM: _d(j['distanceM']),
  );

  final String id, date, source;
  final ActivityKind kind;
  final double activeKcal, distanceM;
  final int steps, minutes;
  final String? title;

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'kind': kind.name,
    'source': source,
    'activeKcal': activeKcal,
    'steps': steps,
    'title': ?title,
    'minutes': minutes,
    'distanceM': distanceM,
  };
}

enum Sex {
  female('Weiblich'),
  male('Männlich'),
  other('Divers');

  const Sex(this.label);
  final String label;
}

enum ActivityLevel {
  sedentary('Überwiegend sitzend', 1.2),
  light('Leicht aktiv', 1.375),
  moderate('Mäßig aktiv', 1.55),
  active('Sehr aktiv', 1.725);

  const ActivityLevel(this.label, this.factor);
  final String label;
  final double factor;
}

enum GoalType {
  lose('Abnehmen'),
  maintain('Gewicht halten'),
  gain('Zunehmen');

  const GoalType(this.label);
  final String label;
}

class Profile {
  const Profile({
    required this.sex,
    required this.birthYear,
    required this.heightCm,
    required this.weightKg,
    this.activity = ActivityLevel.light,
    this.goal = GoalType.maintain,
    this.weeklyRateKg = 0.25,
    this.targetWeightKg,
    this.kcalOverride,
    this.waterOverrideMl,
    this.proteinPct = 20,
    this.carbsPct = 50,
    this.fatPct = 30,
    this.addActivityToBudget = false,
    this.fastingEnabled = false,
  });

  factory Profile.fromJson(Map<String, Object?> j) => Profile(
    sex: _enum(Sex.values, j['sex'], Sex.other),
    birthYear: _i(j['birthYear'], 1990),
    heightCm: _d(j['heightCm'], 170),
    weightKg: _d(j['weightKg'], 70),
    activity: _enum(ActivityLevel.values, j['activity'], ActivityLevel.light),
    goal: _enum(GoalType.values, j['goal'], GoalType.maintain),
    weeklyRateKg: _d(j['weeklyRateKg'], 0.25),
    targetWeightKg: _dn(j['targetWeightKg']),
    kcalOverride: _dn(j['kcalOverride']),
    waterOverrideMl: _dn(j['waterOverrideMl'])?.toInt(),
    proteinPct: _i(j['proteinPct'], 20),
    carbsPct: _i(j['carbsPct'], 50),
    fatPct: _i(j['fatPct'], 30),
    addActivityToBudget: j['addActivityToBudget'] == true,
    fastingEnabled: j['fastingEnabled'] == true,
  );

  final Sex sex;
  final int birthYear;
  final double heightCm, weightKg, weeklyRateKg;
  final ActivityLevel activity;
  final GoalType goal;
  final double? targetWeightKg, kcalOverride;
  final int? waterOverrideMl;
  final int proteinPct, carbsPct, fatPct;

  /// Das Aktivitätsniveau steckt schon im Grundbedarf. Wer verbrannte
  /// Kalorien zusätzlich gutschreibt, wählt besser „Überwiegend sitzend“.
  final bool addActivityToBudget;

  /// Fasten ist nicht für alle geeignet und deshalb zum Einschalten.
  final bool fastingEnabled;

  Profile withFastingEnabled(bool enabled) =>
      Profile.fromJson({...toJson(), 'fastingEnabled': enabled});

  Map<String, Object?> toJson() => {
    'id': 'me',
    'sex': sex.name,
    'birthYear': birthYear,
    'heightCm': heightCm,
    'weightKg': weightKg,
    'activity': activity.name,
    'goal': goal.name,
    'weeklyRateKg': weeklyRateKg,
    'targetWeightKg': ?targetWeightKg,
    'kcalOverride': ?kcalOverride,
    'waterOverrideMl': ?waterOverrideMl,
    'proteinPct': proteinPct,
    'carbsPct': carbsPct,
    'fatPct': fatPct,
    'addActivityToBudget': addActivityToBudget,
    'fastingEnabled': fastingEnabled,
  };
}

/// Zutat eines Rezepts. Die Nährwerte sind eine Momentaufnahme für die Menge.
class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.amount,
    required this.nutrients,
    this.unit = 'g',
    this.foodId,
  });

  factory RecipeIngredient.fromFood(Food food, double amount) =>
      RecipeIngredient(
        name: food.name,
        amount: amount,
        unit: food.unit,
        foodId: food.id,
        nutrients: food.forAmount(amount),
      );

  factory RecipeIngredient.fromJson(Map<String, Object?> j) => RecipeIngredient(
    name: '${j['name'] ?? ''}',
    amount: _d(j['amount']),
    unit: j['unit'] == 'ml' ? 'ml' : 'g',
    foodId: j['foodId'] as String?,
    nutrients: Nutrients.fromJson(_map(j['nutrients'])),
  );

  final String name, unit;
  final String? foodId;
  final double amount;
  final Nutrients nutrients;

  Map<String, Object?> toJson() => {
    'name': name,
    'amount': amount,
    'unit': unit,
    'foodId': ?foodId,
    'nutrients': nutrients.toJson(),
  };
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.servings,
    required this.ingredients,
    this.note,
  });

  factory Recipe.fromJson(Map<String, Object?> j) => Recipe(
    id: '${j['id']}',
    name: '${j['name'] ?? ''}',
    servings: max(1, _i(j['servings'], 1)),
    note: j['note'] as String?,
    ingredients: [
      for (final i in (j['ingredients'] as List? ?? const []))
        RecipeIngredient.fromJson(_map(i)),
    ],
  );

  final String id, name;
  final int servings;
  final String? note;
  final List<RecipeIngredient> ingredients;

  /// Summe der Zutaten. Gramm und Milliliter werden gleichgesetzt; für die
  /// Portionsrechnung reicht das.
  double get totalAmount => ingredients.fold(0, (sum, i) => sum + i.amount);

  Nutrients get total =>
      ingredients.fold(Nutrients.zero, (sum, i) => sum + i.nutrients);

  Nutrients get perServing => total.scaled(1 / servings);

  double get servingAmount => totalAmount / servings;

  /// Das Rezept als Lebensmittel, damit Suche und Tagebuch es wie jedes andere
  /// behandeln.
  Food toFood({int lastUsedAt = 0}) => Food(
    id: foodIdFor(id),
    name: name,
    source: FoodSource.recipe,
    per100: total.scaled(100 / max(totalAmount, 1)),
    servings: [Serving('1 Portion', servingAmount)],
    lastUsedAt: lastUsedAt,
  );

  static String foodIdFor(String recipeId) => 'recipe-$recipeId';

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'servings': servings,
    'note': ?note,
    'ingredients': [for (final i in ingredients) i.toJson()],
  };
}

/// Fastenfenster, die die App anbietet. Längeres Fasten gehört in ärztliche
/// Begleitung und lässt sich hier nicht einstellen.
const fastingPlans = [14, 16, 18, 20];

class FastingSession {
  const FastingSession({
    required this.id,
    required this.date,
    required this.startAt,
    required this.targetHours,
    this.endAt,
  });

  factory FastingSession.fromJson(Map<String, Object?> j) => FastingSession(
    id: '${j['id']}',
    date: '${j['date']}',
    startAt: _i(j['startAt']),
    targetHours: _i(j['targetHours'], 16),
    endAt: j['endAt'] == null ? null : _i(j['endAt']),
  );

  final String id, date;
  final int startAt, targetHours;
  final int? endAt;

  bool get isActive => endAt == null;

  Duration get target => Duration(hours: targetHours);

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startAt);

  DateTime get targetEnd => start.add(target);

  Duration elapsed(DateTime now) {
    final end = endAt == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(endAt!);
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  double progress(DateTime now) => elapsed(now).inSeconds / target.inSeconds;

  FastingSession ended(int at) => FastingSession(
    id: id,
    date: date,
    startAt: startAt,
    targetHours: targetHours,
    endAt: at,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date,
    'startAt': startAt,
    'targetHours': targetHours,
    'endAt': ?endAt,
  };
}
