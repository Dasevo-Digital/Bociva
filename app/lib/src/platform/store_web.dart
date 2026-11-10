import 'package:bociva_shared/bociva_shared.dart';

/// Im Browser bleiben keine Gesundheitsdaten liegen; sie kommen beim Start
/// vom Server.
Future<LocalStore> openLocalStore({
  required Future<String?> Function() readKey,
  required Future<String> Function() createKey,
}) async => MemoryStore();

Future<void> deleteLocalStore() async {}
