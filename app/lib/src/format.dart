import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _int = NumberFormat('#,##0', 'de');
final _one = NumberFormat('#,##0.#', 'de');

String fmtInt(num v) => _int.format(v.round());
String fmtOne(num v) => _one.format(v);

/// Liest Zahlen mit Komma oder Punkt.
double? parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

void showMessage(BuildContext context, Object message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$message')));
}
