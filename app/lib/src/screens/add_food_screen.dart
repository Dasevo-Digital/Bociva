import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import 'ai_screen.dart';
import 'custom_food_screen.dart';
import 'food_amount_sheet.dart';
import 'scanner_screen.dart';

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.meal});

  /// Zum Auswählen einer Rezeptzutat `null`: Dann wird nichts eingetragen und
  /// die Auswahl als [RecipeIngredient] zurückgegeben.
  final Meal? meal;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _query = TextEditingController();
  List<Food> _local = const [],
      _online = const [],
      _recent = const [],
      _recipes = const [];
  bool _searching = false;
  String? _onlineError;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final repo = context.appRead.repo;
    final recent = await repo.recentFoods();
    final recipes = [for (final r in await repo.recipes()) r.toFood()];
    if (mounted) {
      setState(() {
        _recent = recent;
        _recipes = recipes;
      });
    }
  }

  Future<void> _onChanged(String text) async {
    final local = await context.app.repo.searchLocal(text);
    if (mounted && _query.text == text) {
      setState(() {
        _local = local;
        _online = const [];
        _onlineError = null;
      });
    }
  }

  /// Open Food Facts lässt nur wenige Suchen pro Minute zu, deshalb erst auf
  /// ausdrücklichen Wunsch und nicht bei jedem Tastendruck.
  Future<void> _searchOnline() async {
    final text = _query.text.trim();
    if (text.length < 2) return;
    setState(() {
      _searching = true;
      _onlineError = null;
    });
    try {
      final results = await context.app.foodLookup.search(text);
      if (mounted) setState(() => _online = results);
    } on Exception catch (e) {
      if (mounted) setState(() => _onlineError = '$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  bool get _picking => widget.meal == null;

  Future<void> _open(Food food) async {
    if (_picking) {
      final navigator = Navigator.of(context);
      double? chosen;
      await showFoodAmountSheet(
        context,
        food,
        null,
        onConfirm: (amount) => chosen = amount,
        actionLabel: 'Zum Rezept hinzufügen',
      );
      if (chosen != null) {
        navigator.pop(RecipeIngredient.fromFood(food, chosen!));
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final added = await showFoodAmountSheet(context, food, widget.meal);
    if (added == true) {
      await _loadRecent();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${food.name} eingetragen')));
    }
  }

  Future<String?> _askBarcode() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Strichcode eingeben'),
        content: TextField(
          key: const Key('barcode-field'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'EAN / GTIN'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('barcode-submit'),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Suchen'),
          ),
        ],
      ),
    );
  }

  Future<void> _barcode() async {
    final code = kIsWeb
        ? await _askBarcode()
        : await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const ScannerScreen()),
          );
    if (code == null || code.isEmpty || !mounted) return;
    if (!isValidBarcode(code)) {
      showMessage(context, 'Das ist kein gültiger Strichcode.');
      return;
    }
    setState(() => _searching = true);
    try {
      final food = await context.app.lookupBarcode(code);
      if (!mounted) return;
      setState(() => _searching = false);
      if (food != null) {
        await _open(food);
        return;
      }
      final create = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Produkt nicht gefunden'),
          content: Text(
            'Zum Strichcode $code gibt es keinen Eintrag. '
            'Möchtest du das Produkt selbst anlegen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Anlegen'),
            ),
          ],
        ),
      );
      if (create == true) await _createCustom(barcode: code);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        showMessage(context, e);
      }
    }
  }

  Future<void> _createCustom({String? barcode}) async {
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) =>
            CustomFoodScreen(barcode: barcode, initialName: _query.text.trim()),
      ),
    );
    if (food != null && mounted) await _open(food);
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.text.trim().isNotEmpty;
    final seen = _local.map((f) => f.id).toSet();
    final online = _online.where((f) => !seen.contains(f.id)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.meal?.label ?? 'Zutat wählen')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const Key('food-search'),
              controller: _query,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Lebensmittel suchen',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        tooltip: 'Leeren',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _query.clear();
                          _onChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onChanged,
              onSubmitted: (_) => _searchOnline(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ActionChip(
                  key: const Key('open-barcode'),
                  avatar: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(kIsWeb ? 'Strichcode' : 'Scannen'),
                  onPressed: _barcode,
                ),
                if (widget.meal case final meal?) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    key: const Key('open-ai'),
                    avatar: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('KI-Analyse'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => AiScreen(meal: meal),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                ActionChip(
                  key: const Key('open-custom'),
                  avatar: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Selbst anlegen'),
                  onPressed: _createCustom,
                ),
              ],
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!hasQuery) ...[
                  if (_recipes.isNotEmpty && !_picking)
                    const _Header('Rezepte'),
                  if (!_picking)
                    for (final f in _recipes) _FoodTile(food: f, onTap: _open),
                  if (_recent.isNotEmpty) const _Header('Zuletzt verwendet'),
                  for (final f in _recent)
                    if (!_picking || f.source != FoodSource.recipe)
                      _FoodTile(food: f, onTap: _open),
                  if (_recent.isEmpty && (_recipes.isEmpty || _picking))
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Suche ein Lebensmittel, scanne einen Strichcode oder '
                        'beschreibe dein Essen für die KI-Analyse.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                ] else ...[
                  for (final f in _local) _FoodTile(food: f, onTap: _open),
                  if (online.isNotEmpty) const _Header('Open Food Facts'),
                  for (final f in online) _FoodTile(food: f, onTap: _open),
                  if (_onlineError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_onlineError!),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton.icon(
                      key: const Key('search-online'),
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('In Open Food Facts suchen'),
                      onPressed: _searching ? null : _searchOnline,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall!
          .copyWith(fontWeight: FontWeight.w800),
    ),
  );
}

class _FoodTile extends StatelessWidget {
  const _FoodTile({required this.food, required this.onTap});
  final Food food;
  final void Function(Food) onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(food.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      [
        ?food.brand,
        '${fmtInt(food.per100.kcal)} kcal / 100 ${food.unit}',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.add_circle_outline),
    onTap: () => onTap(food),
  );
}
