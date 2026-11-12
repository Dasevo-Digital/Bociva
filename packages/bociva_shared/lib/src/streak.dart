import 'models.dart';

/// Wie viele Tage in Folge Essen eingetragen wurde.
///
/// Ein Tag zählt, sobald er mindestens einen Tagebucheintrag hat. Ist heute
/// noch nichts eingetragen, hält die Serie bis Mitternacht: Sie endet dann
/// gestern und lässt sich heute noch verlängern.
class Streak {
  const Streak({
    required this.today,
    required this.current,
    required this.longest,
    required this.todayDone,
    required this.days,
  });

  /// Ab diesen Längen gibt es eine besondere Würdigung.
  static const milestones = [3, 7, 14, 30, 50, 100, 150, 200, 365, 500, 1000];

  factory Streak.fromDates(Set<String> dates, String today) {
    final days = {
      for (final d in dates)
        if (d.compareTo(today) <= 0) d,
    };
    final start = parseDateKey(today);
    String back(int i) =>
        dateKey(DateTime(start.year, start.month, start.day - i));

    final todayDone = days.contains(today);
    var current = 0;
    for (var i = todayDone ? 0 : 1; days.contains(back(i)); i++) {
      current++;
    }

    var longest = 0, run = 0;
    String? previous;
    for (final d in days.toList()..sort()) {
      if (previous != null) {
        final p = parseDateKey(previous);
        run = dateKey(DateTime(p.year, p.month, p.day + 1)) == d ? run + 1 : 1;
      } else {
        run = 1;
      }
      if (run > longest) longest = run;
      previous = d;
    }

    return Streak(
      today: today,
      current: current,
      longest: longest,
      todayDone: todayDone,
      days: days,
    );
  }

  final String today;
  final int current, longest;
  final bool todayDone;

  /// Alle Tage mit Einträgen bis heute.
  final Set<String> days;

  int get totalDays => days.length;

  /// Gestern noch eingetragen, heute nicht: Die Serie reißt um Mitternacht.
  bool get atRisk => current > 0 && !todayDone;

  bool get isMilestone => milestones.contains(current);

  int? get nextMilestone {
    for (final m in milestones) {
      if (m > current) return m;
    }
    return null;
  }

  /// Ob an [date] eingetragen wurde.
  bool tracked(String date) => days.contains(date);

  /// Die letzten [count] Tage bis heute, der älteste zuerst.
  List<String> lastDays(int count) {
    final t = parseDateKey(today);
    return [
      for (var i = count - 1; i >= 0; i--)
        dateKey(DateTime(t.year, t.month, t.day - i)),
    ];
  }
}
