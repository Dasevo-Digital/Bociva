import 'dart:io';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:health/health.dart';

import 'health_bridge.dart';

HealthBridge createPlatformHealthBridge() => _NativeHealth();

class _NativeHealth implements HealthBridge {
  final _health = Health();
  bool _configured = false;

  @override
  bool get supported => Platform.isIOS || Platform.isAndroid;

  @override
  String get platformName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

  static const _read = [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.WEIGHT,
  ];
  static const _write = [HealthDataType.NUTRITION, HealthDataType.WATER];

  Future<void> _ready() async {
    if (!_configured) {
      await _health.configure();
      _configured = true;
    }
    if (Platform.isAndroid && !await _health.isHealthConnectAvailable()) {
      throw const HealthUnavailable(
        'Health Connect ist auf diesem Gerät nicht installiert.',
        canInstall: true,
      );
    }
  }

  @override
  Future<void> installProvider() => _health.installHealthConnect();

  @override
  Future<bool> requestAccess({required bool write}) async {
    await _ready();
    return _health.requestAuthorization(
      [..._read, if (write) ..._write],
      permissions: [
        for (final _ in _read) HealthDataAccess.READ,
        if (write)
          for (final _ in _write) HealthDataAccess.WRITE,
      ],
    );
  }

  /// Sind mehrere Quellen verbunden (etwa Uhr und Telefon), melden sie
  /// dieselbe Bewegung. Gezählt wird nur die Quelle mit dem höchsten Wert.
  double _bestSource(Iterable<HealthDataPoint> points) {
    final bySource = <String, double>{};
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) {
        bySource.update(
          point.sourceId,
          (v) => v + value.numericValue.toDouble(),
          ifAbsent: () => value.numericValue.toDouble(),
        );
      }
    }
    return bySource.values.fold(0, (max, v) => v > max ? v : max);
  }

  @override
  Future<List<HealthDay>> readDays(int days) async {
    await _ready();
    final now = DateTime.now();
    final result = <HealthDay>[];
    for (var i = 0; i < days; i++) {
      final start = DateTime(now.year, now.month, now.day - i);
      final end = DateTime(start.year, start.month, start.day + 1);
      final points = await _health.getHealthDataFromTypes(
        types: const [
          HealthDataType.STEPS,
          HealthDataType.ACTIVE_ENERGY_BURNED,
        ],
        startTime: start,
        endTime: end.isAfter(now) ? now : end,
      );
      final steps = _bestSource(
        points.where((p) => p.type == HealthDataType.STEPS),
      ).round();
      final kcal = _bestSource(
        points.where((p) => p.type == HealthDataType.ACTIVE_ENERGY_BURNED),
      );
      if (steps > 0 || kcal > 0) {
        result.add(HealthDay(dateKey(start), steps, kcal));
      }
    }
    return result;
  }

  @override
  Future<List<WeightEntry>> readWeights(int days) async {
    await _ready();
    final now = DateTime.now();
    final points = await _health.getHealthDataFromTypes(
      types: const [HealthDataType.WEIGHT],
      startTime: now.subtract(Duration(days: days)),
      endTime: now,
    );
    points.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final byDate = <String, WeightEntry>{};
    for (final point in points) {
      final value = point.value;
      if (value is NumericHealthValue) {
        final date = dateKey(point.dateFrom);
        byDate[date] = WeightEntry(
          date: date,
          kg: value.numericValue.toDouble(),
          source: 'health',
        );
      }
    }
    return byDate.values.toList();
  }

  MealType _mealType(Meal meal) => switch (meal) {
    Meal.breakfast => MealType.BREAKFAST,
    Meal.lunch => MealType.LUNCH,
    Meal.dinner => MealType.DINNER,
    Meal.snack => MealType.SNACK,
  };

  @override
  Future<void> writeEntry(DiaryEntry e) async {
    await _ready();
    final start = healthTime(e.date, e.createdAt);
    await _health.writeMeal(
      mealType: _mealType(e.meal),
      startTime: start,
      endTime: start.add(const Duration(seconds: 1)),
      name: e.name,
      caloriesConsumed: e.nutrients.kcal,
      protein: e.nutrients.protein,
      carbohydrates: e.nutrients.carbs,
      fatTotal: e.nutrients.fat,
    );
  }

  @override
  Future<void> deleteEntry(DiaryEntry e) async {
    await _ready();
    final start = healthTime(e.date, e.createdAt);
    await _health.delete(
      type: HealthDataType.NUTRITION,
      startTime: start,
      endTime: start.add(const Duration(seconds: 1)),
    );
  }

  @override
  Future<void> writeWater(WaterEntry e) async {
    await _ready();
    final start = healthTime(e.date, e.createdAt);
    await _health.writeHealthData(
      value: e.ml / 1000,
      unit: HealthDataUnit.LITER,
      type: HealthDataType.WATER,
      startTime: start,
      endTime: start.add(const Duration(seconds: 1)),
      recordingMethod: RecordingMethod.manual,
    );
  }

  @override
  Future<void> deleteWater(WaterEntry e) async {
    await _ready();
    final start = healthTime(e.date, e.createdAt);
    await _health.delete(
      type: HealthDataType.WATER,
      startTime: start,
      endTime: start.add(const Duration(seconds: 1)),
    );
  }
}
