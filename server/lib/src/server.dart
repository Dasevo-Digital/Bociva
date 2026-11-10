import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'accounts.dart';
import 'api_error.dart';
import 'config.dart';
import 'database.dart';
import 'limits.dart';
import 'web_app.dart';

const version = '0.1.0';

class BocivaServer {
  BocivaServer._(this._http, this._db, this.setupCode, this._purge);

  /// Für den Fall einer Prüfung in Tests.
  final HttpServer _http;
  final Database _db;
  final Timer _purge;

  /// Nur gesetzt, solange noch kein Konto existiert.
  final String? setupCode;

  int get port => _http.port;

  /// Für Tests.
  Database get database => _db;

  static Future<BocivaServer> start(
    ServerConfig config, {
    http.Client? httpClient,
    int? passwordIterations,
    FoodLookup? foodLookup,
    AiBackend? ai,
  }) async {
    final Database db;
    if (config.inMemory) {
      db = openDatabase(':memory:');
    } else {
      Directory(config.dataDir).createSync(recursive: true);
      final file = File(p.join(config.dataDir, 'bociva.db'));
      final key = loadOrCreateKey(config.keyFile!, file);
      db = openDatabase(file.path, hexKey: key);
    }
    migrate(db);
    final accounts = Accounts(db, iterations: passwordIterations ?? 310000);
    final setupCode = accounts.ensureSetupCode();
    final client = httpClient ?? http.Client();
    final contact = config.foodContact;
    final api = _Api(
      config: config,
      db: db,
      accounts: accounts,
      records: RecordService(
        db,
        maxBytesPerUser: config.userQuotaMb * 1024 * 1024,
      ),
      food:
          foodLookup ??
          OpenFoodFactsClient(
            client: client,
            userAgent:
                'Bociva/$version (self-hosted${contact == null ? '' : '; $contact'})',
          ),
      ai:
          ai ??
          (config.ai == null
              ? null
              : ChatCompletionsClient(config.ai!, client: client)),
      web: WebApp.locate(config.webDir),
    );
    final server = await io.serve(api.handler, config.host, config.port);
    final purge = Timer.periodic(const Duration(hours: 6), (_) {
      try {
        accounts.purgeExpired();
        db.execute('DELETE FROM food_cache WHERE fetched_at < ?', [
          DateTime.now().millisecondsSinceEpoch - _Api.foodCacheMs,
        ]);
      } on Object catch (e) {
        // Etwa bei vollem Datenträger: melden, aber weiterlaufen.
        stderr.writeln('Aufräumen fehlgeschlagen: $e');
      }
    });
    return BocivaServer._(server, db, setupCode, purge);
  }

  Future<void> close() async {
    _purge.cancel();
    await _http.close(force: true);
    _db.close();
  }
}

class _Api {
  _Api({
    required this.config,
    required this.db,
    required this.accounts,
    required this.records,
    required this.food,
    required this.ai,
    required this.web,
  });

  final ServerConfig config;
  final Database db;
  final Accounts accounts;
  final RecordService records;
  final FoodLookup food;
  final AiBackend? ai;
  final WebApp? web;

  final _loginLimit = RateLimiter(10, const Duration(minutes: 15));

  /// Wechselnde Namen von derselben Adresse hebeln das obere Limit sonst aus.
  final _loginIpLimit = RateLimiter(50, const Duration(minutes: 15));
  final _registerLimit = RateLimiter(10, const Duration(hours: 1));
  final _deleteLimit = RateLimiter(5, const Duration(minutes: 15));
  final _syncLimit = RateLimiter(120, const Duration(minutes: 1));
  final _aiLimit = RateLimiter(30, const Duration(minutes: 10));
  late final _aiBudget = RateLimiter(
    config.aiDailyLimit,
    const Duration(days: 1),
  );
  final _aiGate = Gate(4, maxQueue: 16);
  final _foodLimit = RateLimiter(60, const Duration(minutes: 1));
  bool _warnedProxy = false;

  /// Open Food Facts erlaubt nur wenige Suchanfragen pro Minute und Quelle.
  final _foodSearchLimit = RateLimiter(10, const Duration(minutes: 1));

  static const _maxJsonBytes = 8 * 1024 * 1024;
  static const _maxAuthBytes = 16 * 1024;
  static const _maxImageBytes = 6 * 1024 * 1024;
  static const foodCacheMs = 30 * 86400000;
  static const _foodMissCacheMs = 86400000;

  Handler get handler => const Pipeline()
      .addMiddleware(_errors)
      .addMiddleware(_securityHeaders)
      .addHandler(_router.call);

  Router get _router {
    final r = Router(notFoundHandler: _notFound);
    r.get('/api/health', _health);
    r.post('/api/auth/register', _register);
    r.post('/api/auth/login', _login);
    r.post('/api/auth/logout', _user(_logout));
    r.get('/api/me', _user((q, u) async => _json({'user': u.toJson()})));
    r.delete('/api/account', _user(_deleteAccount));
    r.post('/api/sync', _user(_sync));
    r.get('/api/export', _user(_export));
    r.get('/api/foods/barcode/<code>', _foodByBarcode);
    r.get('/api/foods/search', _user(_foodSearch));
    r.post('/api/ai/analyze', _user(_aiAnalyze));
    r.post('/api/ai/review', _user(_aiReview));
    r.post('/api/admin/invites', _user(_createInvite));
    return r;
  }

  Response _json(Object? body, {int status = 200}) => Response(
    status,
    body: jsonEncode(body),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  Middleware get _errors =>
      (inner) => (request) async {
        try {
          return await inner(request);
        } on ApiError catch (e) {
          return _json({
            'error': e.code,
            'message': e.message,
          }, status: e.status);
        } on AiException catch (e) {
          return _json({'error': 'ai', 'message': e.message}, status: 502);
        } on FoodLookupException catch (e) {
          return _json({'error': 'food', 'message': e.message}, status: 502);
        } on QuotaExceeded {
          return _json({
            'error': 'quota',
            'message':
                'Der Speicherplatz deines Kontos auf dem Server ist voll.',
          }, status: 413);
        } on HttpException catch (e) {
          // Die Gegenseite hat die Verbindung abgebrochen; kein Stacktrace,
          // sonst ließe sich das Protokoll damit fluten.
          stderr.writeln('${request.method} ${request.url.path}: ${e.message}');
          return _json({
            'error': 'aborted',
            'message': 'Die Anfrage wurde abgebrochen.',
          }, status: 400);
        } catch (e, stack) {
          stderr.writeln('${request.method} ${request.url.path}: $e\n$stack');
          return _json({
            'error': 'internal',
            'message': 'Interner Serverfehler.',
          }, status: 500);
        }
      };

  Middleware get _securityHeaders =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(
          headers: {
            'x-content-type-options': 'nosniff',
            'referrer-policy': 'no-referrer',
            'x-frame-options': 'DENY',
          },
        );
      };

  Future<Response> _notFound(Request request) async {
    final path = request.url.path;
    if (path.startsWith('api/')) {
      throw const ApiError(404, 'not-found', 'Unbekannte Adresse.');
    }
    final app = web;
    if (app == null || request.method != 'GET') {
      return Response.notFound('Bociva-Server: keine Weboberfläche vorhanden.');
    }
    return app.serve(request, path);
  }

  String _clientIp(Request request) {
    final forwarded = request.headers['x-forwarded-for'];
    if (config.trustProxy) {
      if (forwarded != null && forwarded.isNotEmpty) {
        return forwarded.split(',').last.trim();
      }
    } else if (forwarded != null && !_warnedProxy) {
      _warnedProxy = true;
      stderr.writeln(
        'Hinweis: Anfragen kommen über einen Proxy, BOCIVA_TRUST_PROXY ist '
        'aber nicht gesetzt. Alle Anmeldesperren gelten dann für die Adresse '
        'des Proxys, also für alle gemeinsam.',
      );
    }
    final info =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return info?.remoteAddress.address ?? 'unknown';
  }

  Future<Map<String, Object?>> _body(
    Request request, {
    int maxBytes = _maxJsonBytes,
  }) async {
    const tooLarge = ApiError(413, 'too-large', 'Die Anfrage ist zu groß.');
    const tooSlow = ApiError(408, 'timeout', 'Die Anfrage kam zu langsam an.');
    final declared = request.contentLength;
    if (declared != null && declared > maxBytes) throw tooLarge;
    final bytes = BytesBuilder(copy: false);
    final deadline = DateTime.now().add(config.bodyTotalTimeout);
    try {
      await for (final chunk in request.read().timeout(
        config.bodyIdleTimeout,
      )) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw tooLarge;
        if (DateTime.now().isAfter(deadline)) throw tooSlow;
      }
    } on TimeoutException {
      throw tooSlow;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      // Unten als ungültig gemeldet.
    }
    throw const ApiError(400, 'bad-json', 'Ungültige Anfrage.');
  }

  String _string(Map<String, Object?> body, String key) {
    final v = body[key];
    if (v is! String) {
      throw const ApiError(400, 'bad-request', 'Ungültige Anfrage.');
    }
    return v;
  }

  String? _bearer(Request request) {
    final header = request.headers['authorization'];
    if (header == null || !header.startsWith('Bearer ')) return null;
    return header.substring(7);
  }

  User _requireUser(Request request) {
    final token = _bearer(request);
    final user = token == null ? null : accounts.authenticate(token);
    if (user == null) {
      throw const ApiError(401, 'unauthorized', 'Bitte erneut anmelden.');
    }
    return user;
  }

  Handler _user(Future<Response> Function(Request, User) inner) =>
      (request) => inner(request, _requireUser(request));

  Future<Response> _health(Request request) async => _json({
    'service': 'bociva',
    'version': version,
    'aiEnabled': ai != null,
    'setupRequired': accounts.setupRequired,
  });

  Response _authResponse(User user, String token) =>
      _json({'token': token, 'user': user.toJson()});

  Future<Response> _register(Request request) async {
    if (!_registerLimit.hit(_clientIp(request))) {
      throw const ApiError(
        429,
        'rate-limit',
        'Zu viele Versuche. Bitte später erneut versuchen.',
      );
    }
    final body = await _body(request, maxBytes: _maxAuthBytes);
    final (user, token) = await accounts.register(
      _string(body, 'username').trim(),
      _string(body, 'password'),
      _string(body, 'code'),
    );
    return _authResponse(user, token);
  }

  Future<Response> _login(Request request) async {
    final body = await _body(request, maxBytes: _maxAuthBytes);
    final username = _string(body, 'username').trim();
    final password = _string(body, 'password');
    // Zu lange Namen gibt es nicht; sie kämen sonst auch als Schlüssel in die
    // Anmeldesperre.
    if (username.length > Accounts.maxUsernameLength ||
        password.length > Accounts.maxPasswordLength) {
      throw const ApiError(
        401,
        'bad-login',
        'Name oder Passwort stimmt nicht.',
      );
    }
    final ip = _clientIp(request);
    final key = '$ip|${username.toLowerCase()}';
    if (!_loginIpLimit.hit(ip) || !_loginLimit.hit(key)) {
      throw const ApiError(
        429,
        'rate-limit',
        'Zu viele Versuche. Bitte in 15 Minuten erneut versuchen.',
      );
    }
    final result = await accounts.login(username, password);
    if (result == null) {
      throw const ApiError(
        401,
        'bad-login',
        'Name oder Passwort stimmt nicht.',
      );
    }
    _loginLimit.reset(key);
    return _authResponse(result.$1, result.$2);
  }

  Future<Response> _logout(Request request, User user) async {
    accounts.logout(_bearer(request)!);
    return _json({'ok': true});
  }

  Future<Response> _deleteAccount(Request request, User user) async {
    if (!_deleteLimit.hit(user.id)) {
      throw const ApiError(
        429,
        'rate-limit',
        'Zu viele Versuche. Bitte in 15 Minuten erneut versuchen.',
      );
    }
    final body = await _body(request, maxBytes: _maxAuthBytes);
    final password = _string(body, 'password');
    if (password.length > Accounts.maxPasswordLength ||
        !await accounts.checkPassword(user.id, password)) {
      throw const ApiError(403, 'bad-login', 'Das Passwort stimmt nicht.');
    }
    final result = accounts.deleteUser(user.id);
    if (result.promoted case final name?) {
      stdout.writeln('Konto „$name“ ist jetzt Administrator.');
    }
    if (result.setupCode case final code?) {
      stdout.writeln(
        'Kein Konto mehr vorhanden. Einrichtungscode für das erste Konto: '
        '$code',
      );
    }
    return _json({'ok': true});
  }

  Future<Response> _sync(Request request, User user) async {
    if (!_syncLimit.hit(user.id)) throw _tooFast;
    final body = await _body(request);
    final since = body['since'];
    final raw = body['changes'];
    if (since is! int || since < 0 || raw is! List) {
      throw const ApiError(400, 'bad-request', 'Ungültige Anfrage.');
    }
    if (raw.length > RecordService.maxChanges) {
      throw const ApiError(413, 'too-large', 'Zu viele Änderungen auf einmal.');
    }
    // Ungültige Datensätze werden einzeln abgewiesen. Lehnte der Server den
    // ganzen Stapel ab, schickte das Gerät ihn immer wieder.
    final changes = <SyncRecord>[];
    var rejected = 0;
    for (final item in raw) {
      final record = _validRecord(item);
      record == null ? rejected++ : changes.add(record);
    }
    return _json(
      records
          .sync(
            user.id,
            since,
            changes,
            DateTime.now().millisecondsSinceEpoch,
            rejected: rejected,
          )
          .toJson(),
    );
  }

  SyncRecord? _validRecord(Object? item) {
    if (item is! Map) return null;
    final SyncRecord record;
    try {
      record = SyncRecord.fromJson(item.cast<String, Object?>());
    } on TypeError {
      return null;
    }
    return recordProblem(record) == null ? record : null;
  }

  Future<Response> _export(Request request, User user) async => Response(
    200,
    body: records.export(user.id),
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  );

  Future<Response> _foodByBarcode(Request request, String code) async {
    final user = _requireUser(request);
    if (!isValidBarcode(code)) {
      throw const ApiError(400, 'bad-barcode', 'Ungültiger Strichcode.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = db.select(
      'SELECT json, fetched_at FROM food_cache WHERE barcode = ?',
      [code],
    );
    if (cached.isNotEmpty) {
      final json = cached.first['json'] as String?;
      final age = now - (cached.first['fetched_at'] as int);
      if (age < (json == null ? _foodMissCacheMs : foodCacheMs)) {
        if (json == null) throw _foodNotFound;
        return _json({'food': jsonDecode(json)});
      }
    }
    if (!_foodLimit.hit(user.id)) throw _tooFast;
    final result = await food.byBarcode(code);
    db.execute('INSERT OR REPLACE INTO food_cache VALUES (?, ?, ?)', [
      code,
      result == null ? null : jsonEncode(result.toJson()),
      now,
    ]);
    if (result == null) throw _foodNotFound;
    return _json({'food': result.toJson()});
  }

  static const _foodNotFound = ApiError(
    404,
    'food-not-found',
    'Dieses Produkt ist nicht in der Datenbank.',
  );

  static const _tooFast = ApiError(
    429,
    'rate-limit',
    'Zu viele Anfragen. Bitte gleich noch einmal versuchen.',
  );

  Future<Response> _foodSearch(Request request, User user) async {
    final q = (request.url.queryParameters['q'] ?? '').trim();
    if (q.length < 2 || q.length > 100) {
      return _json({'foods': const []});
    }
    if (!_foodSearchLimit.hit('all')) throw _tooFast;
    final foods = await food.search(q);
    return _json({
      'foods': [for (final f in foods) f.toJson()],
    });
  }

  AiBackend _requireAi(User user) {
    final backend = ai;
    if (backend == null) {
      throw const ApiError(
        503,
        'ai-disabled',
        'Auf diesem Server ist keine KI eingerichtet.',
      );
    }
    if (!_aiLimit.hit(user.id)) throw _tooFast;
    if (!_aiBudget.hit('all')) {
      throw const ApiError(
        429,
        'ai-budget',
        'Das tägliche Kontingent für KI-Anfragen auf diesem Server ist '
            'aufgebraucht. Morgen geht es weiter.',
      );
    }
    return backend;
  }

  Future<Response> _aiAnalyze(Request request, User user) async {
    final backend = _requireAi(user);
    final body = await _body(request);
    final text = body['text'];
    final mime = body['imageMime'];
    final encoded = body['image'];
    Uint8List? image;
    if (encoded is String) {
      try {
        image = base64Decode(encoded);
      } on FormatException {
        throw const ApiError(400, 'bad-image', 'Das Bild ist ungültig.');
      }
      if (image.length > _maxImageBytes) {
        throw const ApiError(413, 'too-large', 'Das Bild ist zu groß.');
      }
    }
    const allowedMime = {'image/jpeg', 'image/png', 'image/webp'};
    final result = await _aiGate.run(
      () => backend.analyzeMeal(
        text: text is String && text.length <= 2000 ? text : null,
        image: image,
        imageMime: allowedMime.contains(mime) ? mime as String : 'image/jpeg',
      ),
    );
    return _json(result.toJson());
  }

  Future<Response> _aiReview(Request request, User user) async {
    final backend = _requireAi(user);
    final body = await _body(request, maxBytes: 64 * 1024);
    final stats = reviewStats(body['stats']);
    if (stats == null) {
      throw const ApiError(400, 'bad-request', 'Ungültige Anfrage.');
    }
    return _json({
      'text': await _aiGate.run(() => backend.reviewNutrition(stats)),
    });
  }

  Future<Response> _createInvite(Request request, User user) async {
    if (!user.isAdmin) {
      throw const ApiError(403, 'forbidden', 'Nur für Administratoren.');
    }
    return _json({'code': accounts.createInvite()});
  }
}

/// Nur Zahlen in der Form, die die App schickt. Freier Text ginge sonst als
/// beliebige Aufgabe an das Modell, auf Kosten des Servers.
Map<String, Object?>? reviewStats(Object? raw) {
  const goalKeys = {'zielKcal', 'zielEiweissG', 'zielWasserMl'};
  const dayKeys = {
    'kcal',
    'eiweissG',
    'kohlenhydrateG',
    'fettG',
    'wasserMl',
    'verbranntKcal',
  };
  bool isNumber(Object? v) => v is num && v.isFinite && v.abs() < 1e6;
  if (raw is! Map) return null;
  final days = raw['tage'];
  if (days is! List || days.isEmpty || days.length > 31) return null;
  for (final entry in raw.entries) {
    if (entry.key == 'tage') continue;
    if (!goalKeys.contains(entry.key) || !isNumber(entry.value)) return null;
  }
  for (final day in days) {
    if (day is! Map || day.isEmpty) return null;
    for (final entry in day.entries) {
      if (!dayKeys.contains(entry.key) || !isNumber(entry.value)) return null;
    }
  }
  return raw.cast<String, Object?>();
}
