import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bociva/src/controller.dart';
import 'package:bociva/src/platform/store.dart';
import 'package:bociva_server/bociva_server.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Ohne Test-Binding: Das würde echte HTTP-Anfragen an den Server abfangen.

const _password = 'ein-langes-passwort';

const _profile = Profile(
  sex: Sex.female,
  birthYear: 1990,
  heightCm: 170,
  weightKg: 70,
);

/// Ruft bei der ersten Abfrage geänderter Datensätze [onDirty] auf, also
/// mitten in einem laufenden Abgleich.
class _HookStore extends MemoryStore {
  Future<void> Function()? onDirty;

  @override
  Future<List<SyncRecord>> dirty({int limit = 500}) async {
    final batch = await super.dirty(limit: limit);
    final hook = onDirty;
    onDirty = null;
    if (hook != null) await hook();
    return batch;
  }
}

Future<void> _until(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Zeitüberschreitung: ${reason ?? 'Bedingung'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late BocivaServer server;
  late Uri base;
  final controllers = <AppController>[];

  AppController make({LocalStore? store, bool web = false}) {
    final s = store ?? MemoryStore();
    final c = AppController(
      web: web,
      openStore: ({required readKey, required createKey}) async => s,
      deleteStore: () async {},
    );
    controllers.add(c);
    return c;
  }

  Future<AppController> started({LocalStore? store, bool web = false}) async {
    final c = make(store: store, web: web);
    await c.start();
    return c;
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    server = await BocivaServer.start(
      const ServerConfig(
        dataDir: '',
        host: '127.0.0.1',
        port: 0,
        inMemory: true,
      ),
      passwordIterations: 1000,
    );
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
    await server.close();
  });

  Future<String> invite() async {
    final admin = ApiClient(base);
    await admin.login('anna', _password);
    return admin.createInvite();
  }

  test('Start wartet nicht auf einen unerreichbaren Server', () async {
    final socket = await ServerSocket.bind('127.0.0.1', 0);
    final deadPort = socket.port;
    await socket.close();
    FlutterSecureStorage.setMockInitialValues({
      'session': jsonEncode({
        'url': 'http://127.0.0.1:$deadPort',
        'token': 't',
        'username': 'anna',
      }),
    });
    final c = make();
    final watch = Stopwatch()..start();
    await c.start();
    expect(c.ready, isTrue);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    // Ohne Profil und ohne je abgeglichen zu haben: kein Onboarding.
    expect(c.awaitingFirstSync, isTrue);
    await _until(() => !c.syncing && c.syncError != null);
    expect(c.startError, isNull);
    expect(c.awaitingFirstSync, isTrue);
  });

  test('HTML statt JSON ist ein Abgleichsfehler, kein Startfehler', () async {
    final html = await HttpServer.bind('127.0.0.1', 0);
    html.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write('<html>Bitte anmelden</html>')
        ..close();
    });
    addTearDown(() => html.close(force: true));
    FlutterSecureStorage.setMockInitialValues({
      'session': jsonEncode({
        'url': 'http://127.0.0.1:${html.port}',
        'token': 't',
        'username': 'anna',
      }),
    });
    final c = await started();
    await _until(() => !c.syncing && c.syncError != null);
    expect(c.startError, isNull);
    expect(c.ready, isTrue);
  });

  test('Daten eines früheren Kontos gehen nicht ungefragt mit', () async {
    final a = await started();
    await a.connect(
      url: base,
      name: 'anna',
      password: _password,
      registerCode: server.setupCode,
    );
    await a.saveProfile(_profile);
    await a.addWater(400);
    await a.syncNow();
    final code = await invite();
    await a.disconnect();
    expect(a.previousAccount, 'anna (127.0.0.1)');

    // Wie der Anmeldebildschirm es vorbelegt: nicht übernehmen.
    await a.connect(
      url: base,
      name: 'bernd',
      password: _password,
      registerCode: code,
      keepLocal: a.previousAccount == null,
    );
    expect(a.day, isNull);
    expect(await a.pendingChanges(), 0);
    final bernd = ApiClient(base);
    await bernd.login('bernd', _password);
    expect((await bernd.exchange(0, const [])).changes, isEmpty);
  });

  test('Erste Verbindung ersetzt das Profil des Kontos nicht', () async {
    final a = await started();
    await a.connect(
      url: base,
      name: 'anna',
      password: _password,
      registerCode: server.setupCode,
    );
    await a.saveProfile(
      const Profile(
        sex: Sex.female,
        birthYear: 1990,
        heightCm: 170,
        weightKg: 70,
        kcalOverride: 1900,
      ),
    );
    await a.syncNow();

    // Ein neues Gerät, erst ohne Server eingerichtet, dann verbunden.
    final b = await started();
    await b.saveProfile(
      const Profile(
        sex: Sex.male,
        birthYear: 1970,
        heightCm: 190,
        weightKg: 95,
      ),
    );
    await b.connect(url: base, name: 'anna', password: _password);
    expect(b.profile!.kcalOverride, 1900);
    expect(b.profile!.heightCm, 170);

    // Ein Konto ohne Profil bekommt das des Geräts.
    final code = await invite();
    final c = await started();
    await c.saveProfile(_profile);
    await c.connect(
      url: base,
      name: 'bernd',
      password: _password,
      registerCode: code,
    );
    final bernd = ApiClient(base);
    await bernd.login('bernd', _password);
    final records = (await bernd.exchange(0, const [])).changes;
    expect(records.where((r) => r.kind == RecordKind.profile), hasLength(1));
  });

  test('Änderung während eines Abgleichs wird nachgeholt', () async {
    final store = _HookStore();
    final c = await started(store: store);
    await c.connect(
      url: base,
      name: 'anna',
      password: _password,
      registerCode: server.setupCode,
    );
    store.onDirty = () async {
      await c.repo.addWater('2026-11-10', 250);
      unawaited(c.syncNow());
    };
    await c.syncNow();
    expect(await c.pendingChanges(), 0);
    expect(c.hasUnsyncedChanges, isFalse);
  });

  test('Web: abgelaufene Sitzung löscht Ungesendetes nicht', () async {
    final c = await started(web: true);
    await c.connect(
      url: base,
      name: 'anna',
      password: _password,
      registerCode: server.setupCode,
    );
    await c.saveProfile(_profile);
    await c.syncNow();
    // Die Sitzung endet auf dem Server, z. B. durch Abmelden anderswo.
    await ApiClient(base, token: c.api!.token).logout();
    await c.repo.addWater('2026-11-10', 300);
    await c.syncNow();
    expect(c.mustConnect, isTrue);
    expect(await c.pendingChanges(), 1);
    expect(c.hasUnsyncedChanges, isTrue);

    await c.connect(url: base, name: 'anna', password: _password);
    expect(await c.pendingChanges(), 0);
    expect((await c.repo.water('2026-11-10')).single.ml, 300);
  });

  test('Web: Abmelden fragt bei Ungesendetem nach', () async {
    final c = await started(web: true);
    await c.connect(
      url: base,
      name: 'anna',
      password: _password,
      registerCode: server.setupCode,
    );
    await server.close();
    await c.repo.addWater('2026-11-10', 300);
    c.hasUnsyncedChanges = true;
    expect(await c.disconnect(), isFalse);
    expect(c.isConnected, isTrue);
    expect(await c.disconnect(force: true), isTrue);
    expect(await c.pendingChanges(), 0);
    // tearDown schließt den Server noch einmal.
    server = await BocivaServer.start(
      const ServerConfig(
        dataDir: '',
        host: '127.0.0.1',
        port: 0,
        inMemory: true,
      ),
      passwordIterations: 1000,
    );
  });

  test('Ohne Schlüssel bietet die App Zurücksetzen an', () async {
    var locked = true;
    var deleted = false;
    final c = AppController(
      openStore: ({required readKey, required createKey}) async {
        if (locked) throw const LocalStoreLocked();
        return MemoryStore();
      },
      deleteStore: () async => deleted = true,
    );
    controllers.add(c);
    await c.start();
    expect(c.ready, isFalse);
    expect(c.canResetStore, isTrue);
    expect(c.startError, isNotNull);
    locked = false;
    await c.resetLocalStore();
    expect(deleted, isTrue);
    expect(c.ready, isTrue);
    expect(c.startError, isNull);
  });
}
