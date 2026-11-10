import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bociva_server/bociva_server.dart';
import 'package:bociva_server/src/api_error.dart';
import 'package:bociva_server/src/database.dart';
import 'package:bociva_server/src/limits.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';
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

  test('Ungültige Datensätze werden einzeln abgelehnt', () async {
    final c = await admin();
    final res = await c.exchange(0, [
      const SyncRecord(kind: 'evil', id: 'x', updatedAt: 1, data: {}),
      SyncRecord(
        kind: RecordKind.recipe,
        id: 'gross',
        updatedAt: 1,
        data: {'note': 'x' * (70 * 1024)},
      ),
      const SyncRecord(kind: RecordKind.water, id: 'w', updatedAt: 1, data: {}),
    ]);
    expect(res.rejected, 2);
    expect(res.changes.single.id, 'w');
    // Ein kaputter Umschlag ist weiterhin ein Fehler.
    final raw = await http.post(
      base.resolve('api/sync'),
      headers: {'authorization': 'Bearer ${c.token}'},
      body: jsonEncode({'since': 'x', 'changes': []}),
    );
    expect(raw.statusCode, 400);
  });

  test('Cursor jenseits des Servers beginnt von vorn', () async {
    final c = await admin();
    await c.exchange(0, const [
      SyncRecord(kind: RecordKind.water, id: 'a', updatedAt: 1, data: {}),
    ]);
    // Wie nach dem Einspielen einer älteren Sicherung.
    final res = await c.exchange(500, const [
      SyncRecord(kind: RecordKind.water, id: 'b', updatedAt: 1, data: {}),
    ]);
    expect([for (final r in res.changes) r.id], ['a', 'b']);
    expect(res.cursor, 2);
  });

  test('Speicherplatz pro Konto ist begrenzt, Löschen geht immer', () async {
    await server.close();
    server = await BocivaServer.start(
      const ServerConfig(
        dataDir: '',
        host: '127.0.0.1',
        port: 0,
        inMemory: true,
        userQuotaMb: 1,
      ),
      passwordIterations: 1000,
    );
    base = Uri.parse('http://127.0.0.1:${server.port}');
    final c = await admin();
    SyncRecord big(String id) => SyncRecord(
      kind: RecordKind.recipe,
      id: id,
      updatedAt: 1,
      data: {'note': 'x' * (60 * 1024)},
    );
    await c.exchange(0, [for (var i = 0; i < 15; i++) big('r$i')]);
    await expectLater(
      c.exchange(0, [for (var i = 15; i < 25; i++) big('r$i')]),
      throwsA(predicate((e) => e is ApiException && e.code == 'quota')),
    );
    final res = await c.exchange(0, const [
      SyncRecord(
        kind: RecordKind.recipe,
        id: 'r0',
        updatedAt: 2,
        data: {},
        deleted: true,
      ),
    ]);
    expect(res.changes, hasLength(15));
    await c.exchange(0, [big('neu')]);
  });

  test('Rezepte und Fasten werden abgeglichen und exportiert', () async {
    final c = await admin();
    final phone = MemoryStore();
    final repo = BocivaRepository(phone);
    await repo.saveRecipe(
      const Recipe(
        id: 'r',
        name: 'Suppe',
        servings: 2,
        ingredients: [
          RecipeIngredient(
            name: 'Linsen',
            amount: 200,
            nutrients: Nutrients(kcal: 232),
          ),
        ],
      ),
    );
    await repo.startFasting(16);
    await SyncEngine(phone, c).run();

    final web = MemoryStore();
    await SyncEngine(web, c).run();
    final other = BocivaRepository(web);
    expect((await other.recipes()).single.perServing.kcal, 116);
    expect((await other.activeFasting())!.targetHours, 16);
    expect((await other.searchLocal('supp')).single.name, 'Suppe');
    final export = await c.export();
    expect(export['recipe'], hasLength(1));
    expect(export['fasting'], hasLength(1));
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
    final db = server.database;
    expect(db.select('SELECT count(*) c FROM records').first['c'], 0);
    expect(db.select('SELECT count(*) c FROM sessions').first['c'], 0);
  });

  test('Ohne Administrator wird das älteste Konto einer', () async {
    final a = await admin();
    final code = await a.createInvite();
    final b = ApiClient(base);
    final auth = await b.register('bernd', password, code);
    expect(auth.isAdmin, isFalse);
    await a.deleteAccount(password);
    await b.login('bernd', password);
    expect(await b.createInvite(), hasLength(12));
    await b.deleteAccount(password);
    expect((await ApiClient(base).info()).setupRequired, isTrue);
    final stored = server.database.select(
      "SELECT 1 FROM settings WHERE key = 'setup_code_hash'",
    );
    expect(stored, hasLength(1));
  });

  test('Konto löschen ist gegen Passwortraten gesperrt', () async {
    final c = await admin();
    for (var i = 0; i < 5; i++) {
      await expectLater(
        c.deleteAccount('falsch-$i-xxxxxx'),
        throwsA(predicate((e) => e is ApiException && e.status == 403)),
      );
    }
    await expectLater(
      c.deleteAccount(password),
      throwsA(predicate((e) => e is ApiException && e.status == 429)),
    );
  });

  test('Überlange Namen beim Anmelden landen nicht in der Sperre', () async {
    await admin();
    for (var i = 0; i < 12; i++) {
      final res = await http.post(
        base.resolve('api/auth/login'),
        body: jsonEncode({'username': '$i${'n' * 10000}', 'password': 'x'}),
      );
      expect(res.statusCode, 401);
    }
    // Auch die Größe der Anfrage ist begrenzt.
    final huge = await http.post(
      base.resolve('api/auth/login'),
      body: jsonEncode({'username': 'n' * 100000, 'password': 'x'}),
    );
    expect(huge.statusCode, 413);
  });

  test('Stockende Anfrage wird beendet', () async {
    await server.close();
    server = await BocivaServer.start(
      const ServerConfig(
        dataDir: '',
        host: '127.0.0.1',
        port: 0,
        inMemory: true,
        bodyIdleTimeout: Duration(milliseconds: 200),
      ),
      passwordIterations: 1000,
    );
    final socket = await Socket.connect('127.0.0.1', server.port);
    socket.write(
      'POST /api/auth/login HTTP/1.1\r\nHost: x\r\n'
      'Content-Length: 100\r\n\r\n{"us',
    );
    // Der Server beendet die Verbindung, statt ewig zu warten; je nach
    // Zeitpunkt noch mit einer Antwort 408.
    final watch = Stopwatch()..start();
    final reply = await socket
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
        .timeout(const Duration(seconds: 5));
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    final text = utf8.decode(reply);
    expect(text.isEmpty || text.startsWith('HTTP/1.1 408'), isTrue);
    socket.destroy();
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
    expect(
      await c.reviewNutrition({
        'zielKcal': 2000,
        'tage': [
          {'kcal': 1800, 'eiweissG': 70},
        ],
      }),
      'Gut.',
    );
    // Freier Text geht nicht an das Modell.
    await expectLater(
      c.reviewNutrition({
        'zielKcal': 2000,
        'tage': [
          {'aufgabe': 'Schreibe ein Gedicht'},
        ],
      }),
      throwsA(predicate((e) => e is ApiException && e.status == 400)),
    );
  });

  test('Sperre und Warteschlange bleiben begrenzt', () async {
    final limiter = RateLimiter(3, const Duration(minutes: 1), maxKeys: 100);
    for (var i = 0; i < 1000; i++) {
      limiter.hit('k$i');
    }
    expect(limiter.size, lessThanOrEqualTo(100));
    final gate = Gate(1, maxQueue: 1);
    final release = Completer<void>();
    final first = gate.run(() => release.future);
    final second = gate.run(() async => 2);
    await expectLater(
      gate.run(() async => 3),
      throwsA(predicate((e) => e is ApiError && e.status == 503)),
    );
    release.complete();
    await first;
    expect(await second, 2);
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

  test('Datenbank aus Version 1 wird ergänzt', () async {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        is_admin INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        seq INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE sessions (token_hash TEXT PRIMARY KEY, user_id TEXT,
        expires_at INTEGER);
      CREATE TABLE invites (code_hash TEXT PRIMARY KEY, expires_at INTEGER);
      CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE records (user_id TEXT, kind TEXT, id TEXT, seq INTEGER,
        updated_at INTEGER, deleted INTEGER, data TEXT,
        PRIMARY KEY (user_id, kind, id));
      CREATE TABLE food_cache (barcode TEXT PRIMARY KEY, json TEXT,
        fetched_at INTEGER NOT NULL);
      INSERT INTO users VALUES ('u', 'anna', 'x', 1, 0, 2);
      INSERT INTO records VALUES ('u', 'water', 'a', 1, 1, 0, '{"ml":250}');
      INSERT INTO records VALUES ('u', 'water', 'b', 2, 1, 1, '{}');
      PRAGMA user_version = 1;
    ''');
    migrate(db);
    final row = db.select('SELECT record_count, data_bytes FROM users').first;
    expect(row['record_count'], 2);
    expect(row['data_bytes'], 12);
    expect(db.select('PRAGMA user_version').first.values.first, 2);
    migrate(db);
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
