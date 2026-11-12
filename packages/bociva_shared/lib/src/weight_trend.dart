import 'models.dart';

/// Geglätteter Gewichtsverlauf mit Tempo und Prognose.
///
/// Einzelne Messungen schwanken durch Wasser und Mahlzeiten um ein bis zwei
/// Kilo. Der Trend glättet das exponentiell, gewichtet nach den Tagen
/// zwischen zwei Messungen: Nach einer Pause zählt die neue Messung mehr.
class WeightTrend {
  const WeightTrend._({
    required this.trend,
    required this.ratePerWeek,
    required this.eta,
    required this.reached,
    required this.awayFromTarget,
  });

  /// Anteil einer neuen Messung pro Tag.
  static const smoothing = 0.1;

  /// Über diesen Zeitraum wird das Tempo bestimmt.
  static const window = 28;

  factory WeightTrend.of(List<WeightEntry> entries, {double? target}) {
    final sorted = [...entries.where((e) => e.kg > 0)]
      ..sort((a, b) => a.date.compareTo(b.date));
    final trend = <double>[];
    DateTime? previous;
    for (final e in sorted) {
      final day = parseDateKey(e.date);
      if (trend.isEmpty) {
        trend.add(e.kg);
      } else {
        final gap = _days(previous!, day).clamp(1, 60);
        final weight = 1 - _pow(1 - smoothing, gap);
        trend.add(trend.last + weight * (e.kg - trend.last));
      }
      previous = day;
    }
    if (trend.isEmpty) {
      return const WeightTrend._(
        trend: [],
        ratePerWeek: null,
        eta: null,
        reached: false,
        awayFromTarget: false,
      );
    }

    // Tempo: Gerade durch die Trendwerte der letzten Wochen.
    final last = parseDateKey(sorted.last.date);
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < sorted.length; i++) {
      final x = -_days(parseDateKey(sorted[i].date), last).toDouble();
      if (x <= -window) continue;
      xs.add(x);
      ys.add(trend[i]);
    }
    double? rate;
    if (xs.length >= 3 && xs.last - xs.first >= 7) {
      rate = _slope(xs, ys) * 7;
    }

    final current = trend.last;
    var reached = false, away = false;
    DateTime? eta;
    if (target != null && target > 0) {
      final missing = target - current;
      if (missing.abs() < 0.3) {
        reached = true;
      } else if (rate != null && rate.abs() >= 0.05) {
        if (missing * rate > 0) {
          final days = (missing / rate * 7).round();
          // Weiter als zwei Jahre ist keine sinnvolle Prognose mehr.
          if (days <= 730) {
            eta = DateTime(last.year, last.month, last.day + days);
          }
        } else {
          away = true;
        }
      }
    }
    return WeightTrend._(
      trend: trend,
      ratePerWeek: rate,
      eta: eta,
      reached: reached,
      awayFromTarget: away,
    );
  }

  /// Ein Trendwert je Messung, in derselben Reihenfolge (nach Datum).
  final List<double> trend;

  /// Kilo pro Woche, negativ beim Abnehmen. Fehlt bei zu wenigen Messungen.
  final double? ratePerWeek;

  /// Wann das Zielgewicht beim jetzigen Tempo erreicht wäre.
  final DateTime? eta;

  /// Der Trend liegt schon am Ziel.
  final bool reached;

  /// Der Trend bewegt sich vom Ziel weg.
  final bool awayFromTarget;

  double? get current => trend.isEmpty ? null : trend.last;

  static int _days(DateTime a, DateTime b) => DateTime.utc(
    b.year,
    b.month,
    b.day,
  ).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

  static double _pow(double base, int exp) {
    var r = 1.0;
    for (var i = 0; i < exp; i++) {
      r *= base;
    }
    return r;
  }

  static double _slope(List<double> xs, List<double> ys) {
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var num = 0.0, den = 0.0;
    for (var i = 0; i < n; i++) {
      num += (xs[i] - mx) * (ys[i] - my);
      den += (xs[i] - mx) * (xs[i] - mx);
    }
    return den == 0 ? 0 : num / den;
  }
}
