import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/brand.dart';

/// Anmeldung am Bociva-Server. Im Browser ist es immer der ausliefernde
/// Server, in der App wird die Adresse eingegeben.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.webMode});
  final bool webMode;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _register = false, _keepLocal = true, _busy = false, _setup = false;
  int _local = 0, _pending = 0;
  String? _error;

  /// Konto, zu dem die Daten auf diesem Gerät gehören.
  late final String? _previous = context.appRead.previousAccount;

  @override
  void initState() {
    super.initState();
    // Daten eines anderen Kontos nur auf ausdrücklichen Wunsch übernehmen.
    _keepLocal = _previous == null;
    if (widget.webMode) _detectSetup();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.appRead;
      final count = await app.localRecordCount();
      final pending = await app.pendingChanges();
      if (mounted) {
        setState(() {
          _local = count;
          _pending = pending;
        });
      }
    });
  }

  Future<void> _detectSetup() async {
    try {
      final info = await ApiClient(_webBase).info();
      if (mounted && info.setupRequired) {
        setState(() {
          _setup = true;
          _register = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Uri get _webBase => Uri.parse(Uri.base.origin);

  String? get _keepHint => switch ((_previous, _keepLocal)) {
    (null, true) => null,
    (null, false) =>
      'Die Einträge auf diesem Gerät werden gelöscht und durch die des '
          'Kontos ersetzt.',
    (_, true) =>
      'Nur wählen, wenn diese Daten dir gehören. Sie werden mit dem Konto '
          'zusammengeführt.',
    (_, false) =>
      'Bei demselben Konto bleibt alles erhalten. Bei einem anderen werden '
          'die Einträge dieses Geräts durch die des Kontos ersetzt.',
  };

  @override
  void dispose() {
    for (final c in [_url, _name, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final app = context.app;
    try {
      await app.connect(
        url: widget.webMode ? _webBase : normalizeServerUrl(_url.text),
        name: _name.text.trim(),
        password: _password.text,
        registerCode: _register ? _code.text : null,
        keepLocal: _keepLocal,
      );
      if (!widget.webMode && navigator.canPop()) navigator.pop();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: AutofillGroup(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.webMode) ...[
              const Mascot(height: 150),
              gap,
              const Center(child: BrandWordmark(width: 180)),
              const SizedBox(height: 24),
            ],
            if (_setup)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Dieser Server hat noch kein Konto. Lege das erste an; es '
                  'wird Administrator. Den Einrichtungscode findest du im '
                  'Serverprotokoll.',
                ),
              ),
            if (!widget.webMode) ...[
              TextField(
                key: const Key('connect-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Serveradresse',
                  hintText: 'https://bociva.example.org',
                ),
              ),
              gap,
            ],
            TextField(
              key: const Key('connect-name'),
              controller: _name,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            gap,
            TextField(
              key: const Key('connect-password'),
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: const InputDecoration(labelText: 'Passwort'),
              onSubmitted: (_) => _submit(),
            ),
            if (_register) ...[
              gap,
              TextField(
                key: const Key('connect-code'),
                controller: _code,
                autocorrect: false,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: _setup ? 'Einrichtungscode' : 'Einladungscode',
                ),
              ),
            ],
            if (!_setup)
              SwitchListTile(
                key: const Key('connect-register'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Neues Konto mit Einladung'),
                value: _register,
                onChanged: (v) => setState(() => _register = v),
              ),
            if (widget.webMode && _pending > 0)
              Padding(
                key: const Key('connect-pending'),
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '$_pending ${_pending == 1 ? 'Änderung ist' : 'Änderungen sind'} '
                  'noch nicht auf dem Server. Melde dich mit demselben Konto '
                  'wieder an, damit nichts verloren geht.',
                ),
              ),
            if (!kIsWeb && _local > 0)
              CheckboxListTile(
                key: const Key('connect-keep-local'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _previous == null
                      ? 'Daten dieses Geräts ins Konto übernehmen'
                      : 'Daten von $_previous in dieses Konto übernehmen',
                ),
                subtitle: _keepHint == null ? null : Text(_keepHint!),
                value: _keepLocal,
                onChanged: (v) => setState(() => _keepLocal = v!),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            gap,
            FilledButton(
              key: const Key('connect-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_register ? 'Konto anlegen' : 'Anmelden'),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: widget.webMode ? null : AppBar(title: const Text('Server')),
      body: Center(child: form),
    );
  }
}
