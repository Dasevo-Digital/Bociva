import 'package:bociva/src/platform/store_native.dart';
import 'package:bociva/src/theme.dart';
import 'package:bociva/src/widgets/charts.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
