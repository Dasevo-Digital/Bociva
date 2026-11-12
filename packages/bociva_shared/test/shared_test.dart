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

  group('Rezepte', () {
    const flour = Food(
      id: 'f',
      name: 'Mehl',
      per100: Nutrients(kcal: 350, protein: 10, carbs: 70, fat: 1),
    );
    const egg = Food(
      id: 'e',
      name: 'Ei',
      per100: Nutrients(kcal: 150, protein: 13, carbs: 1, fat: 10),
    );
    final recipe = Recipe(
      id: 'r1',
      name: 'Pfannkuchen',
      servings: 4,
      ingredients: [
        RecipeIngredient.fromFood(flour, 200),
        RecipeIngredient.fromFood(egg, 200),
      ],
    );

    test('rechnet Gesamtwert und Portion', () {
      expect(recipe.total.kcal, 1000);
      expect(recipe.perServing.kcal, 250);
      expect(recipe.servingAmount, 100);
      final food = recipe.toFood();
      expect(food.per100.kcal, 250);
      expect(food.forAmount(food.servings.single.amount).kcal, 250);
    });

    test('erscheint in der Suche und lässt sich eintragen', () async {
      final repo = BocivaRepository(MemoryStore());
      await repo.saveRecipe(recipe);
      final found = (await repo.searchLocal('pfannk')).single;
      expect(found.source, FoodSource.recipe);
      await repo.logFood(
        found,
        date: '2026-11-09',
        meal: Meal.dinner,
        amount: 100,
      );
      expect((await repo.diary('2026-11-09')).single.nutrients.kcal, 250);
    });

    test(
      'Änderung behält „zuletzt genutzt“, Löschen entfernt beides',
      () async {
        final repo = BocivaRepository(MemoryStore());
        await repo.saveRecipe(recipe);
        await repo.logFood(
          recipe.toFood(),
          date: '2026-11-09',
          meal: Meal.dinner,
          amount: 100,
        );
        await repo.saveRecipe(
          Recipe(
            id: 'r1',
            name: 'Pfannkuchen dünn',
            servings: 8,
            ingredients: recipe.ingredients,
          ),
        );
        final recent = await repo.recentFoods();
        expect(recent.single.name, 'Pfannkuchen dünn');
        expect((await repo.diary('2026-11-09')).single.name, 'Pfannkuchen');
        await repo.deleteRecipe('r1');
        expect(await repo.recipes(), isEmpty);
        expect(await repo.searchLocal('pfannk'), isEmpty);
      },
    );
  });

  group('Fasten', () {
    test('läuft, zeigt Fortschritt und endet', () async {
      var now = DateTime(2026, 11, 9, 20);
      final repo = BocivaRepository(MemoryStore(), clock: () => now);
      final s = await repo.startFasting(16);
      now = DateTime(2026, 11, 10, 4);
      expect((await repo.activeFasting())!.progress(now), 0.5);
      expect(s.date, '2026-11-09');
      now = DateTime(2026, 11, 10, 12);
      await repo.endFasting(s);
      expect(await repo.activeFasting(), isNull);
      final done = (await repo.fastingSessions()).single;
      expect(done.elapsed(DateTime(2030)), const Duration(hours: 16));
    });

    test('Beginn in der Zukunft wird auf jetzt gesetzt', () async {
      final now = DateTime(2026, 11, 9, 20);
      final repo = BocivaRepository(MemoryStore(), clock: () => now);
      final s = await repo.startFasting(
        16,
        startAt: now.add(const Duration(hours: 3)),
      );
      expect(s.start, now);
    });

    test('Profil schaltet Fasten ein, ohne Rest zu ändern', () {
      const p = Profile(
        sex: Sex.male,
        birthYear: 1980,
        heightCm: 180,
        weightKg: 80,
      );
      final on = p.withFastingEnabled(true);
      expect(on.fastingEnabled, isTrue);
      expect(on.heightCm, 180);
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

    test(
      'ein nicht sendbarer Datensatz blockiert den Abgleich nicht',
      () async {
        final store = MemoryStore();
        await BocivaRepository(store).addWater('2026-11-09', 300);
        // Zum Beispiel von einer älteren App-Version gespeichert.
        await store.put(
          const SyncRecord(
            kind: 'water',
            id: 'kaputt',
            updatedAt: 1,
            data: {'ml': double.nan},
          ),
          dirty: true,
        );
        final engine = SyncEngine(store, fakeServer());
        await engine.run();
        expect(engine.rejected, 1);
        expect(serverRecords.single.data['ml'], 300);
        expect(await store.dirty(), isEmpty);
      },
    );

    test('vom Server abgelehnte Datensätze werden gemeldet', () async {
      final store = MemoryStore();
      await BocivaRepository(store).addWater('2026-11-09', 300);
      final engine = SyncEngine(
        store,
        _Fake(
          (since, changes) => SyncResponse(
            cursor: 1,
            changes: const [],
            hasMore: false,
            rejected: changes.length,
          ),
        ),
      );
      await engine.run();
      expect(engine.rejected, 1);
      expect(await store.dirty(), isEmpty);
    });

    test('HTML statt JSON wird ein ApiException', () async {
      final client = ApiClient(
        Uri.parse('https://bociva.example'),
        token: 't',
        client: MockClient(
          (r) async => http.Response('<html>Anmelden</html>', 200),
        ),
      );
      await expectLater(
        client.exchange(0, const []),
        throwsA(isA<ApiException>()),
      );
      final wrongShape = ApiClient(
        Uri.parse('https://bociva.example'),
        token: 't',
        client: MockClient((r) async => http.Response('{"cursor":"x"}', 200)),
      );
      await expectLater(
        wrongShape.exchange(0, const []),
        throwsA(isA<ApiException>()),
      );
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

  group('Datenschutz vor Überschreiben', () {
    const apple = Food(
      id: 'apfel',
      name: 'Apfel',
      per100: Nutrients(kcal: 52, protein: 0.3, carbs: 14, fat: 0.2),
    );

    test(
      'Eintragen schreibt ein gespeichertes Lebensmittel nicht neu',
      () async {
        final store = MemoryStore();
        final repo = BocivaRepository(store);
        await repo.saveFood(apple);
        final before = await store.get(RecordKind.food, 'apfel');
        // Eine alte Kopie, z. B. aus einer Suchliste von vorhin.
        await repo.logFood(
          const Food(id: 'apfel', name: 'Alt', per100: Nutrients()),
          date: '2026-11-10',
          meal: Meal.snack,
          amount: 100,
        );
        final after = await store.get(RecordKind.food, 'apfel');
        expect(after!.updatedAt, before!.updatedAt);
        expect(after.data['name'], 'Apfel');
        expect((await repo.recentFoods()).single.id, 'apfel');
      },
    );

    test('Eintragen holt ein gelöschtes Lebensmittel nicht zurück', () async {
      final store = MemoryStore();
      final repo = BocivaRepository(store);
      await repo.saveFood(apple);
      await repo.deleteFood('apfel');
      await repo.logFood(
        apple,
        date: '2026-11-10',
        meal: Meal.snack,
        amount: 100,
      );
      expect(await repo.savedFoods(), isEmpty);
      expect((await repo.diary('2026-11-10')).single.name, 'Apfel');
    });

    test('Zuletzt genutzt folgt dem Tagebuch', () async {
      var now = DateTime(2026, 11, 10, 8);
      final repo = BocivaRepository(MemoryStore(), clock: () => now);
      const pear = Food(id: 'birne', name: 'Birne', per100: Nutrients());
      await repo.logFood(
        apple,
        date: '2026-11-10',
        meal: Meal.snack,
        amount: 1,
      );
      now = now.add(const Duration(hours: 1));
      await repo.logFood(pear, date: '2026-11-10', meal: Meal.snack, amount: 1);
      now = now.add(const Duration(hours: 1));
      await repo.logFood(
        apple,
        date: '2026-11-10',
        meal: Meal.snack,
        amount: 1,
      );
      expect(
        [for (final f in await repo.recentFoods()) f.id],
        ['apfel', 'birne'],
      );
    });

    test(
      'Gewicht ändert das Profil nicht, die Ziele gehen trotzdem mit',
      () async {
        final store = MemoryStore();
        final repo = BocivaRepository(store);
        await repo.saveProfile(
          const Profile(
            sex: Sex.female,
            birthYear: 1990,
            heightCm: 170,
            weightKg: 70,
            fastingEnabled: true,
          ),
        );
        final before = await store.get(RecordKind.profile, 'me');
        await repo.saveWeight(const WeightEntry(date: '2026-11-01', kg: 68));
        await repo.saveWeight(const WeightEntry(date: '2026-10-01', kg: 75));
        final after = await store.get(RecordKind.profile, 'me');
        expect(after!.updatedAt, before!.updatedAt);
        final p = (await repo.profile())!;
        expect(p.weightKg, 68);
        expect(p.fastingEnabled, isTrue);
      },
    );

    test(
      'Ungültige Zahlen und zu große Einträge werden nicht gespeichert',
      () async {
        final store = MemoryStore();
        final repo = BocivaRepository(store);
        await expectLater(
          repo.logFood(
            apple,
            date: '2026-11-10',
            meal: Meal.snack,
            amount: double.nan,
          ),
          throwsA(isA<InvalidRecordException>()),
        );
        await expectLater(
          repo.saveRecipe(
            Recipe(
              id: 'r',
              name: 'Groß',
              servings: 1,
              ingredients: const [],
              note: 'x' * 70000,
            ),
          ),
          throwsA(isA<InvalidRecordException>()),
        );
        expect(await store.dirty(), isEmpty);
        expect(Nutrients.fromJson({'kcal': 'NaN'}).kcal, 0);
        expect(
          Profile.fromJson({'waterOverrideMl': 'Infinity'}).waterOverrideMl,
          isNull,
        );
      },
    );
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
          // Manche Modelle lehnen Anfragen mit temperature ab.
          expect(body.containsKey('temperature'), isFalse);
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

  group('Serie', () {
    test('zählt bis heute, wenn heute eingetragen ist', () {
      final s = Streak.fromDates({
        '2026-03-27',
        '2026-03-28',
        '2026-03-29',
        '2026-03-30',
      }, '2026-03-30');
      expect(s.current, 4);
      expect(s.todayDone, isTrue);
      expect(s.atRisk, isFalse);
    });

    test('hält bis Mitternacht, wenn heute noch nichts eingetragen ist', () {
      final s = Streak.fromDates({'2026-01-30', '2026-01-31'}, '2026-02-01');
      expect(s.current, 2);
      expect(s.todayDone, isFalse);
      expect(s.atRisk, isTrue);
      expect(s.nextMilestone, 3);
    });

    test('reißt nach einem leeren Tag', () {
      final s = Streak.fromDates({'2026-05-01', '2026-05-02'}, '2026-05-04');
      expect(s.current, 0);
      expect(s.longest, 2);
      expect(s.atRisk, isFalse);
    });

    test('längste Serie und Tage in der Zukunft', () {
      final s = Streak.fromDates({
        '2025-12-30',
        '2025-12-31',
        '2026-01-01',
        '2026-01-02',
        '2026-01-05',
        '2026-01-06',
        '2026-01-08',
      }, '2026-01-06');
      expect(s.current, 2);
      expect(s.longest, 4);
      expect(s.totalDays, 6);
      expect(s.tracked('2026-01-08'), isFalse);
      expect(s.lastDays(3), ['2026-01-04', '2026-01-05', '2026-01-06']);
    });

    test('über die Zeitumstellung hinweg', () {
      final s = Streak.fromDates({
        '2026-03-28',
        '2026-03-29',
        '2026-03-30',
      }, '2026-03-30');
      expect(s.current, 3);
      expect(s.isMilestone, isTrue);
    });

    test('nur nicht gelöschte Tagebucheinträge zählen', () async {
      final repo = BocivaRepository(MemoryStore());
      final food = basicFoods.first;
      final first = await repo.logFood(
        food,
        date: '2026-04-01',
        meal: Meal.lunch,
        amount: 100,
      );
      await repo.logFood(
        food,
        date: '2026-04-02',
        meal: Meal.lunch,
        amount: 100,
      );
      await repo.addWater('2026-04-03', 250);
      expect((await repo.streak('2026-04-03')).current, 2);
      await repo.deleteDiary(first.id);
      expect((await repo.streak('2026-04-03')).current, 1);
      expect((await repo.streak('2026-04-04')).current, 0);
    });
  });

  test('Mahlzeit vom Vortag übernehmen', () async {
    var now = DateTime(2026, 5, 2, 8);
    final repo = BocivaRepository(MemoryStore(), clock: () => now);
    for (final f in basicFoods.take(2)) {
      await repo.logFood(
        f,
        date: '2026-05-01',
        meal: Meal.breakfast,
        amount: 50,
      );
    }
    await repo.logFood(
      basicFoods[3],
      date: '2026-05-01',
      meal: Meal.dinner,
      amount: 200,
    );
    final copies = await repo.copyMeal(
      fromDate: '2026-05-01',
      toDate: '2026-05-02',
      meal: Meal.breakfast,
    );
    expect(copies, hasLength(2));
    final today = await repo.diary('2026-05-02');
    expect(today.map((e) => e.name), [basicFoods[0].name, basicFoods[1].name]);
    expect(today.map((e) => e.meal).toSet(), {Meal.breakfast});
    // Neue IDs und verschiedene Zeitpunkte, der Vortag bleibt unverändert.
    expect(today.map((e) => e.id).toSet(), hasLength(2));
    expect(today[0].createdAt, isNot(today[1].createdAt));
    expect(await repo.diary('2026-05-01'), hasLength(3));
    expect(
      await repo.copyMeal(
        fromDate: '2026-05-01',
        toDate: '2026-05-02',
        meal: Meal.lunch,
      ),
      isEmpty,
    );
  });

  group('Gewichtstrend', () {
    List<WeightEntry> series(double start, double perDay, int days) => [
      for (var i = 0; i < days; i++)
        WeightEntry(
          date: dateKey(DateTime(2026, 1, 1 + i)),
          kg: start + perDay * i + (i.isEven ? 0.6 : -0.6),
        ),
    ];

    test('glättet Schwankungen und misst das Tempo', () {
      final t = WeightTrend.of(series(80, -0.1, 42), target: 74);
      // Rohwerte springen um 1,2 kg, der Trend kaum.
      final jumps = [
        for (var i = 1; i < t.trend.length; i++)
          (t.trend[i] - t.trend[i - 1]).abs(),
      ];
      expect(jumps.reduce((a, b) => a > b ? a : b), lessThan(0.35));
      expect(t.ratePerWeek, closeTo(-0.7, 0.15));
      expect(t.eta, isNotNull);
      expect(t.eta!.isAfter(DateTime(2026, 2, 11)), isTrue);
      expect(t.awayFromTarget, isFalse);
    });

    test('bemerkt, wenn es vom Ziel weggeht', () {
      final t = WeightTrend.of(series(70, 0.05, 30), target: 65);
      expect(t.ratePerWeek, greaterThan(0));
      expect(t.eta, isNull);
      expect(t.awayFromTarget, isTrue);
    });

    test('zu wenige Messungen ergeben kein Tempo', () {
      final t = WeightTrend.of(const [
        WeightEntry(date: '2026-01-01', kg: 80),
        WeightEntry(date: '2026-01-03', kg: 79.5),
      ], target: 75);
      expect(t.trend, hasLength(2));
      expect(t.ratePerWeek, isNull);
      expect(t.eta, isNull);
    });

    test('Ziel erreicht und leere Liste', () {
      expect(
        WeightTrend.of(const [
          WeightEntry(date: '2026-01-01', kg: 65.1),
        ], target: 65).reached,
        isTrue,
      );
      final empty = WeightTrend.of(const []);
      expect(empty.current, isNull);
      expect(empty.trend, isEmpty);
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
