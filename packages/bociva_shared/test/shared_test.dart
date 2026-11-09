import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// Baut eine kleine FIT-Datei mit einer Session-Nachricht.
Uint8List fitFile({int calories = 512, int startFit = 1000000000}) {
  final b = BytesBuilder();
  final body = BytesBuilder();
  // Definition: lokaler Typ 0, Little Endian, global 18, vier Felder.
  body.add([0x40, 0, 0, 18, 0, 5]);
  body.add([2, 4, 134, 5, 1, 0, 8, 4, 134, 9, 4, 134, 11, 2, 132]);
  final d = ByteData(15);
  d.setUint32(0, startFit, Endian.little);
  d.setUint8(4, 1);
  d.setUint32(5, 1800000, Endian.little);
  d.setUint32(9, 500000, Endian.little);
  d.setUint16(13, calories, Endian.little);
  body.addByte(0x00);
  body.add(d.buffer.asUint8List());
  final bytes = body.toBytes();
  final header = ByteData(12)
    ..setUint8(0, 12)
    ..setUint8(1, 0x10)
    ..setUint16(2, 2100, Endian.little)
    ..setUint32(4, bytes.length, Endian.little);
  final h = header.buffer.asUint8List();
  h.setRange(8, 12, '.FIT'.codeUnits);
  b.add(h);
  b.add(bytes);
  b.add([0, 0]);
  return b.toBytes();
}

void main() {
  group('Ziele', () {
    const base = Profile(
      sex: Sex.female,
      birthYear: 1990,
      heightCm: 170,
      weightKg: 70,
      activity: ActivityLevel.light,
    );

    test('Grundumsatz nach Mifflin-St Jeor', () {
      expect(basalMetabolicRate(base, year: 2026), 700 + 1062.5 - 180 - 161);
    });

    test('Kalorienziel wird nicht unter die Untergrenze gerechnet', () {
      final goals = calculateGoals(
        const Profile(
          sex: Sex.female,
          birthYear: 1990,
          heightCm: 150,
          weightKg: 45,
          activity: ActivityLevel.sedentary,
          goal: GoalType.lose,
          weeklyRateKg: 5,
        ),
        year: 2026,
      );
      expect(goals.kcal, 1200);
      expect(goals.limitedToMinimum, isTrue);
    });

    test('Makros ergeben zusammen das Kalorienziel', () {
      final g = calculateGoals(base, year: 2026);
      expect(g.protein * 4 + g.carbs * 4 + g.fat * 9, closeTo(g.kcal, 3));
    });

    test('Training zählt nicht doppelt zur Tagessumme', () {
      final day = DaySummary(
        date: '2026-11-09',
        entries: const [],
        water: const [],
        goals: calculateGoals(base, year: 2026),
        addActivityToBudget: true,
        activities: const [
          ActivityEntry(
            id: 'd',
            date: '2026-11-09',
            kind: ActivityKind.daySummary,
            source: 'health',
            activeKcal: 600,
          ),
          ActivityEntry(
            id: 'w',
            date: '2026-11-09',
            kind: ActivityKind.workout,
            source: 'fit',
            activeKcal: 400,
          ),
        ],
      );
      expect(day.burnedKcal, 600);
      expect(day.budgetKcal, day.goals.kcal + 600);
    });
  });

  group('Tagebuch', () {
    test('Eintrag bleibt beim Ändern des Lebensmittels unverändert', () async {
      final repo = BocivaRepository(MemoryStore());
      const food = Food(
        id: 'x',
        name: 'Test',
        per100: Nutrients(kcal: 200, protein: 10),
      );
      await repo.logFood(
        food,
        date: '2026-11-09',
        meal: Meal.lunch,
        amount: 150,
      );
      await repo.saveFood(
        const Food(id: 'x', name: 'Neu', per100: Nutrients(kcal: 999)),
      );
      final list = await repo.diary('2026-11-09');
      expect(list.single.nutrients.kcal, 300);
      expect(list.single.nutrients.protein, 15);
      expect(list.single.name, 'Test');
    });

    test('lokale Suche findet Grundnahrungsmittel', () async {
      final repo = BocivaRepository(MemoryStore());
      expect((await repo.searchLocal('banan')).first.name, 'Banane');
    });

    test('Rückgängig entfernt nur die letzte Wasserportion', () async {
      var ms = 1000;
      final repo = BocivaRepository(
        MemoryStore(),
        clock: () => DateTime.fromMillisecondsSinceEpoch(ms += 10),
      );
      await repo.addWater('2026-11-09', 250);
      await repo.addWater('2026-11-09', 500);
      await repo.undoLastWater('2026-11-09');
      expect((await repo.water('2026-11-09')).single.ml, 250);
    });
  });

  group('Sync', () {
    late List<SyncRecord> serverRecords;
    late int seq;

    SyncTransport fakeServer() => _Fake((since, changes) {
      for (final c in changes) {
        serverRecords.removeWhere((r) => r.kind == c.kind && r.id == c.id);
        serverRecords.add(c);
        seq++;
      }
      return SyncResponse(
        cursor: seq,
        changes: since == 0 ? List.of(serverRecords) : const [],
        hasMore: false,
      );
    });

    setUp(() {
      serverRecords = [];
      seq = 0;
    });

    test('Daten kommen von Gerät A auf Gerät B', () async {
      final a = MemoryStore();
      final b = MemoryStore();
      await BocivaRepository(a).addWater('2026-11-09', 300);
      await SyncEngine(a, fakeServer()).run();
      await SyncEngine(b, fakeServer()).run();
      expect((await BocivaRepository(b).water('2026-11-09')).single.ml, 300);
      expect(await a.dirty(), isEmpty);
    });

    test('jüngere lokale Änderung bleibt bei Konflikt erhalten', () async {
      final store = MemoryStore();
      await store.put(
        const SyncRecord(
          kind: 'water',
          id: 'a',
          updatedAt: 200,
          data: {'date': '2026-11-09', 'id': 'a', 'ml': 2},
        ),
        dirty: true,
      );
      // Die Eingabe kommt, während die Anfrage unterwegs ist.
      final engine = SyncEngine(
        store,
        _FakeAsync((since, changes) async {
          await store.put(
            const SyncRecord(
              kind: 'water',
              id: 'a',
              updatedAt: 300,
              data: {'date': '2026-11-09', 'id': 'a', 'ml': 3},
            ),
            dirty: true,
          );
          return const SyncResponse(
            cursor: 1,
            hasMore: false,
            changes: [
              SyncRecord(
                kind: 'water',
                id: 'a',
                updatedAt: 100,
                data: {'date': '2026-11-09', 'id': 'a', 'ml': 1},
              ),
            ],
          );
        }),
      );
      await engine.run();
      expect((await store.get('water', 'a'))!.data['ml'], 3);
      expect(await store.isDirty('water', 'a'), isTrue);
    });
  });

  group('Open Food Facts', () {
    test('rechnet kJ um und erkennt Flüssigkeiten', () {
      final f = foodFromOpenFoodFacts({
        'code': '4000000000000',
        'product_name_de': 'Saft',
        'brands': 'Marke, Andere',
        'quantity': '1 l',
        'nutriments': {'energy_100g': 200, 'carbohydrates_100g': '10,5'},
      })!;
      expect(f.per100.kcal, closeTo(47.8, 0.1));
      expect(f.per100.carbs, 10.5);
      expect(f.unit, 'ml');
      expect(f.brand, 'Marke');
    });

    test('verwirft Produkte ohne Energiewert', () {
      expect(foodFromOpenFoodFacts({'code': '1', 'product_name': 'X'}), isNull);
    });

    test('Strichcode wird angefragt und ausgewertet', () async {
      final client = OpenFoodFactsClient(
        client: MockClient((r) async {
          expect(r.url.path, '/api/v2/product/40111445.json');
          return http.Response(
            jsonEncode({
              'status': 1,
              'product': {
                'product_name': 'Riegel',
                'nutriments': {'energy-kcal_100g': 500},
              },
            }),
            200,
          );
        }),
      );
      expect((await client.byBarcode('40111445'))!.id, 'off-40111445');
    });

    test('ungültiger Strichcode geht nicht ins Netz', () async {
      final client = OpenFoodFactsClient(
        client: MockClient((r) async => fail('kein Aufruf erwartet')),
      );
      expect(await client.byBarcode('../../x'), isNull);
    });
  });

  group('KI', () {
    test('liest JSON mitten aus Text und stutzt Unsinn', () {
      final a = parseMealAnalysis('''
Klar! ```json
{"items":[{"name":"Pasta","amount":"250","nutrients":{"kcal":99999,"protein":-3,"carbs":70,"fat":10}},
{"name":"  ","amount":1,"nutrients":{}}],"note":"ok"}
```''');
      expect(a.items.single.name, 'Pasta');
      expect(a.items.single.amount, 250);
      expect(a.items.single.nutrients.kcal, 8000);
      expect(a.items.single.nutrients.protein, 0);
      expect(a.note, 'ok');
    });

    test('fehlende Kalorien kommen aus den Makros', () {
      final a = parseMealAnalysis(
        '{"items":[{"name":"X","amount":100,"nutrients":{"protein":10,"carbs":10,"fat":10}}]}',
      );
      expect(a.items.single.nutrients.kcal, 170);
    });

    test('keine Nährwerte ergibt eine klare Fehlermeldung', () {
      expect(() => parseMealAnalysis('Hallo'), throwsA(isA<AiException>()));
    });

    test('Anfrage nutzt Protokoll, Schlüssel und Bild', () async {
      final client = ChatCompletionsClient(
        const AiConfig(
          baseUrl: 'http://localhost:11434/v1/',
          model: 'vision',
          apiKey: 'k',
        ),
        client: MockClient((r) async {
          expect(
            r.url.toString(),
            'http://localhost:11434/v1/chat/completions',
          );
          expect(r.headers['authorization'], 'Bearer k');
          final body = jsonDecode(r.body) as Map;
          expect(body['model'], 'vision');
          expect(
            jsonEncode(body['messages']),
            contains('data:image/png;base64'),
          );
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content':
                        '{"items":[{"name":"Apfel","amount":180,"nutrients":{"kcal":94}}]}',
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final a = await client.analyzeMeal(
        image: Uint8List.fromList([1, 2, 3]),
        imageMime: 'image/png',
      );
      expect(a.items.single.toFood().forAmount(90).kcal, closeTo(47, 0.1));
    });
  });

  group('FIT', () {
    test('liest eine Einheit', () {
      final s = parseFit(fitFile()).single;
      expect(s.kcal, 512);
      expect(s.sportName, 'Laufen');
      expect(s.seconds, 1800);
      expect(s.distanceM, 5000);
      expect(s.toActivity().minutes, 30);
    });

    test('gleiche Einheit ergibt beim erneuten Import dieselbe ID', () {
      expect(
        parseFit(fitFile()).single.toActivity().id,
        parseFit(fitFile()).single.toActivity().id,
      );
    });

    test('liest FIT aus einem ZIP', () {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('a.fit', fitFile(calories: 300)));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(parseFitOrZip(zip).single.kcal, 300);
    });

    test('kaputte Dateien ergeben einen Fehler statt Absturz', () {
      expect(() => parseFit(Uint8List(5)), throwsA(isA<FitFormatException>()));
      final cut = fitFile();
      expect(
        () => parseFit(Uint8List.sublistView(cut, 0, 20)),
        throwsA(isA<FitFormatException>()),
      );
    });
  });

  group('Serveradresse', () {
    test('ergänzt https und entfernt Schrägstriche', () {
      expect(
        normalizeServerUrl('bociva.example.org/').toString(),
        'https://bociva.example.org',
      );
    });

    test('HTTP nur im eigenen Netz', () {
      expect(
        normalizeServerUrl('http://192.168.1.5:8770').toString(),
        'http://192.168.1.5:8770',
      );
      expect(
        () => normalizeServerUrl('http://bociva.example.org'),
        throwsA(isA<ServerUrlException>()),
      );
    });
  });
}

class _Fake implements SyncTransport {
  _Fake(this.handler);
  final SyncResponse Function(int, List<SyncRecord>) handler;
  @override
  Future<SyncResponse> exchange(int since, List<SyncRecord> changes) async =>
      handler(since, changes);
}

class _FakeAsync implements SyncTransport {
  _FakeAsync(this.handler);
  final Future<SyncResponse> Function(int, List<SyncRecord>) handler;
  @override
  Future<SyncResponse> exchange(int since, List<SyncRecord> changes) =>
      handler(since, changes);
}
