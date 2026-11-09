import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

/// Liefert die Flutter-Web-App aus. Der Browser spricht nur mit diesem Server.
class WebApp {
  WebApp(String dir) : dir = p.normalize(p.absolute(dir));

  final String dir;

  static WebApp? locate(String? configured) {
    final candidates = [
      ?configured,
      p.join(p.dirname(p.dirname(Platform.resolvedExecutable)), 'web'),
      'web',
    ];
    for (final dir in candidates) {
      if (File(p.join(dir, 'index.html')).existsSync()) return WebApp(dir);
    }
    return null;
  }

  static const policy =
      "default-src 'self'; "
      "script-src 'self' 'wasm-unsafe-eval'; "
      "style-src 'self' 'unsafe-inline'; "
      "img-src 'self' data: blob:; "
      "font-src 'self' data:; "
      "connect-src 'self'; "
      "worker-src 'self' blob:; "
      "object-src 'none'; base-uri 'self'; "
      "frame-ancestors 'none'";

  static const _types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'text/javascript; charset=utf-8',
    '.mjs': 'text/javascript; charset=utf-8',
    '.json': 'application/json',
    '.wasm': 'application/wasm',
    '.css': 'text/css; charset=utf-8',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff2': 'font/woff2',
    '.bin': 'application/octet-stream',
    '.frag': 'application/octet-stream',
  };

  Future<Response> serve(Request request, String path) async {
    final relative = path.isEmpty ? 'index.html' : path;
    final file = p.normalize(p.join(dir, relative));
    if (!p.isWithin(dir, file)) return Response.notFound('Not found');
    final type = _types[p.extension(file).toLowerCase()];
    final plain = File(file);
    if (type == null || !await plain.exists()) {
      return Response.notFound('Not found');
    }
    final stat = await plain.stat();
    final etag =
        '"${stat.size.toRadixString(36)}-'
        '${stat.modified.millisecondsSinceEpoch.toRadixString(36)}"';
    final headers = {
      'content-type': type,
      'cache-control': 'no-cache',
      'etag': etag,
      'vary': 'accept-encoding',
      if (relative == 'index.html') 'content-security-policy': policy,
    };
    final match = request.headers['if-none-match'];
    if (match != null && match.split(',').any((t) => t.trim() == etag)) {
      return Response.notModified(headers: headers);
    }
    final accepted = {
      for (final part in (request.headers['accept-encoding'] ?? '').split(','))
        part.split(';').first.trim(),
    };
    var send = plain;
    String? encoding;
    for (final (name, suffix) in const [('br', '.br'), ('gzip', '.gz')]) {
      final packed = File('$file$suffix');
      if (accepted.contains(name) && await packed.exists()) {
        send = packed;
        encoding = name;
        break;
      }
    }
    return Response.ok(
      send.openRead(),
      headers: {
        ...headers,
        'content-encoding': ?encoding,
        'content-length': '${await send.length()}',
      },
    );
  }
}
