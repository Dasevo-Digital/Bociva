class ServerUrlException implements Exception {
  const ServerUrlException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Prüft eine eingegebene Serveradresse und bringt sie in eine feste Form.
/// Unverschlüsseltes HTTP ist nur im eigenen Netz erlaubt, weil Zugangsdaten
/// und Gesundheitsdaten sonst lesbar durchs Internet gingen.
Uri normalizeServerUrl(String input) {
  var text = input.trim();
  if (text.isEmpty) {
    throw const ServerUrlException('Bitte eine Serveradresse eingeben.');
  }
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw const ServerUrlException('Das ist keine gültige Adresse.');
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw const ServerUrlException('Die Adresse muss mit https:// beginnen.');
  }
  if (uri.userInfo.isNotEmpty) {
    throw const ServerUrlException(
      'Zugangsdaten gehören nicht in die Adresse.',
    );
  }
  if (uri.scheme == 'http' && !isLocalHost(uri.host)) {
    throw const ServerUrlException(
      'Unverschlüsseltes HTTP geht nur im eigenen Netz. Bitte https:// '
      'verwenden.',
    );
  }
  var path = uri.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(path: path, query: null, fragment: null);
}

/// Loopback, private IPv4-Bereiche und `.local`-Namen.
bool isLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local') || h == '::1') return true;
  final parts = h.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) {
    return false;
  }
  final a = parts[0]!, b = parts[1]!;
  return a == 127 ||
      a == 10 ||
      (a == 192 && b == 168) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 169 && b == 254);
}
