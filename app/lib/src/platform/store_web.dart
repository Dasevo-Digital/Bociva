import 'package:bociva_shared/bociva_shared.dart';

/// Im Browser bleiben keine Gesundheitsdaten liegen; sie kommen beim Start
/// vom Server.
Future<LocalStore> openLocalStore(Future<String> Function() key) async =>
    MemoryStore();
