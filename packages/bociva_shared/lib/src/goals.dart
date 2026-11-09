import 'models.dart';

/// Tagesziele, aus dem Profil berechnet.
class DailyGoals {
  const DailyGoals({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.waterMl,
    this.limitedToMinimum = false,
  });

  final double kcal, protein, carbs, fat;
  final int waterMl;

  /// Das rechnerische Ziel lag unter der Untergrenze und wurde angehoben.
  final bool limitedToMinimum;
}

/// Grundumsatz nach Mifflin-St Jeor in kcal/Tag.
double basalMetabolicRate(Profile p, {required int year}) {
  final age = year - p.birthYear;
  final base = 10 * p.weightKg + 6.25 * p.heightCm - 5 * age;
  return base +
      switch (p.sex) {
        Sex.male => 5,
        Sex.female => -161,
        Sex.other => -78,
      };
}

/// Maximal erlaubte Änderung pro Woche; schnelleres Abnehmen rechnet die App
/// bewusst nicht aus.
const maxWeeklyRateKg = 0.75;

const _kcalPerKg = 7700.0;

double minimumDailyKcal(Sex sex) => switch (sex) {
  Sex.male => 1500,
  Sex.female => 1200,
  Sex.other => 1350,
};

DailyGoals calculateGoals(Profile p, {required int year}) {
  final maintenance = basalMetabolicRate(p, year: year) * p.activity.factor;
  final rate = p.weeklyRateKg.clamp(0, maxWeeklyRateKg);
  final delta = rate * _kcalPerKg / 7;
  var kcal = switch (p.goal) {
    GoalType.lose => maintenance - delta,
    GoalType.maintain => maintenance,
    GoalType.gain => maintenance + delta,
  };
  var limited = false;
  final minimum = minimumDailyKcal(p.sex);
  if (p.kcalOverride != null) {
    kcal = p.kcalOverride!;
  } else if (kcal < minimum) {
    kcal = minimum;
    limited = true;
  }
  final water = p.waterOverrideMl ?? ((p.weightKg * 35 / 50).round() * 50);
  return DailyGoals(
    kcal: kcal.roundToDouble(),
    protein: kcal * p.proteinPct / 100 / 4,
    carbs: kcal * p.carbsPct / 100 / 4,
    fat: kcal * p.fatPct / 100 / 9,
    waterMl: water,
    limitedToMinimum: limited,
  );
}

/// Alles, was die Tagesansicht und die Statistik brauchen.
class DaySummary {
  const DaySummary({
    required this.date,
    required this.entries,
    required this.water,
    required this.activities,
    required this.goals,
    required this.addActivityToBudget,
  });

  final String date;
  final List<DiaryEntry> entries;
  final List<WaterEntry> water;
  final List<ActivityEntry> activities;
  final DailyGoals goals;
  final bool addActivityToBudget;

  Nutrients get consumed =>
      entries.fold(Nutrients.zero, (sum, e) => sum + e.nutrients);

  Nutrients consumedIn(Meal meal) => entries
      .where((e) => e.meal == meal)
      .fold(Nutrients.zero, (sum, e) => sum + e.nutrients);

  int get waterMl => water.fold(0, (sum, w) => sum + w.ml);

  int get steps => activities
      .where((a) => a.kind == ActivityKind.daySummary)
      .fold(0, (max, a) => a.steps > max ? a.steps : max);

  /// Eine Tagessumme aus Health enthält die Trainings des Tages bereits.
  /// Der größere Wert zählt, damit dieselbe Einheit nicht doppelt zählt, wenn
  /// sie zusätzlich als FIT-Datei importiert wurde.
  double get burnedKcal {
    double day = 0, workouts = 0;
    for (final a in activities) {
      if (a.kind == ActivityKind.daySummary) {
        if (a.activeKcal > day) day = a.activeKcal;
      } else {
        workouts += a.activeKcal;
      }
    }
    return day > workouts ? day : workouts;
  }

  double get budgetKcal => goals.kcal + (addActivityToBudget ? burnedKcal : 0);

  double get remainingKcal => budgetKcal - consumed.kcal;
}
