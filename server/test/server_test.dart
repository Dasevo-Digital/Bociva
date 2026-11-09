import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bociva_server/bociva_server.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _Food implements FoodLookup {
  int calls = 0;
  @override
  Future<Food?> byBarcode(String barcode) async {
    calls++;
    return barcode == '40111445'
        ? const Food(
            id: 'off-40111445',
            name: 'Riegel',
            per100: Nutrients(kcal: 500),
          )
        : null;
  }

  @override
  Future<List<Food>> search(String query) async => const [];
}

class _Ai implements AiBackend {
  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    Uint8List? image,
    String? imageMime,
  }) async => MealAnalysis(
    items: [
      AiFoodItem(
        name: text ?? 'Bild',
        amount: 100,
        nutrients: const Nutrients(kcal: 10),
      ),
    ],
  );

  @override
  Future<String> reviewNutrition(Map<String, Object?> stats) async => 'Gut.';
}

void main() {
  late BocivaServer server;
  late Uri base;
  late _Food foods;
  const password = 'ein-langes-passwort';

  setUp(() async {
    foods = _Food();
    server = await BocivaServer.start(
      const ServerConfig(
        dataDir: '',
        host: '127.0.0.1',
        port: 0,
        inMemory: true,
      ),
      passwordIterations: 1000,
      foodLookup: foods,
      ai: _Ai(),
    );
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() => server.close());

  Future<ApiClient> admin() async {
    final c = ApiClient(base);
    await c.register('anna', password, server.setupCode!);
    return c;
  }

  test('Erstes Konto braucht den Einrichtungscode', () async {
    final c = ApiClient(base);
    expect((await c.info()).setupRequired, isTrue);
    await expectLater(
      c.register('mallory', password, 'FALSCH'),
      throwsA(predicate((e) => e is ApiException && e.status == 403)),
    );
    final auth = await c.register('anna', password, server.setupCode!);
    expect(auth.isAdmin, isTrue);
    expect((await c.info()).setupRequired, isFalse);
  });

  test('Einladung gilt nur einmal, ohne sie gibt es kein Konto', () async {
    final a = await admin();
    final code = await a.createInvite();
    final b = ApiClient(base);
    final auth = await b.register('bernd', password, code);
    expect(auth.isAdmin, isFalse);
    await expectLater(
      ApiClient(base).register('carla', password, code),
      throwsA(predicate((e) => e is ApiException && e.status == 403)),
    );
    await expectLater(
      b.createInvite(),
      throwsA(predicate((e) => e is ApiException && e.status == 403)),
    );
  });

  test('Daten anderer Konten bleiben unsichtbar', () async {
    final a = await admin();
    final b = ApiClient(base);
    await b.register('bernd', password, await a.createInvite());
    const record = SyncRecord(
      kind: RecordKind.water,
      id: 'w1',
      updatedAt: 1000,
      data: {'id': 'w1', 'date': '2026-11-09', 'ml': 250},
    );
    await a.exchange(0, [record]);
    expect((await b.exchange(0, const [])).changes, isEmpty);
    expect((await a.exchange(0, const [])).changes.single.data['ml'], 250);
  });

  test('Zwei Geräte gleichen sich über den Server ab', () async {
    final client = await admin();
    final phone = MemoryStore();
    final web = MemoryStore();
    await BocivaRepository(phone).addWater('2026-11-09', 300);
    await SyncEngine(phone, client).run();
    await SyncEngine(web, client).run();
    final repoWeb = BocivaRepository(web);
    expect((await repoWeb.water('2026-11-09')).single.ml, 300);

    await repoWeb.undoLastWater('2026-11-09');
    await SyncEngine(web, client).run();
    await SyncEngine(phone, client).run();
    expect(await BocivaRepository(phone).water('2026-11-09'), isEmpty);
  });

  test('Ältere Änderung überschreibt keine neuere', () async {
    final c = await admin();
    SyncRecord r(int at, int ml) => SyncRecord(
      kind: RecordKind.water,
      id: 'w',
      updatedAt: at,
      data: {'ml': ml},
    );
    await c.exchange(0, [r(2000, 2)]);
    await c.exchange(0, [r(1000, 1)]);
    expect((await c.exchange(0, const [])).changes.single.data['ml'], 2);
  });

  test('Uhrzeit aus der Zukunft wird begrenzt', () async {
    final c = await admin();
    final future = DateTime.now().millisecondsSinceEpoch + 86400000 * 365;
    final res = await c.exchange(0, [
      SyncRecord(
        kind: RecordKind.water,
        id: 'w',
        updatedAt: future,
        data: const {'ml': 1},
      ),
    ]);
    expect(res.changes.single.updatedAt, lessThan(future));
  });

  test('Unbekannte Datensatzart wird abgelehnt', () async {
    final c = await admin();
    await expectLater(
      c.exchange(0, const [
        SyncRecord(kind: 'evil', id: 'x', updatedAt: 1, data: {}),
      ]),
      throwsA(predicate((e) => e is ApiException && e.status == 400)),
    );
  });

  test('Ohne Anmeldung gibt es nichts', () async {
    for (final path in ['api/me', 'api/export', 'api/foods/barcode/40111445']) {
      final res = await http.get(base.resolve(path));
      expect(res.statusCode, 401, reason: path);
    }
  });

  test('Abgemeldete Sitzung ist ungültig', () async {
    final c = await admin();
    final token = c.token;
    await c.logout();
    final res = await http.get(
      base.resolve('api/me'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(res.statusCode, 401);
  });

  test('Anmeldung sperrt nach zu vielen Fehlversuchen', () async {
    await admin();
    final c = ApiClient(base);
    for (var i = 0; i < 10; i++) {
      await expectLater(
        c.login('anna', 'falsches-passwort'),
        throwsA(predicate((e) => e is ApiException && e.status == 401)),
      );
    }
    await expectLater(
      c.login('anna', password),
      throwsA(predicate((e) => e is ApiException && e.status == 429)),
    );
  });

  test('Konto löschen entfernt alle Daten', () async {
    final c = await admin();
    await c.exchange(0, const [
      SyncRecord(kind: RecordKind.water, id: 'w', updatedAt: 1, data: {}),
    ]);
    await expectLater(
      c.deleteAccount('falsches-passwort'),
      throwsA(predicate((e) => e is ApiException && e.status == 403)),
    );
    await c.deleteAccount(password);
    await expectLater(
      c.exchange(0, const []),
      throwsA(predicate((e) => e is ApiException && e.isAuth)),
    );
  });

  test('Strichcode wird zwischengespeichert, auch wenn er fehlt', () async {
    final c = await admin();
    expect((await c.byBarcode('40111445'))!.name, 'Riegel');
    await c.byBarcode('40111445');
    expect(foods.calls, 1);
    expect(await c.byBarcode('12345678'), isNull);
    expect(await c.byBarcode('12345678'), isNull);
    expect(foods.calls, 2);
  });

  test('KI läuft über den Server', () async {
    final c = await admin();
    final result = await c.analyzeMeal(text: 'Suppe');
    expect(result.items.single.name, 'Suppe');
    expect(await c.reviewNutrition({'days': 7}), 'Gut.');
  });

  test('Übergroße Anfragen werden abgelehnt', () async {
    final c = await admin();
    final res = await http.post(
      base.resolve('api/sync'),
      headers: {'authorization': 'Bearer ${c.token}'},
      body: 'x' * (9 * 1024 * 1024),
    );
    expect(res.statusCode, 413);
  });

  test('Verschlüsselte Datenbank übersteht einen Neustart', () async {
    final dir = await Directory.systemTemp.createTemp('bociva-test');
    addTearDown(() => dir.delete(recursive: true));
    final config = ServerConfig(
      dataDir: dir.path,
      keyFile: '${dir.path}/k.key',
      host: '127.0.0.1',
      port: 0,
    );
    var s = await BocivaServer.start(config, passwordIterations: 1000);
    final c = ApiClient(Uri.parse('http://127.0.0.1:${s.port}'));
    await c.register('anna', password, s.setupCode!);
    await s.close();
    final header = File('${dir.path}/bociva.db').openSync().readSync(16);
    expect(String.fromCharCodes(header), isNot(startsWith('SQLite format')));
    s = await BocivaServer.start(config, passwordIterations: 1000);
    expect(s.setupCode, isNull);
    final again = ApiClient(Uri.parse('http://127.0.0.1:${s.port}'));
    expect((await again.login('anna', password)).username, 'anna');
    await s.close();
  });

  test('Export enthält keine gelöschten Datensätze', () async {
    final c = await admin();
    await c.exchange(0, const [
      SyncRecord(
        kind: RecordKind.water,
        id: 'a',
        updatedAt: 1,
        data: {'ml': 1},
      ),
      SyncRecord(
        kind: RecordKind.water,
        id: 'b',
        updatedAt: 1,
        data: {},
        deleted: true,
      ),
    ]);
    final export = await c.export();
    expect(jsonEncode(export['water']), '[{"ml":1}]');
  });
}
