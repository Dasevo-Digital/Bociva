import 'package:bociva/src/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  test('Vorbelegte Felder lesen sich unverändert zurück', () {
    for (final v in [0.5, 72.5, 100, 999, 1000, 1500, 2000, 12345.5]) {
      expect(parseNumber(fmtInput(v)), v, reason: fmtInput(v));
    }
  });

  test('Deutsche und englische Schreibweisen', () {
    expect(parseNumber('1.500'), 1500);
    expect(parseNumber('1.234,5'), 1234.5);
    expect(parseNumber('72,5'), 72.5);
    expect(parseNumber('72.5'), 72.5);
    expect(parseNumber(' 2 000 '), 2000);
    expect(parseNumber('1.5'), 1.5);
  });

  test('Ungültiges ergibt null', () {
    for (final s in ['', 'NaN', 'Infinity', '-Infinity', '1e5', '-3', 'abc']) {
      expect(parseNumber(s), isNull, reason: s);
    }
  });
}
