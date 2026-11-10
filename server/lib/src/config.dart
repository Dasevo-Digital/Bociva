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
    this.aiDailyLimit = 500,
    this.userQuotaMb = 200,
    this.bodyIdleTimeout = const Duration(seconds: 30),
    this.bodyTotalTimeout = const Duration(seconds: 120),
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
      aiDailyLimit: int.tryParse(env['BOCIVA_AI_DAILY_LIMIT'] ?? '') ?? 500,
      userQuotaMb: int.tryParse(env['BOCIVA_USER_QUOTA_MB'] ?? '') ?? 200,
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

  /// KI-Anfragen pro Tag für alle Konten zusammen; jede kostet Rechenzeit
  /// oder Geld beim Anbieter.
  final int aiDailyLimit;

  /// Speicherplatz pro Konto in MB.
  final int userQuotaMb;

  /// Wie lange ein Request-Body ins Stocken geraten bzw. insgesamt dauern
  /// darf. Sonst hielten halbe Anfragen Verbindungen unbegrenzt offen.
  final Duration bodyIdleTimeout, bodyTotalTimeout;
}
