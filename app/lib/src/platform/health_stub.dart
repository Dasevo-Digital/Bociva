import 'package:bociva_shared/bociva_shared.dart';

import 'health_bridge.dart';

HealthBridge createPlatformHealthBridge() => _NoHealth();

class _NoHealth implements HealthBridge {
  @override
  bool get supported => false;
  @override
  String get platformName => '';
  @override
  Future<bool> requestAccess({required bool write}) async => false;
  @override
  Future<void> installProvider() async {}
  @override
  Future<List<HealthDay>> readDays(int days) async => const [];
  @override
  Future<List<WeightEntry>> readWeights(int days) async => const [];
  @override
  Future<void> writeEntry(DiaryEntry entry) async {}
  @override
  Future<void> deleteEntry(DiaryEntry entry) async {}
  @override
  Future<void> writeWater(WaterEntry entry) async {}
  @override
  Future<void> deleteWater(WaterEntry entry) async {}
}
