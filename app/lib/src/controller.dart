import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'platform/health_bridge.dart';
import 'platform/store.dart';

enum AiMode { off, server, custom }

class ControllerScope extends InheritedNotifier<AppController> {
  const ControllerScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ControllerScope>()!.notifier!;
}

extension ControllerContext on BuildContext {
  AppController get app => ControllerScope.of(this);
}

/// Zustand der App. Oberflächen lesen hier und melden Änderungen hierher;
/// nach jeder Änderung wird der Tag neu berechnet und abgeglichen.
class AppController extends ChangeNotifier {
  static const _secrets = FlutterSecureStorage();
  static const _kDbKey = 'db_key';
  static const _kSession = 'session';
  static const _kAi = 'ai_config';
  static const _userAgent = 'Bociva/0.1';

  late LocalStore _store;
  late BocivaRepository repo;
  final HealthBridge health = createHealthBridge();

  bool ready = false;
  String? startError;

  Profile? profile;
  String date = dateKey(DateTime.now());
  DaySummary? day;

  /// Steigt bei jeder Datenänderung, damit z. B. die Statistik neu lädt.
  int dataVersion = 0;

  ApiClient? api;
  String? username, serverUrl, syncError;
  bool isAdmin = false, syncing = false, serverAi = false;
  bool needsLogin = false;
  DateTime? lastSync;

  AiMode aiMode = AiMode.off;
  AiConfig? customAi;

  bool healthEnabled = false, healthWrite = false;

  Timer? _syncDebounce, _syncTimer;
  DateTime? _lastHealthSync;

  /// Der Browser braucht immer einen Server; er ist der, der ihn ausliefert.
  bool get mustConnect => kIsWeb && api == null;

  bool get isConnected => api != null;

  FoodLookup get foodLookup =>
      api ?? OpenFoodFactsClient(userAgent: _userAgent);

  AiBackend? get ai => switch (aiMode) {
    AiMode.server when api != null && serverAi => api,
    AiMode.custom when customAi?.isComplete ?? false => ChatCompletionsClient(
      customAi!,
    ),
    _ => null,
  };

  /// Wohin Fotos und Texte bei einer Analyse gehen.
  String? get aiDestination => switch (aiMode) {
    AiMode.server when api != null && serverAi => api!.base.host,
    AiMode.custom when customAi?.isComplete ?? false => Uri.tryParse(
      customAi!.baseUrl,
    )?.host,
    _ => null,
  };

  Future<String> _databaseKey() async {
    var key = await _secrets.read(key: _kDbKey);
    if (key == null) {
      final random = Random.secure();
      key = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _secrets.write(key: _kDbKey, value: key);
    }
    return key;
  }

  Future<void> start() async {
    try {
      _store = await openLocalStore(_databaseKey);
      repo = BocivaRepository(_store);
      await _loadSettings();
      await _restoreSession();
      await reload(notify: false);
      if (api != null) {
        await syncNow();
      }
      _syncTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => unawaited(syncNow()),
      );
      ready = true;
      notifyListeners();
      unawaited(syncHealth());
    } on Object catch (e, stack) {
      debugPrint('$e\n$stack');
      startError =
          'Bociva konnte nicht starten. Die Datenablage ließ sich '
          'nicht öffnen.';
      notifyListeners();
    }
  }

  Future<void> _loadSettings() async {
    final mode = await _store.meta('ai.mode');
    aiMode = AiMode.values.firstWhere(
      (m) => m.name == mode,
      orElse: () => AiMode.off,
    );
    final raw = await _secrets.read(key: _kAi);
    if (raw != null) {
      final j = jsonDecode(raw) as Map;
      customAi = AiConfig(
        baseUrl: '${j['baseUrl']}',
        model: '${j['model']}',
        apiKey: j['apiKey'] as String?,
      );
    }
    healthEnabled = await _store.meta('health.enabled') == '1';
    healthWrite = await _store.meta('health.write') == '1';
  }

  Future<void> _restoreSession() async {
    final raw = await _secrets.read(key: _kSession);
    if (raw == null) return;
    final j = jsonDecode(raw) as Map;
    final base = Uri.parse('${j['url']}');
    if (kIsWeb && base.origin != Uri.base.origin) return;
    api = ApiClient(base, token: j['token'] as String);
    serverUrl = base.toString();
    username = j['username'] as String?;
    isAdmin = j['isAdmin'] == true;
    unawaited(_refreshServerInfo());
  }

  Future<void> _refreshServerInfo() async {
    try {
      final info = await api?.info();
      if (info == null) return;
      serverAi = info.aiEnabled;
      if (serverAi && aiMode == AiMode.off && kIsWeb) aiMode = AiMode.server;
      notifyListeners();
    } on ApiException {
      // Offline: Der Abgleich meldet das.
    }
  }

  Future<void> reload({bool notify = true}) async {
    profile = await repo.profile();
    day = profile == null ? null : await repo.summary(date, profile!);
    dataVersion++;
    if (notify) notifyListeners();
  }

  void _changed() {
    _syncDebounce?.cancel();
    if (api == null) return;
    // Im Browser sind die Daten nur im Speicher, also sofort hoch.
    _syncDebounce = Timer(
      Duration(milliseconds: kIsWeb ? 100 : 2000),
      () => unawaited(syncNow()),
    );
  }

  Future<void> goToDate(String newDate) async {
    date = newDate;
    await reload();
  }

  Future<void> shiftDate(int days) {
    final d = parseDateKey(date);
    return goToDate(dateKey(DateTime(d.year, d.month, d.day + days)));
  }

  bool get isToday => date == dateKey(DateTime.now());

  // Eingaben

  Future<void> saveProfile(Profile p) async {
    await repo.saveProfile(p);
    await reload();
    _changed();
  }

  Future<void> logFood(Food food, Meal meal, double amount) async {
    final entry = await repo.logFood(
      food,
      date: date,
      meal: meal,
      amount: amount,
    );
    await reload();
    _changed();
    if (healthWrite) await _quietly(() => health.writeEntry(entry));
  }

  Future<void> updateEntry(DiaryEntry e, double amount) async {
    final base = e.amount > 0 ? e.amount : 1.0;
    final updated = DiaryEntry(
      id: e.id,
      date: e.date,
      meal: e.meal,
      name: e.name,
      brand: e.brand,
      foodId: e.foodId,
      amount: amount,
      unit: e.unit,
      nutrients: e.nutrients.scaled(amount / base),
      createdAt: e.createdAt,
      estimated: e.estimated,
    );
    await repo.saveDiary(updated);
    await reload();
    _changed();
    if (healthWrite) {
      await _quietly(() async {
        await health.deleteEntry(e);
        await health.writeEntry(updated);
      });
    }
  }

  Future<void> deleteEntry(DiaryEntry e) async {
    await repo.deleteDiary(e.id);
    await reload();
    _changed();
    if (healthWrite) await _quietly(() => health.deleteEntry(e));
  }

  Future<void> addWater(int ml) async {
    final e = await repo.addWater(date, ml);
    await reload();
    _changed();
    if (healthWrite) await _quietly(() => health.writeWater(e));
  }

  Future<void> undoWater() async {
    final e = await repo.undoLastWater(date);
    await reload();
    _changed();
    if (healthWrite && e != null) await _quietly(() => health.deleteWater(e));
  }

  Future<void> saveWeight(double kg, {String? onDate}) async {
    await repo.saveWeight(WeightEntry(date: onDate ?? date, kg: kg));
    await reload();
    _changed();
  }

  Future<void> saveCustomFood(Food food) async {
    await repo.saveFood(food);
    dataVersion++;
    notifyListeners();
    _changed();
  }

  Future<Food?> lookupBarcode(String code) async =>
      await repo.foodByBarcode(code) ?? await foodLookup.byBarcode(code);

  Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      debugPrint('Health: $e');
    }
  }

  // Server

  Future<int> localRecordCount() => _store.countLive();

  /// Meldet an und führt die Daten zusammen. Mit [register] wird ein Konto
  /// mit Einladungscode angelegt. Ist [keepLocal] aus, werden die Daten dieses
  /// Geräts durch die des Kontos ersetzt.
  Future<void> connect({
    required Uri url,
    required String name,
    required String password,
    String? registerCode,
    bool keepLocal = true,
  }) async {
    final client = ApiClient(url);
    await client.info();
    final auth = registerCode != null
        ? await client.register(name, password, registerCode)
        : await client.login(name, password);
    final account = '$url|${auth.userId}';
    if (await _store.meta('sync.account') != account) {
      if (keepLocal) {
        await SyncEngine(_store, client).prepareFirstSync();
      } else {
        await _store.clearAll();
        await _saveSettingsAfterClear();
      }
      await _store.setMeta('sync.account', account);
    }
    await _secrets.write(
      key: _kSession,
      value: jsonEncode({
        'url': url.toString(),
        'token': auth.token,
        'username': auth.username,
        'isAdmin': auth.isAdmin,
      }),
    );
    api = client;
    serverUrl = url.toString();
    username = auth.username;
    isAdmin = auth.isAdmin;
    needsLogin = false;
    await _refreshServerInfo();
    await syncNow();
    await reload();
  }

  Future<void> _saveSettingsAfterClear() async {
    await _store.setMeta('ai.mode', aiMode.name);
    await _store.setMeta('health.enabled', healthEnabled ? '1' : null);
    await _store.setMeta('health.write', healthWrite ? '1' : null);
  }

  /// Die Daten bleiben auf dem Gerät, nur im Browser sind sie danach weg.
  Future<void> disconnect() async {
    try {
      await api?.logout();
    } on ApiException {
      // Offline abmelden geht trotzdem.
    }
    await _forgetSession();
  }

  Future<void> _forgetSession() async {
    await _secrets.delete(key: _kSession);
    api = null;
    username = serverUrl = syncError = null;
    isAdmin = false;
    if (kIsWeb) await _store.clearAll();
    await reload();
  }

  Future<void> deleteAccount(String password) async {
    await api!.deleteAccount(password);
    await _store.setMeta('sync.account', null);
    await _forgetSession();
  }

  Future<void> syncNow() async {
    final client = api;
    if (client == null || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final applied = await SyncEngine(_store, client).run();
      lastSync = DateTime.now();
      syncError = null;
      needsLogin = false;
      if (applied > 0) await reload(notify: false);
    } on ApiException catch (e) {
      syncError = e.message;
      if (e.isAuth) {
        needsLogin = true;
        if (kIsWeb) await _forgetSession();
      }
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<String> createInvite() => api!.createInvite();

  // KI

  Future<void> setAi(AiMode mode, AiConfig? config) async {
    aiMode = mode;
    customAi = config;
    await _store.setMeta('ai.mode', mode.name);
    if (config == null) {
      await _secrets.delete(key: _kAi);
    } else {
      await _secrets.write(
        key: _kAi,
        value: jsonEncode({
          'baseUrl': config.baseUrl,
          'model': config.model,
          'apiKey': config.apiKey,
        }),
      );
    }
    notifyListeners();
  }

  /// Fasst die letzten [days] Tage für die KI zusammen. Nur Summen, keine
  /// einzelnen Einträge und keine Konto- oder Personendaten außer den Zielen.
  Future<String> reviewRecentDays(int days) async {
    final backend = ai;
    if (backend == null || profile == null) {
      throw const AiException('Keine KI eingerichtet.');
    }
    final list = await repo.summaries(dateKey(DateTime.now()), days, profile!);
    final logged = list.where((d) => d.entries.isNotEmpty).toList();
    if (logged.isEmpty) {
      throw const AiException(
        'In diesem Zeitraum ist noch nichts eingetragen.',
      );
    }
    return backend.reviewNutrition({
      'zielKcal': list.last.goals.kcal.round(),
      'zielEiweissG': list.last.goals.protein.round(),
      'zielWasserMl': list.last.goals.waterMl,
      'tage': [
        for (final d in logged)
          {
            'kcal': d.consumed.kcal.round(),
            'eiweissG': d.consumed.protein.round(),
            'kohlenhydrateG': d.consumed.carbs.round(),
            'fettG': d.consumed.fat.round(),
            'wasserMl': d.waterMl,
            'verbranntKcal': d.burnedKcal.round(),
          },
      ],
    });
  }

  // Health und FIT

  Future<void> setHealth({required bool enabled, required bool write}) async {
    if (enabled && !await health.requestAccess(write: write)) {
      throw const HealthUnavailable('Der Zugriff wurde nicht erlaubt.');
    }
    healthEnabled = enabled;
    healthWrite = enabled && write;
    await _store.setMeta('health.enabled', healthEnabled ? '1' : null);
    await _store.setMeta('health.write', healthWrite ? '1' : null);
    notifyListeners();
    if (enabled) await syncHealth(force: true);
  }

  /// Holt die letzten 14 Tage. Nur Änderungen werden gespeichert, sonst löste
  /// jeder App-Start einen unnötigen Abgleich aus.
  Future<void> syncHealth({bool force = false}) async {
    if (!healthEnabled || !health.supported) return;
    final now = DateTime.now();
    if (!force &&
        _lastHealthSync != null &&
        now.difference(_lastHealthSync!).inMinutes < 15) {
      return;
    }
    _lastHealthSync = now;
    try {
      var changed = false;
      for (final d in await health.readDays(14)) {
        final id = 'health-${d.date}';
        final existing = await _store.get(RecordKind.activity, id);
        if (existing != null &&
            !existing.deleted &&
            existing.data['steps'] == d.steps &&
            (existing.data['activeKcal'] as num?)?.round() ==
                d.activeKcal.round()) {
          continue;
        }
        await repo.saveActivity(
          ActivityEntry(
            id: id,
            date: d.date,
            kind: ActivityKind.daySummary,
            source: 'health',
            steps: d.steps,
            activeKcal: d.activeKcal,
          ),
        );
        changed = true;
      }
      for (final w in await health.readWeights(30)) {
        final existing = await _store.get(RecordKind.weight, w.date);
        // Von Hand Eingetragenes geht vor.
        if (existing != null &&
            (existing.data['source'] != 'health' ||
                existing.data['kg'] == w.kg)) {
          continue;
        }
        await repo.saveWeight(w);
        changed = true;
      }
      if (changed) {
        await reload();
        _changed();
      }
    } on Object catch (e) {
      debugPrint('Health: $e');
    }
  }

  Future<int> importFit(Uint8List bytes) async {
    final sessions = parseFitOrZip(bytes);
    for (final s in sessions) {
      await repo.saveActivity(s.toActivity());
    }
    await reload();
    _changed();
    return sessions.length;
  }

  /// Beim Zurückkehren in die App: abgleichen und ggf. zum neuen Tag wechseln.
  Future<void> onResume({required String previousToday}) async {
    final today = dateKey(DateTime.now());
    if (date == previousToday && today != previousToday) {
      await goToDate(today);
    }
    await syncNow();
    await syncHealth();
  }

  Future<Map<String, Object?>> exportData() =>
      api?.export() ?? repo.exportAll();

  /// Entfernt alle Daten von diesem Gerät.
  Future<void> wipeDevice() async {
    await disconnect();
    await _store.clearAll();
    await _secrets.delete(key: _kAi);
    aiMode = AiMode.off;
    customAi = null;
    healthEnabled = healthWrite = false;
    await reload();
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
