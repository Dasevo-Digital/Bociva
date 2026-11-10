import 'package:bociva_shared/bociva_shared.dart';

/// Öffnet die Datenablage. [readKey] liefert den gespeicherten Schlüssel,
/// [createKey] legt einen neuen an.
typedef StoreOpener = Future<LocalStore> Function({
  required Future<String?> Function() readKey,
  required Future<String> Function() createKey,
});

/// Die Datenbank liegt vor, aber ihr Schlüssel fehlt oder passt nicht, etwa
/// nach einer Wiederherstellung auf einem neuen Gerät.
class LocalStoreLocked implements Exception {
  const LocalStoreLocked();
}
