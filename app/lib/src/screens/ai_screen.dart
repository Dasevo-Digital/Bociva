import 'dart:typed_data';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../controller.dart';
import '../format.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key, required this.meal});
  final Meal meal;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _Draft {
  _Draft(this.item) : amount = TextEditingController(text: fmtOne(item.amount));
  final AiFoodItem item;
  final TextEditingController amount;
  bool selected = true;
}

class _AiScreenState extends State<AiScreen> {
  final _text = TextEditingController();
  Uint8List? _image;
  String? _mime, _note, _error;
  bool _busy = false;
  List<_Draft> _drafts = const [];

  @override
  void dispose() {
    _text.dispose();
    for (final d in _drafts) {
      d.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      // Reicht zum Erkennen und schont Leitung und lokale Modelle.
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _image = bytes;
      _mime = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _analyze() async {
    final backend = context.app.ai;
    if (backend == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _drafts = const [];
      _note = null;
    });
    try {
      final result = await backend.analyzeMeal(
        text: _text.text,
        image: _image,
        imageMime: _mime,
      );
      if (!mounted) return;
      setState(() {
        _note = result.note;
        _drafts = [for (final i in result.items) _Draft(i)];
        if (_drafts.isEmpty) _error = result.note ?? 'Kein Essen erkannt.';
      });
    } on Exception catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final app = context.app;
    final navigator = Navigator.of(context);
    for (final d in _drafts.where((d) => d.selected)) {
      final amount = parseNumber(d.amount.text);
      if (amount == null || amount <= 0 || amount > 10000) continue;
      await app.logFood(d.item.toFood(), widget.meal, amount);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final destination = app.aiDestination;
    return Scaffold(
      appBar: AppBar(title: const Text('KI-Analyse')),
      body: destination == null
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Es ist noch keine KI eingerichtet. Unter „Mehr → KI-Analyse“ '
                'kannst du einen selbst gehosteten oder beliebigen anderen '
                'Dienst eintragen. Alle anderen Funktionen arbeiten auch ohne.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: const Key('ai-text'),
                  controller: _text,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText:
                        'Was gab es? Zum Beispiel: Zwei Scheiben Vollkornbrot '
                        'mit Käse und ein Apfel',
                  ),
                ),
                const SizedBox(height: 8),
                if (_image != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(
                        _image!,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('Foto'),
                      onPressed: () => _pick(ImageSource.camera),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Mediathek'),
                      onPressed: () => _pick(ImageSource.gallery),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  app.aiMode == AiMode.server
                      ? 'Text und Foto gehen an deinen Bociva-Server ($destination) '
                            'und von dort an den dort eingerichteten KI-Dienst.'
                      : 'Text und Foto werden an $destination gesendet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('ai-analyze'),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Analysieren'),
                  onPressed: _busy ? null : _analyze,
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!),
                  ),
                if (_drafts.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Das sind Schätzungen. Bitte Mengen prüfen.',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (_note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_note!),
                    ),
                  const SizedBox(height: 8),
                  for (final d in _drafts)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: CheckboxListTile(
                        value: d.selected,
                        onChanged: (v) => setState(() => d.selected = v!),
                        title: Text(d.item.name),
                        subtitle: Row(
                          children: [
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: d.amount,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  suffixText: d.item.unit,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text('${fmtInt(_kcal(d))} kcal'),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('ai-save'),
                    onPressed: _drafts.any((d) => d.selected) ? _save : null,
                    child: Text('Zu ${widget.meal.label} hinzufügen'),
                  ),
                ],
              ],
            ),
    );
  }

  double _kcal(_Draft d) {
    final amount = parseNumber(d.amount.text) ?? 0;
    final base = d.item.amount > 0 ? d.item.amount : 100;
    return d.item.nutrients.kcal * amount / base;
  }
}
