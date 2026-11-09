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
            return _StartError(message: controller.startError!);
          }
          if (!controller.ready) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (controller.mustConnect) return const ConnectScreen(webMode: true);
          if (controller.profile == null) return const OnboardingScreen();
          return const Shell();
        },
      ),
    ),
  );
}

class _StartError extends StatelessWidget {
  const _StartError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    ),
  );
}
