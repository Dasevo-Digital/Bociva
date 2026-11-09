import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'api_error.dart';
import 'database.dart';

class User {
  const User(this.id, this.username, this.isAdmin);
  final String id, username;
  final bool isAdmin;

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'isAdmin': isAdmin,
  };
}

String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _token() {
  final random = Random.secure();
  return base64Url
      .encode(List.generate(32, (_) => random.nextInt(256)))
      .replaceAll('=', '');
}

class Accounts {
  Accounts(this.db, {this.iterations = 310000});

  final Database db;
  final int iterations;

  static const sessionDays = 90;
  static const inviteDays = 7;
  static const _setupKey = 'setup_code_hash';

  /// Vergleichswert, damit eine Anmeldung mit unbekanntem Namen genauso lange
  /// dauert wie eine mit falschem Passwort.
  late final Future<String> _dummyHash = hashPassword(_token());

  int get _now => DateTime.now().millisecondsSinceEpoch;

  bool get setupRequired => db.select('SELECT 1 FROM users LIMIT 1').isEmpty;

  /// Das erste Konto braucht einen Code aus dem Serverprotokoll: Sonst könnte
  /// jeder, der den frischen Server zuerst erreicht, Administrator werden.
  /// Gibt den neuen Code zurück, solange noch kein Konto existiert.
  String? ensureSetupCode() {
    if (!setupRequired) return null;
    final code = _readableCode();
    db.execute('INSERT OR REPLACE INTO settings VALUES (?, ?)', [
      _setupKey,
      sha256Hex(code),
    ]);
    return code;
  }

  String _readableCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random.secure();
    return List.generate(12, (_) => chars[random.nextInt(chars.length)]).join();
  }

  String createInvite() {
    final code = _readableCode();
    db.execute('INSERT INTO invites VALUES (?, ?)', [
      sha256Hex(code),
      _now + inviteDays * 86400000,
    ]);
    return code;
  }

  static final _nameRe = RegExp(r'^[\p{L}\p{N}._-]{2,40}$', unicode: true);

  void _checkPassword(String password) {
    if (password.length < 10 || password.length > 256) {
      throw const ApiError(
        400,
        'weak-password',
        'Das Passwort braucht mindestens 10 Zeichen.',
      );
    }
  }

  Future<(User, String)> register(
    String username,
    String password,
    String code,
  ) async {
    if (!_nameRe.hasMatch(username)) {
      throw const ApiError(
        400,
        'bad-username',
        'Der Name braucht 2 bis 40 Zeichen: Buchstaben, Ziffern, . _ -',
      );
    }
    _checkPassword(password);
    final hash = await hashPassword(password);
    final codeHash = sha256Hex(code.trim().toUpperCase());
    db.execute('BEGIN IMMEDIATE');
    try {
      final first = setupRequired;
      if (first) {
        final stored = db.select('SELECT value FROM settings WHERE key = ?', [
          _setupKey,
        ]);
        if (stored.isEmpty || stored.first['value'] != codeHash) {
          throw const ApiError(403, 'bad-code', 'Der Code stimmt nicht.');
        }
        db.execute('DELETE FROM settings WHERE key = ?', [_setupKey]);
      } else {
        db.execute(
          'DELETE FROM invites WHERE code_hash = ? AND expires_at > ?',
          [codeHash, _now],
        );
        if (db.updatedRows != 1) {
          throw const ApiError(
            403,
            'bad-code',
            'Die Einladung ist ungültig oder abgelaufen.',
          );
        }
      }
      if (db.select('SELECT 1 FROM users WHERE username = ?', [
        username,
      ]).isNotEmpty) {
        throw const ApiError(409, 'name-taken', 'Der Name ist schon vergeben.');
      }
      final user = User(randomHex(16), username, first);
      db.execute(
        'INSERT INTO users (id, username, password_hash, is_admin, created_at) '
        'VALUES (?, ?, ?, ?, ?)',
        [user.id, username, hash, first ? 1 : 0, _now],
      );
      final token = _newSession(user.id);
      db.execute('COMMIT');
      return (user, token);
    } on Object {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  String _newSession(String userId) {
    final token = _token();
    db.execute('INSERT INTO sessions VALUES (?, ?, ?)', [
      sha256Hex(token),
      userId,
      _now + sessionDays * 86400000,
    ]);
    return token;
  }

  Future<(User, String)?> login(String username, String password) async {
    final rows = db.select(
      'SELECT id, username, password_hash, is_admin FROM users '
      'WHERE username = ?',
      [username],
    );
    final stored = rows.isEmpty
        ? await _dummyHash
        : rows.first['password_hash'] as String;
    final ok = await verifyPassword(password, stored);
    if (rows.isEmpty || !ok) return null;
    final r = rows.first;
    final user = User(
      r['id'] as String,
      r['username'] as String,
      r['is_admin'] == 1,
    );
    return (user, _newSession(user.id));
  }

  User? authenticate(String token) {
    final hash = sha256Hex(token);
    final rows = db.select(
      'SELECT u.id, u.username, u.is_admin, s.expires_at FROM sessions s '
      'JOIN users u ON u.id = s.user_id WHERE s.token_hash = ? '
      'AND s.expires_at > ?',
      [hash, _now],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    // Aktive Geräte bleiben angemeldet, höchstens einmal täglich geschrieben.
    final renewed = _now + sessionDays * 86400000;
    if (renewed - (r['expires_at'] as int) > 86400000) {
      db.execute('UPDATE sessions SET expires_at = ? WHERE token_hash = ?', [
        renewed,
        hash,
      ]);
    }
    return User(r['id'] as String, r['username'] as String, r['is_admin'] == 1);
  }

  void logout(String token) => db.execute(
    'DELETE FROM sessions WHERE token_hash = ?',
    [sha256Hex(token)],
  );

  Future<bool> checkPassword(String userId, String password) async {
    final rows = db.select('SELECT password_hash FROM users WHERE id = ?', [
      userId,
    ]);
    if (rows.isEmpty) return false;
    return verifyPassword(password, rows.first['password_hash'] as String);
  }

  /// Löscht das Konto samt aller Datensätze und Sitzungen.
  void deleteUser(String userId) =>
      db.execute('DELETE FROM users WHERE id = ?', [userId]);

  void purgeExpired() {
    db.execute('DELETE FROM sessions WHERE expires_at <= ?', [_now]);
    db.execute('DELETE FROM invites WHERE expires_at <= ?', [_now]);
  }

  Future<String> hashPassword(String password) async {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    final rounds = iterations;
    final key = await Isolate.run(
      () => _pbkdf2(utf8.encode(password), salt, rounds),
    );
    return 'pbkdf2_sha256\$$rounds\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  Future<bool> verifyPassword(String password, String stored) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2_sha256') return false;
    final rounds = int.parse(parts[1]);
    final salt = base64.decode(parts[2]);
    final actual = await Isolate.run(
      () => _pbkdf2(utf8.encode(password), salt, rounds),
    );
    return constantTimeEquals(actual, base64.decode(parts[3]));
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int rounds) {
    final mac = Hmac(sha256, password);
    var block = mac.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = List<int>.of(block);
    for (var i = 1; i < rounds; i++) {
      block = mac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return result;
  }
}
