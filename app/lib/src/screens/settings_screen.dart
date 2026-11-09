import 'dart:convert';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../format.dart';
import '../platform/health_bridge.dart';
import 'connect_screen.dart';
import 'profile_form.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('Mehr')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _Section('Profil', [
            ListTile(
              key: const Key('open-profile'),
              leading: const Icon(Icons.person_outline),
              title: const Text('Profil und Ziele'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _ProfileScreen()),
              ),
            ),
          ]),
          const _ServerSection(),
          _Section('KI-Analyse', [
            ListTile(
              key: const Key('open-ai-settings'),
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Dienst einrichten'),
              subtitle: Text(switch (app.aiDestination) {
                null => 'Aus',
                final host => 'Aktiv: $host',
              }),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const _AiSettings()),
              ),
            ),
          ]),
          const _HealthSection(),
          const _DataSection(),
          _Section('Über', [
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Produktdaten'),
              subtitle: Text(
                'Strichcodes und Produktsuche nutzen Open Food Facts, '
                'lizenziert unter der Open Database License (ODbL).',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Lizenzen'),
              onTap: () =>
                  showLicensePage(context: context, applicationName: 'Bociva'),
            ),
            const ListTile(
              leading: Icon(Icons.health_and_safety_outlined),
              title: Text('Hinweis'),
              subtitle: Text(
                'Bociva ersetzt keine medizinische Beratung. Berechnete Ziele '
                'und KI-Schätzungen sind Richtwerte.',
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall!
                .copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    ),
  );
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil und Ziele')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ProfileForm(
            initial: app.profile,
            submitLabel: 'Speichern',
            onSaved: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ServerSection extends StatelessWidget {
  const _ServerSection();

  Future<void> _invite(BuildContext context, AppController app) async {
    try {
      final code = await app.createInvite();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Einladung'),
          content: SelectableText(
            'Einladungscode, 7 Tage und einmal gültig:\n\n$code',
            key: const Key('invite-code'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
              },
              child: const Text('Kopieren'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<void> _deleteAccount(BuildContext context, AppController app) async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konto löschen?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Das Konto und alle Daten auf dem Server werden endgültig '
              'gelöscht. Das lässt sich nicht rückgängig machen.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Endgültig löschen'),
          ),
        ],
      ),
    );
    if (password == null || password.isEmpty) return;
    try {
      await app.deleteAccount(password);
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.isConnected) {
      return _Section('Server', [
        ListTile(
          key: const Key('open-connect'),
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Mit eigenem Server verbinden'),
          subtitle: const Text('Abgleich zwischen Geräten und Weboberfläche'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ConnectScreen(webMode: false),
            ),
          ),
        ),
      ]);
    }
    final last = app.lastSync;
    return _Section('Server', [
      ListTile(
        leading: const Icon(Icons.dns_outlined),
        title: Text('${app.username}'),
        subtitle: Text(
          app.syncError ??
              (last == null
                  ? app.serverUrl ?? ''
                  : 'Abgeglichen um ${DateFormat.Hm('de').format(last)}'),
        ),
        trailing: IconButton(
          key: const Key('sync-now'),
          tooltip: 'Jetzt abgleichen',
          icon: app.syncing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          onPressed: app.syncNow,
        ),
      ),
      if (app.needsLogin && !kIsWeb)
        ListTile(
          leading: const Icon(Icons.login),
          title: const Text('Erneut anmelden'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ConnectScreen(webMode: false),
            ),
          ),
        ),
      if (app.isAdmin)
        ListTile(
          key: const Key('create-invite'),
          leading: const Icon(Icons.person_add_alt),
          title: const Text('Einladung erstellen'),
          onTap: () => _invite(context, app),
        ),
      ListTile(
        key: const Key('logout'),
        leading: const Icon(Icons.logout),
        title: const Text('Abmelden'),
        subtitle: kIsWeb
            ? null
            : const Text('Die Daten bleiben auf diesem Gerät.'),
        onTap: app.disconnect,
      ),
      ListTile(
        leading: const Icon(Icons.delete_forever_outlined),
        title: const Text('Konto löschen'),
        onTap: () => _deleteAccount(context, app),
      ),
    ]);
  }
}

class _AiSettings extends StatefulWidget {
  const _AiSettings();

  @override
  State<_AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<_AiSettings> {
  late AiMode _mode;
  late final TextEditingController _url, _model, _key;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = ControllerScope.of(context);
    _mode = app.aiMode;
    _url = TextEditingController(text: app.customAi?.baseUrl);
    _model = TextEditingController(text: app.customAi?.model);
    _key = TextEditingController(text: app.customAi?.apiKey);
  }

  @override
  void dispose() {
    for (final c in [_url, _model, _key]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.app;
    final navigator = Navigator.of(context);
    AiConfig? config;
    if (_mode == AiMode.custom) {
      if (_model.text.trim().isEmpty) {
        setState(() => _error = 'Bitte einen Modellnamen eingeben.');
        return;
      }
      try {
        config = AiConfig(
          baseUrl: normalizeServerUrl(_url.text).toString(),
          model: _model.text.trim(),
          apiKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
        );
      } on ServerUrlException catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }
    await app.setAi(_mode, config);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('KI-Analyse')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Fotos und Beschreibungen werden nur an den hier gewählten Dienst '
            'gesendet. Für Fotos braucht das Modell Bildverständnis.',
          ),
          gap,
          RadioGroup<AiMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v!),
            child: Column(
              children: [
                const RadioListTile(
                  key: Key('ai-off'),
                  value: AiMode.off,
                  title: Text('Aus'),
                ),
                RadioListTile(
                  key: const Key('ai-server'),
                  value: AiMode.server,
                  enabled: app.isConnected && app.serverAi,
                  title: const Text('Über meinen Bociva-Server'),
                  subtitle: Text(
                    app.isConnected
                        ? (app.serverAi
                              ? 'Vom Server eingerichtet'
                              : 'Auf dem Server ist keine KI eingerichtet')
                        : 'Nicht mit einem Server verbunden',
                  ),
                ),
                if (!kIsWeb)
                  const RadioListTile(
                    key: Key('ai-custom'),
                    value: AiMode.custom,
                    title: Text('Eigener Dienst'),
                    subtitle: Text('Selbst gehostet oder beliebige API'),
                  ),
              ],
            ),
          ),
          if (_mode == AiMode.custom) ...[
            gap,
            TextField(
              key: const Key('ai-url'),
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Basisadresse',
                hintText: 'http://localhost:11434/v1',
                helperText: 'Dienst mit Chat-Completions-Schnittstelle',
              ),
            ),
            gap,
            TextField(
              key: const Key('ai-model'),
              controller: _model,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Modell'),
            ),
            gap,
            TextField(
              key: const Key('ai-key'),
              controller: _key,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API-Schlüssel (optional)',
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          gap,
          FilledButton(
            key: const Key('ai-settings-save'),
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}

class _HealthSection extends StatelessWidget {
  const _HealthSection();

  Future<void> _toggle(
    BuildContext context,
    AppController app, {
    required bool enabled,
    required bool write,
  }) async {
    try {
      await app.setHealth(enabled: enabled, write: write);
    } on HealthUnavailable catch (e) {
      if (!context.mounted) return;
      showMessage(context, e);
      if (e.canInstall) await app.health.installProvider();
    } on Exception catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<void> _importFit(BuildContext context, AppController app) async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    final Uint8List bytes = await picked.first.readAsBytes();
    if (!context.mounted) return;
    try {
      final count = await app.importFit(bytes);
      if (context.mounted) {
        showMessage(
          context,
          '$count ${count == 1 ? 'Aktivität' : 'Aktivitäten'} importiert.',
        );
      }
    } on FitFormatException catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final health = app.health;
    return _Section('Aktivität', [
      if (health.supported) ...[
        SwitchListTile(
          secondary: const Icon(Icons.favorite_outline),
          title: Text('${health.platformName} verbinden'),
          subtitle: const Text(
            'Liest Schritte, aktive Kalorien und Gewicht. Garmin-Daten kommen '
            'über Garmin Connect hierher, wenn du sie dort freigibst.',
          ),
          value: app.healthEnabled,
          onChanged: (v) =>
              _toggle(context, app, enabled: v, write: app.healthWrite),
        ),
        if (app.healthEnabled)
          SwitchListTile(
            secondary: const Icon(Icons.upload_outlined),
            title: const Text('Mahlzeiten und Wasser dorthin schreiben'),
            value: app.healthWrite,
            onChanged: (v) => _toggle(context, app, enabled: true, write: v),
          ),
      ],
      ListTile(
        key: const Key('import-fit'),
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('FIT-Datei importieren'),
        subtitle: const Text('Aktivität aus Garmin Connect als .fit oder .zip'),
        onTap: () => _importFit(context, app),
      ),
    ]);
  }
}

class _DataSection extends StatelessWidget {
  const _DataSection();

  Future<void> _export(BuildContext context, AppController app) async {
    try {
      final data = await app.exportData();
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
      );
      await FilePicker.saveFile(fileName: 'bociva-export.json', bytes: bytes);
    } on Exception catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<void> _wipe(BuildContext context, AppController app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Daten auf diesem Gerät löschen?'),
        content: const Text(
          'Tagebuch, Ziele und Einstellungen werden von diesem Gerät entfernt. '
          'Ein Server-Konto bleibt bestehen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok == true) await app.wipeDevice();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return _Section('Daten', [
      ListTile(
        key: const Key('export'),
        leading: const Icon(Icons.download_outlined),
        title: const Text('Alle Daten exportieren'),
        subtitle: const Text('Als JSON-Datei'),
        onTap: () => _export(context, app),
      ),
      if (!kIsWeb)
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Alle Daten auf diesem Gerät löschen'),
          onTap: () => _wipe(context, app),
        ),
    ]);
  }
}
