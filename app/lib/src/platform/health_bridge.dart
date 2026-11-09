import 'package:bociva_shared/bociva_shared.dart';

import 'health_stub.dart' if (dart.library.ffi) 'health_native.dart';

class HealthDay {
  const HealthDay(this.date, this.steps, this.activeKcal);
  final String date;
  final int steps;
  final double activeKcal;
}

class HealthUnavailable implements Exception {
  const HealthUnavailable(this.message, {this.canInstall = false});
  final String message;
  final bool canInstall;
  @override
  String toString() => message;
}

/// Apple Health (dort landen auch Apple Watch, Fitness und Garmin Connect)
/// bzw. Health Connect unter Android.
abstract class HealthBridge {
  bool get supported;
  String get platformName;
  Future<bool> requestAccess({required bool write});
  Future<void> installProvider();
  Future<List<HealthDay>> readDays(int days);
  Future<List<WeightEntry>> readWeights(int days);
  Future<void> writeEntry(DiaryEntry entry);
  Future<void> deleteEntry(DiaryEntry entry);
  Future<void> writeWater(WaterEntry entry);
  Future<void> deleteWater(WaterEntry entry);
}

HealthBridge createHealthBridge() => createPlatformHealthBridge();

/// Zeitpunkt für Health: der eingetragene Tag, mit der Uhrzeit der Eingabe.
DateTime healthTime(String date, int createdAtMs) {
  final d = parseDateKey(date);
  final t = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  return DateTime(d.year, d.month, d.day, t.hour, t.minute, t.second);
}
