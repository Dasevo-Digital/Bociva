import 'dart:io';

import 'package:bociva/main.dart';
import 'package:bociva/src/controller.dart';
import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lässt echte Zeit vergehen; `pumpAndSettle` allein wartet nicht auf das
/// System, etwa auf die Tastatur.
Future<void> _settleFor(WidgetTester tester, Duration duration) async {
  await tester.runAsync(() => Future<void>.delayed(duration));
  await tester.pumpAndSettle();
}

/// Nur im Simulator oder Emulator ausführen: Der Test setzt eine frisch
/// installierte App voraus.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Ohne Server: einrichten, eintragen, Neustart', (tester) async {
    await initializeDateFormatting('de');
    final controller = AppController();
    await tester.pumpWidget(BocivaApp(controller: controller));
    await controller.start();
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile-birth')), '1990');
    await tester.enterText(find.byKey(const Key('profile-height')), '170');
    await tester.enterText(find.byKey(const Key('profile-weight')), '70');
    await tester.pumpAndSettle();

    // Die Tastatur soll den Knopf nicht mehr verschieben, während getippt wird;
    // auf einem gerade gestarteten Emulator fährt sie erst spät ein.
    FocusManager.instance.primaryFocus?.unfocus();
    await _settleFor(tester, const Duration(seconds: 2));

    final save = find.byKey(const Key('profile-save'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await _settleFor(tester, const Duration(seconds: 2));
    debugPrint('Profil gespeichert: ${controller.profile != null}');

    expect(find.byKey(const Key('kcal-remaining')), findsOneWidget);
    expect(controller.day!.goals.kcal, greaterThan(1200));

    await controller.repo.logFood(
      basicFoods.firstWhere((f) => f.name == 'Banane'),
      date: controller.date,
      meal: Meal.breakfast,
      amount: 120,
    );
    await controller.reload();
    await tester.pumpAndSettle();
    expect(find.text('Banane'), findsOneWidget);

    final water = find.byKey(const Key('water-250'));
    await tester.scrollUntilVisible(
      water,
      300,
      scrollable: find
          .descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(water);
    await tester.pumpAndSettle();
    expect(controller.day!.waterMl, 250);

    // Ein neuer Controller liest dieselbe Datenbank wie nach einem Neustart.
    final restarted = AppController();
    await restarted.start();
    expect(restarted.profile, isNotNull);
    expect(restarted.day!.entries.single.name, 'Banane');
    expect(restarted.day!.waterMl, 250);

    final dir = await getApplicationSupportDirectory();
    final raf = File(p.join(dir.path, 'bociva.db')).openSync();
    final header = String.fromCharCodes(raf.readSync(16));
    raf.closeSync();
    expect(header, isNot(startsWith('SQLite format')));
  });
}
