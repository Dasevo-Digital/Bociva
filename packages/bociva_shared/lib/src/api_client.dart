import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai.dart';
import 'models.dart';
import 'open_food_facts.dart';
import 'store.dart';
import 'sync.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code, message;

  bool get isAuth => status == 401;

  @override
  String toString() => message;
}

class ServerInfo {
  const ServerInfo({
    required this.version,
    required this.aiEnabled,
    required this.setupRequired,
  });

  final String version;
  final bool aiEnabled, setupRequired;
}

class AuthResult {
  const AuthResult({
    required this.token,
    required this.username,
    required this.userId,
    required this.isAdmin,
  });

  final String token, username, userId;
  final bool isAdmin;
}

/// Client für den Bociva-Server, von App und Web gemeinsam genutzt.
class ApiClient implements SyncTransport, FoodLookup, AiBackend {
  ApiClient(this.base, {this.token, http.Client? client})
    : _client = client ?? http.Client();

  final Uri base;
  String? token;
  final http.Client _client;

  Uri _uri(String path, [Map<String, String>? query]) =>
      base.replace(path: '${base.path}/$path', queryParameters: query);

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final request = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on ApiException {
      rethrow;
    } on Exception {
      throw const ApiException(
        0,
        'network',
        'Der Server ist nicht erreichbar.',
      );
    }
    Map<String, Object?> json = const {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map) json = decoded.cast<String, Object?>();
    } on FormatException {
      // Ein Proxy davor antwortet womöglich mit HTML.
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        '${json['error'] ?? 'error'}',
        '${json['message'] ?? 'Der Server meldet Fehler ${res.statusCode}.'}',
      );
    }
    return json;
  }

  Future<ServerInfo> info() async {
    final j = await _send('GET', 'api/health');
    if (j['service'] != 'bociva') {
      throw const ApiException(
        0,
        'not-bociva',
        'Unter dieser Adresse läuft kein Bociva-Server.',
      );
    }
    return ServerInfo(
      version: '${j['version']}',
      aiEnabled: j['aiEnabled'] == true,
      setupRequired: j['setupRequired'] == true,
    );
  }

  AuthResult _auth(Map<String, Object?> j) {
    final user = (j['user'] as Map).cast<String, Object?>();
    token = j['token'] as String;
    return AuthResult(
      token: token!,
      username: '${user['username']}',
      userId: '${user['id']}',
      isAdmin: user['isAdmin'] == true,
    );
  }

  Future<AuthResult> login(String username, String password) async => _auth(
    await _send(
      'POST',
      'api/auth/login',
      body: {'username': username, 'password': password},
    ),
  );

  Future<AuthResult> register(
    String username,
    String password,
    String code,
  ) async => _auth(
    await _send(
      'POST',
      'api/auth/register',
      body: {'username': username, 'password': password, 'code': code},
    ),
  );

  Future<void> logout() async {
    await _send('POST', 'api/auth/logout');
    token = null;
  }

  Future<void> deleteAccount(String password) =>
      _send('DELETE', 'api/account', body: {'password': password});

  Future<String> createInvite() async =>
      '${(await _send('POST', 'api/admin/invites'))['code']}';

  Future<Map<String, Object?>> export() => _send('GET', 'api/export');

  @override
  Future<SyncResponse> exchange(int since, List<SyncRecord> changes) async =>
      SyncResponse.fromJson(
        await _send(
          'POST',
          'api/sync',
          body: {
            'since': since,
            'changes': [for (final c in changes) c.toJson()],
          },
          timeout: const Duration(seconds: 60),
        ),
      );

  @override
  Future<Food?> byBarcode(String barcode) async {
    try {
      final j = await _send('GET', 'api/foods/barcode/$barcode');
      return Food.fromJson((j['food'] as Map).cast<String, Object?>());
    } on ApiException catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<Food>> search(String query) async {
    final j = await _send('GET', 'api/foods/search', query: {'q': query});
    return [
      for (final f in j['foods'] as List)
        Food.fromJson((f as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<MealAnalysis> analyzeMeal({
    String? text,
    Uint8List? image,
    String? imageMime,
  }) async => MealAnalysis.fromJson(
    await _send(
      'POST',
      'api/ai/analyze',
      body: {
        'text': ?text,
        if (image != null) 'image': base64Encode(image),
        'imageMime': ?imageMime,
      },
      timeout: const Duration(seconds: 200),
    ),
  );

  @override
  Future<String> reviewNutrition(Map<String, Object?> stats) async =>
      '${(await _send('POST', 'api/ai/review', body: {'stats': stats}, timeout: const Duration(seconds: 200)))['text']}';
}
