import 'dart:io';

import 'package:bociva/src/controller.dart';
import 'package:bociva/src/platform/health_bridge.dart';
import 'package:bociva/src/platform/reminders.dart';
import 'package:bociva/src/platform/store_common.dart';
import 'package:bociva/src/platform/store_native.dart';
import 'package:bociva/src/screens/connect_screen.dart';
import 'package:bociva/src/screens/profile_form.dart';
import 'package:bociva/src/screens/shell.dart';
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
      expect(await store.datesWith(RecordKind.water), {'2026-11-09'});
      expect(await store.datesWith(RecordKind.diary), isEmpty);
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

    Future<void> startWithDays(WidgetTester tester, List<int> daysAgo) async {
      await tester.runAsync(() async {
        await app.start();
        await app.saveProfile(
          const Profile(
            sex: Sex.male,
            birthYear: 1985,
            heightCm: 180,
            weightKg: 80,
          ),
        );
        final now = DateTime.now();
        for (final d in daysAgo) {
          await app.repo.logFood(
            basicFoods.first,
            date: dateKey(DateTime(now.year, now.month, now.day - d)),
            meal: Meal.lunch,
            amount: 100,
          );
        }
        await app.reload();
      });
      await tester.pumpWidget(
        ControllerScope(
          controller: app,
          child: MaterialApp(
            theme: bocivaTheme(Brightness.light),
            home: const Shell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Serie hält bis Mitternacht und wächst mit dem Eintrag', (
      tester,
    ) async {
      await startWithDays(tester, [1]);
      expect(find.text('1 Tag in Folge'), findsOneWidget);
      expect(find.textContaining('damit deine Serie hält'), findsOneWidget);
      await tester.runAsync(
        () => app.logFood(basicFoods.first, Meal.dinner, 50),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('streak-snack')), findsOneWidget);
      expect(find.text('2 Tage in Folge'), findsOneWidget);
      // Ein zweiter Eintrag am selben Tag verlängert nichts.
      await tester.runAsync(
        () => app.logFood(basicFoods.first, Meal.snack, 20),
      );
      expect(app.hasCelebration, isFalse);
    });

    testWidgets('Mahlzeit vom Vortag mit einem Tipp übernehmen', (
      tester,
    ) async {
      await startWithDays(tester, [1]);
      final chip = find.byKey(const Key('repeat-lunch'));
      await tester.scrollUntilVisible(chip, 200);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      expect(find.textContaining('Wie am Vortag'), findsOneWidget);
      await tester.tap(chip);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(app.day!.entries.single.meal, Meal.lunch);
      expect(find.byKey(const Key('repeat-lunch')), findsNothing);
      // Der Vortag zählt mit: die Serie wächst auf zwei Tage.
      expect(app.streak!.current, 2);
    });

    testWidgets('Meilenstein wird groß gewürdigt', (tester) async {
      await startWithDays(tester, [2, 1]);
      await tester.runAsync(
        () => app.logFood(basicFoods.first, Meal.breakfast, 80),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('streak-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('streak-dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('streak-dialog')), findsNothing);
      expect(app.streak!.current, 3);
    });
  });

  test('Erinnerungstext nennt die Serie nur, wenn sie sicher ist', () {
    final open = Streak.fromDates({'2026-03-02', '2026-03-03'}, '2026-03-04');
    expect(reminderText(open, 0), contains('2 Tagen'));
    expect(reminderText(open, 1), isNot(contains('Tagen')));
    final done = Streak.fromDates({'2026-03-03', '2026-03-04'}, '2026-03-04');
    expect(reminderText(done, 1), contains('2 Tagen'));
    expect(reminderText(done, 3), contains('Jeder Tag zählt'));
    final none = Streak.fromDates({}, '2026-03-04');
    expect(reminderText(none, 0), contains('Jeder Tag zählt'));
  });

  test('Health-Zeit trennt Einträge derselben Sekunde', () {
    final at = DateTime(2026, 3, 29, 12, 30, 15, 120).millisecondsSinceEpoch;
    final a = healthTime('2026-03-29', at);
    final b = healthTime('2026-03-29', at + 1);
    expect(a.millisecond, 120);
    // Das Löschfenster von a reicht nicht bis b.
    expect(healthDeleteEnd(a).isAfter(b), isFalse);
    // Ein nachgetragener Tag behält die Uhrzeit der Eingabe.
    expect(
      healthTime('2026-03-27', at),
      DateTime(2026, 3, 27, 12, 30, 15, 120),
    );
  });

  testWidgets('Diagramme zeichnen auch ohne Daten', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bocivaTheme(Brightness.light),
        home: const Scaffold(
          body: Column(
            children: [
              BarChart(values: [], labels: [], color: BocivaColors.forest),
              LineChart(values: [70], color: BocivaColors.coral),
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
