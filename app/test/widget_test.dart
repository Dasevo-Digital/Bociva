import 'dart:io';

import 'package:bociva/src/controller.dart';
import 'package:bociva/src/platform/store_common.dart';
import 'package:bociva/src/platform/store_native.dart';
import 'package:bociva/src/screens/connect_screen.dart';
import 'package:bociva/src/screens/profile_form.dart';
import 'package:bociva/src/theme.dart';
import 'package:bociva/src/widgets/charts.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('SqliteStore', () {
    late SqliteStore store;

    setUp(() => store = SqliteStore(sqlite3.openInMemory()));

    const record = SyncRecord(
      kind: RecordKind.water,
      id: 'a',
      updatedAt: 10,
      data: {'id': 'a', 'date': '2026-11-09', 'ml': 250},
    );

    test('sucht nach Datum und lässt Gelöschtes aus', () async {
      await store.put(record, dirty: true);
      await store.put(
        const SyncRecord(
          kind: RecordKind.water,
          id: 'b',
          updatedAt: 10,
          data: {},
          deleted: true,
        ),
        dirty: true,
      );
      final found = await store.byDate(
        RecordKind.water,
        '2026-11-01',
        '2026-11-30',
      );
      expect(found.single.id, 'a');
      expect(await store.countLive(), 1);
      expect(await store.dirty(), hasLength(2));
    });

    test('hält neuere Änderungen beim Quittieren markiert', () async {
      await store.put(record, dirty: true);
      final sent = await store.dirty();
      await store.put(
        const SyncRecord(
          kind: RecordKind.water,
          id: 'a',
          updatedAt: 20,
          data: {'id': 'a', 'date': '2026-11-09', 'ml': 500},
        ),
        dirty: true,
      );
      await store.clearDirty(sent);
      expect(await store.isDirty(RecordKind.water, 'a'), isTrue);
    });

    test('funktioniert als Grundlage des Tagebuchs', () async {
      final repo = BocivaRepository(store);
      await repo.addWater('2026-11-09', 300);
      expect((await repo.water('2026-11-09')).single.ml, 300);
      await store.setMeta('k', 'v');
      expect(await store.meta('k'), 'v');
      await store.clearAll();
      expect(await store.countLive(), 0);
      expect(await store.meta('k'), isNull);
    });
  });

  test('Datenbank ohne passenden Schlüssel wird nicht überschrieben', () async {
    final dir = await Directory.systemTemp.createTemp('bociva');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/bociva.db';
    const key = '00112233445566778899aabbccddeeff';
    var created = 0;
    Future<String> create() async {
      created++;
      return key;
    }

    final first = await openLocalStoreAt(
      path,
      readKey: () async => null,
      createKey: create,
    );
    await BocivaRepository(first).addWater('2026-11-10', 250);
    (first as SqliteStore).db.close();
    expect(created, 1);

    await expectLater(
      openLocalStoreAt(path, readKey: () async => null, createKey: create),
      throwsA(isA<LocalStoreLocked>()),
    );
    await expectLater(
      openLocalStoreAt(
        path,
        readKey: () async => 'ffeeddccbbaa99887766554433221100',
        createKey: create,
      ),
      throwsA(isA<LocalStoreLocked>()),
    );
    expect(created, 1);
    final again = await openLocalStoreAt(
      path,
      readKey: () async => key,
      createKey: create,
    );
    expect((await BocivaRepository(again).water('2026-11-10')).single.ml, 250);
    (again as SqliteStore).db.close();
  });

  group('Oberfläche mit Controller', () {
    late MemoryStore store;
    late AppController app;

    setUp(() async {
      await initializeDateFormatting('de');
      FlutterSecureStorage.setMockInitialValues({});
      store = MemoryStore();
      app = AppController(
        openStore: ({required readKey, required createKey}) async => store,
        deleteStore: () async {},
      );
    });

    tearDown(() => app.dispose());

    Widget wrap(Widget child) => ControllerScope(
      controller: app,
      child: MaterialApp(
        theme: bocivaTheme(Brightness.light),
        home: Scaffold(body: child),
      ),
    );

    testWidgets('Profil speichern behält Fasten, Zielgewicht und 2000 kcal', (
      tester,
    ) async {
      await tester.runAsync(app.start);
      const initial = Profile(
        sex: Sex.female,
        birthYear: 1990,
        heightCm: 170,
        weightKg: 70,
        targetWeightKg: 65,
        kcalOverride: 2000,
        fastingEnabled: true,
      );
      await tester.runAsync(() => app.saveProfile(initial));
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: ProfileForm(initial: app.profile, submitLabel: 'Speichern'),
          ),
        ),
      );
      final save = find.byKey(const Key('profile-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final p = app.profile!;
      expect(p.fastingEnabled, isTrue);
      expect(p.targetWeightKg, 65);
      expect(p.kcalOverride, 2000);
      // Unverändertes Gewicht wird kein neuer Eintrag.
      expect(await tester.runAsync(() => app.repo.latestWeight()), isNull);
    });

    testWidgets('Daten eines früheren Kontos sind nicht vorausgewählt', (
      tester,
    ) async {
      await store.setMeta('sync.account', 'https://a.example|1');
      await store.setMeta('sync.accountName', 'anna (a.example)');
      await tester.runAsync(app.start);
      await tester.runAsync(() => app.addWater(250));
      await tester.pumpWidget(wrap(const ConnectScreen(webMode: false)));
      await tester.pumpAndSettle();
      final box = tester.widget<CheckboxListTile>(
        find.byKey(const Key('connect-keep-local')),
      );
      expect(box.value, isFalse);
      expect(find.textContaining('anna (a.example)'), findsOneWidget);
    });
  });

  testWidgets('Diagramme zeichnen auch ohne Daten', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bocivaTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              BarChart(values: [], labels: [], color: BocivaColors.pine),
              LineChart(values: [70], color: BocivaColors.apricot),
              CalorieRing(fraction: 2, over: true, child: Text('x')),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('x'), findsOneWidget);
  });
}
