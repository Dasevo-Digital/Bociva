import 'package:bociva_shared/bociva_shared.dart';

class ServerConfig {
  const ServerConfig({
    required this.dataDir,
    this.host = '0.0.0.0',
    this.port = 8770,
    this.keyFile,
    this.webDir,
    this.ai,
    this.trustProxy = false,
    this.foodContact,
    this.inMemory = false,
  });

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final dataDir = env['BOCIVA_DATA_DIR'] ?? 'data';
    final aiUrl = env['BOCIVA_AI_BASE_URL'];
    final aiModel = env['BOCIVA_AI_MODEL'];
    return ServerConfig(
      dataDir: dataDir,
      host: env['BOCIVA_HOST'] ?? '0.0.0.0',
      port: int.tryParse(env['BOCIVA_PORT'] ?? '') ?? 8770,
      keyFile: env['BOCIVA_KEY_FILE'] ?? '$dataDir/bociva.key',
      webDir: env['BOCIVA_WEB_DIR'],
      trustProxy: env['BOCIVA_TRUST_PROXY'] == 'true',
      foodContact: env['BOCIVA_FOOD_CONTACT'],
      ai: aiUrl != null && aiModel != null
          ? AiConfig(
              baseUrl: aiUrl,
              model: aiModel,
              apiKey: env['BOCIVA_AI_API_KEY'],
            )
          : null,
    );
  }

  final String dataDir, host;
  final int port;
  final String? keyFile, webDir, foodContact;
  final AiConfig? ai;

  /// Nur hinter einem Reverse Proxy: dann ist X-Forwarded-For vertrauenswürdig.
  final bool trustProxy;

  /// Für Tests.
  final bool inMemory;
}
