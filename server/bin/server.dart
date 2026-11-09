import 'dart:ffi';
import 'dart:io';

import 'package:bociva_server/bociva_server.dart';
import 'package:http/http.dart' as http;

/// Alles, was der Server anlegt, ist nur für seinen eigenen Benutzer lesbar
/// (umask 077). Im Docker-Image gibt es dafür kein chmod.
void _restrictNewFiles() {
  if (Platform.isWindows) return;
  try {
    DynamicLibrary.process()
        .lookupFunction<Uint32 Function(Uint32), int Function(int)>('umask')(
      0x3f,
    );
  } on Object catch (e) {
    stderr.writeln('umask ließ sich nicht setzen: $e');
  }
}

Future<void> main(List<String> args) async {
  _restrictNewFiles();
  final config = ServerConfig.fromEnvironment(Platform.environment);
  if (args.contains('--healthcheck')) {
    exit(await _healthy(config.port) ? 0 : 1);
  }
  final server = await BocivaServer.start(config);
  stdout.writeln(
    'Bociva-Server läuft auf ${config.host}:${server.port} '
    '(KI: ${config.ai == null ? 'aus' : 'an'})',
  );
  if (server.setupCode case final code?) {
    stdout.writeln(
      'Noch kein Konto vorhanden. Einrichtungscode für das erste Konto: $code',
    );
  }
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await server.close();
      exit(0);
    });
  }
}

Future<bool> _healthy(int port) async {
  try {
    final res = await http
        .get(Uri.parse('http://127.0.0.1:$port/api/health'))
        .timeout(const Duration(seconds: 4));
    return res.statusCode == 200;
  } on Exception {
    return false;
  }
}
