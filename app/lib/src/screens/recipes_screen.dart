import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';
import '../widgets/brand.dart';
import 'add_food_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  List<Recipe> _recipes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final recipes = await context.app.repo.recipes();
    if (mounted) setState(() => _recipes = recipes);
  }

  Future<void> _edit([Recipe? recipe]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecipeEditScreen(recipe: recipe)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rezepte')),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('recipe-new'),
      icon: const Icon(Icons.add),
      label: const Text('Neues Rezept'),
      onPressed: _edit,
    ),
    body: _recipes.isEmpty
        ? const Center(
            child: SingleChildScrollView(
              child: MascotHint(
                text:
                    'Lege Gerichte an, die du öfter kochst. Sie erscheinen dann '
                    'bei der Lebensmittelsuche und lassen sich als Portion '
                    'eintragen.',
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final r in _recipes)
                ListTile(
                  title: Text(r.name),
                  subtitle: Text(
                    '${fmtInt(r.perServing.kcal)} kcal je Portion · '
                    '${r.servings} ${r.servings == 1 ? 'Portion' : 'Portionen'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _edit(r),
                ),
            ],
          ),
  );
}

class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.recipe?.name);
  late final _servings = TextEditingController(
    text: '${widget.recipe?.servings ?? 2}',
  );
  late final _note = TextEditingController(text: widget.recipe?.note);
  late final List<RecipeIngredient> _ingredients = [
    ...?widget.recipe?.ingredients,
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _servingCount {
    final v = int.tryParse(_servings.text.trim());
    return v == null || v < 1 || v > 100 ? null : v;
  }

  Future<void> _addIngredient() async {
    final ingredient = await Navigator.of(context).push<RecipeIngredient>(
      MaterialPageRoute(builder: (_) => const AddFoodScreen(meal: null)),
    );
    if (ingredient != null) {
      setState(() {
        _ingredients.add(ingredient);
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_ingredients.isEmpty) {
      setState(() => _error = 'Bitte mindestens eine Zutat hinzufügen.');
      return;
    }
    final navigator = Navigator.of(context);
    try {
      await context.app.saveRecipe(
        Recipe(
          id: widget.recipe?.id ?? newId(),
          name: _name.text.trim(),
          servings: _servingCount!,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          ingredients: _ingredients,
        ),
      );
    } on InvalidRecordException catch (e) {
      // Etwa sehr viele Zutaten: Der Server nähme das Rezept nicht an.
      if (mounted) setState(() => _error = '$e');
      return;
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final app = context.app;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rezept löschen?'),
        content: const Text('Bereits Eingetragenes bleibt im Tagebuch.'),
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
    if (ok == true) {
      await app.deleteRecipe(widget.recipe!.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final total = _ingredients.fold(
      Nutrients.zero,
      (sum, i) => sum + i.nutrients,
    );
    final count = _servingCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recipe == null ? 'Neues Rezept' : 'Rezept'),
        actions: [
          if (widget.recipe != null)
            IconButton(
              tooltip: 'Löschen',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _form,
        onChanged: () => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('recipe-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? 'Bitte einen Namen eingeben'
                  : null,
            ),
            gap,
            TextFormField(
              key: const Key('recipe-servings'),
              controller: _servings,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Portionen'),
              validator: (_) =>
                  _servingCount == null ? 'Bitte 1 bis 100 eingeben' : null,
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Zutaten',
                    style: Theme.of(context).textTheme.titleMedium!
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton.icon(
                  key: const Key('recipe-add-ingredient'),
                  icon: const Icon(Icons.add),
                  label: const Text('Hinzufügen'),
                  onPressed: _addIngredient,
                ),
              ],
            ),
            for (final (index, i) in _ingredients.indexed)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(i.name),
                  subtitle: Text(
                    '${fmtOne(i.amount)} ${i.unit} · '
                    '${fmtInt(i.nutrients.kcal)} kcal',
                  ),
                  trailing: IconButton(
                    tooltip: 'Entfernen',
                    icon: const Icon(Icons.close),
                    onPressed: () =>
                        setState(() => _ingredients.removeAt(index)),
                  ),
                ),
              ),
            if (_ingredients.isNotEmpty && count != null) ...[
              gap,
              Text(
                'Je Portion: ${fmtInt(total.kcal / count)} kcal · '
                'E ${fmtOne(total.protein / count)} g · '
                'K ${fmtOne(total.carbs / count)} g · '
                'F ${fmtOne(total.fat / count)} g',
                key: const Key('recipe-per-serving'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            gap,
            TextFormField(
              controller: _note,
              maxLines: 4,
              maxLength: 4000,
              decoration: const InputDecoration(
                labelText: 'Zubereitung (optional)',
              ),
            ),
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
              key: const Key('recipe-save'),
              onPressed: _save,
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }
}
