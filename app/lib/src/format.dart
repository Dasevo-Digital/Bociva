import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _int = NumberFormat('#,##0', 'de');
final _one = NumberFormat('#,##0.#', 'de');
final _input = NumberFormat('0.#', 'de');

/// Zum Anzeigen, mit Tausenderpunkt.
String fmtInt(num v) => _int.format(v.round());
String fmtOne(num v) => _one.format(v);

/// Zum Vorbelegen von Eingabefeldern: ohne Tausenderpunkt, damit
/// [parseNumber] den Wert unverändert zurückliest.
String fmtInput(num v) => _input.format(v);

final _grouped = RegExp(r'^\d{1,3}(\.\d{3})+$');
final _plain = RegExp(r'^\d+(\.\d+)?$');

/// Liest Zahlen wie „1500“, „1.500“, „1.234,5“, „72,5“ oder „72.5“.
/// Gibt nur endliche, nicht negative Werte zurück.
double? parseNumber(String text) {
  var s = text.trim().replaceAll(' ', '').replaceAll(' ', '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    // Deutsch: Punkte gruppieren, das Komma trennt die Nachkommastellen.
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (_grouped.hasMatch(s)) {
    s = s.replaceAll('.', '');
  }
  if (!_plain.hasMatch(s)) return null;
  final v = double.tryParse(s);
  return v != null && v.isFinite ? v : null;
}

void showMessage(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$message')));
}
