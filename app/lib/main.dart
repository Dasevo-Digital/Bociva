import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/controller.dart';
import 'src/screens/connect_screen.dart';
import 'src/screens/onboarding_screen.dart';
import 'src/screens/shell.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');
  final controller = AppController();
  runApp(BocivaApp(controller: controller));
  await controller.start();
}

class BocivaApp extends StatelessWidget {
  const BocivaApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ControllerScope(
    controller: controller,
    child: MaterialApp(
      title: 'Bociva',
      debugShowCheckedModeBanner: false,
      theme: bocivaTheme(Brightness.light),
      darkTheme: bocivaTheme(Brightness.dark),
      locale: const Locale('de'),
      supportedLocales: const [Locale('de')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Der Ziffernblock von iOS hat keine Fertig-Taste: Tippen neben ein Feld
      // schließt die Tastatur.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.startError != null) {
            return _StartError(controller: controller);
          }
          if (!controller.ready) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (controller.mustConnect) return const ConnectScreen(webMode: true);
          if (controller.awaitingFirstSync) {
            return _FirstSync(controller: controller);
          }
          if (controller.profile == null) return const OnboardingScreen();
          return const Shell();
        },
      ),
    ),
  );
}

class _StartError extends StatelessWidget {
  const _StartError({required this.controller});
  final AppController controller;

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daten auf diesem Gerät zurücksetzen?'),
        content: Text(
          controller.isConnected
              ? 'Die nicht lesbaren Daten werden gelöscht. Was schon auf dem '
                    'Server liegt, kommt danach wieder.'
              : 'Die nicht lesbaren Daten werden endgültig gelöscht. Danach '
                    'beginnt Bociva von vorn.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('reset-store-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Zurücksetzen'),
          ),
        ],
      ),
    );
    if (ok == true) await controller.resetLocalStore();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(controller.startError!, textAlign: TextAlign.center),
            if (controller.canResetStore) ...[
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('reset-store'),
                onPressed: () => _reset(context),
                child: const Text('Zurücksetzen'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Verbunden, aber die Daten des Kontos sind noch nicht da.
class _FirstSync extends StatelessWidget {
  const _FirstSync({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.syncing ? null : controller.syncError;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Daten werden vom Server geladen …'),
              ] else ...[
                Text(
                  'Die Daten des Kontos ließen sich nicht laden.\n$error',
                  key: const Key('first-sync-error'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('first-sync-retry'),
                  onPressed: controller.syncNow,
                  child: const Text('Erneut versuchen'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => controller.disconnect(force: true),
                  child: const Text('Abmelden'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
