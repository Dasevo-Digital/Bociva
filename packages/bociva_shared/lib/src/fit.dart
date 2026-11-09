import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

class FitFormatException implements Exception {
  const FitFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Eine Trainingseinheit aus einer FIT-Datei.
class FitSession {
  const FitSession({
    required this.start,
    required this.sport,
    required this.seconds,
    required this.kcal,
    required this.distanceM,
  });

  final DateTime start;
  final int sport;
  final double seconds, distanceM;
  final int kcal;

  String get sportName => switch (sport) {
    1 => 'Laufen',
    2 => 'Radfahren',
    5 => 'Schwimmen',
    10 => 'Training',
    11 => 'Gehen',
    13 => 'Fitnessgeräte',
    15 => 'Rudern',
    17 => 'Wandern',
    _ => 'Training',
  };

  ActivityEntry toActivity() => ActivityEntry(
    // Aus der Startzeit: derselbe Lauf, zweimal importiert, bleibt einer.
    id: 'fit-${start.millisecondsSinceEpoch ~/ 1000}',
    date: dateKey(start.toLocal()),
    kind: ActivityKind.workout,
    source: 'fit',
    activeKcal: kcal.toDouble(),
    title: sportName,
    minutes: (seconds / 60).round(),
    distanceM: distanceM,
  );
}

const _sessionMessage = 18;
const _fitEpochSeconds = 631065600; // 1989-12-31T00:00:00Z

class _Field {
  const _Field(this.number, this.size);
  final int number, size;
}

class _Definition {
  const _Definition(this.global, this.bigEndian, this.fields, this.extraBytes);
  final int global, extraBytes;
  final bool bigEndian;
  final List<_Field> fields;
}

/// Liest die Einheiten aus einer FIT-Datei. Von Fremddaten ausgehend: jede
/// Leseposition wird geprüft, kaputte Dateien enden in einer Fehlermeldung.
List<FitSession> parseFit(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 14) {
    throw const FitFormatException('Die Datei ist zu kurz für FIT.');
  }
  final headerSize = bytes[0];
  if ((headerSize != 12 && headerSize != 14) ||
      String.fromCharCodes(bytes, 8, 12) != '.FIT') {
    throw const FitFormatException('Das ist keine FIT-Datei.');
  }
  final dataSize = data.getUint32(4, Endian.little);
  final end = headerSize + dataSize;
  if (end > bytes.length) {
    throw const FitFormatException('Die FIT-Datei ist unvollständig.');
  }

  final definitions = <int, _Definition>{};
  final sessions = <FitSession>[];
  var pos = headerSize;

  void need(int count) {
    if (pos + count > end) {
      throw const FitFormatException('Die FIT-Datei ist beschädigt.');
    }
  }

  while (pos < end) {
    need(1);
    final header = bytes[pos++];
    final compressedTime = header & 0x80 != 0;
    final isDefinition = !compressedTime && header & 0x40 != 0;
    final hasDeveloperFields = !compressedTime && header & 0x20 != 0;
    final local = compressedTime ? (header >> 5) & 0x03 : header & 0x0F;

    if (isDefinition) {
      need(5);
      pos++; // reserviert
      final bigEndian = bytes[pos++] == 1;
      final global = data.getUint16(
        pos,
        bigEndian ? Endian.big : Endian.little,
      );
      pos += 2;
      final count = bytes[pos++];
      need(count * 3);
      final fields = <_Field>[];
      for (var i = 0; i < count; i++) {
        fields.add(_Field(bytes[pos], bytes[pos + 1]));
        pos += 3;
      }
      var extra = 0;
      if (hasDeveloperFields) {
        need(1);
        final devCount = bytes[pos++];
        need(devCount * 3);
        for (var i = 0; i < devCount; i++) {
          extra += bytes[pos + 1];
          pos += 3;
        }
      }
      definitions[local] = _Definition(global, bigEndian, fields, extra);
      continue;
    }

    final def = definitions[local];
    if (def == null) {
      throw const FitFormatException('Die FIT-Datei ist beschädigt.');
    }
    final values = <int, int>{};
    final order = def.bigEndian ? Endian.big : Endian.little;
    for (final field in def.fields) {
      need(field.size);
      if (def.global == _sessionMessage) {
        final v = switch (field.size) {
          1 => bytes[pos] == 0xFF ? null : bytes[pos],
          2 => () {
            final x = data.getUint16(pos, order);
            return x == 0xFFFF ? null : x;
          }(),
          4 => () {
            final x = data.getUint32(pos, order);
            return x == 0xFFFFFFFF ? null : x;
          }(),
          _ => null,
        };
        if (v != null) values[field.number] = v;
      }
      pos += field.size;
    }
    need(def.extraBytes);
    pos += def.extraBytes;

    if (def.global == _sessionMessage && values[2] != null) {
      sessions.add(
        FitSession(
          start: DateTime.fromMillisecondsSinceEpoch(
            (values[2]! + _fitEpochSeconds) * 1000,
            isUtc: true,
          ),
          sport: values[5] ?? 0,
          seconds: (values[8] ?? values[7] ?? 0) / 1000,
          distanceM: (values[9] ?? 0) / 100,
          kcal: values[11] ?? 0,
        ),
      );
    }
  }
  return sessions;
}

/// Liest eine .fit-Datei oder ein .zip, wie es Garmin Connect beim Export
/// einer Aktivität liefert.
List<FitSession> parseFitOrZip(Uint8List bytes) {
  const maxEntries = 500, maxEntrySize = 32 * 1024 * 1024;
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  if (!isZip) return parseFit(bytes);
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const FitFormatException('Das ZIP-Archiv ist beschädigt.');
  }
  final fits = archive.files
      .where((f) => f.isFile && f.name.toLowerCase().endsWith('.fit'))
      .take(maxEntries);
  final sessions = <FitSession>[];
  for (final file in fits) {
    if (file.size > maxEntrySize) continue;
    sessions.addAll(parseFit(file.content));
  }
  if (sessions.isEmpty) {
    throw const FitFormatException('Im Archiv ist keine Aktivität enthalten.');
  }
  return sessions;
}
