import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';

/// Menge wählen und eintragen. Gibt `true` zurück, wenn etwas eingetragen wurde.
Future<bool?> showFoodAmountSheet(BuildContext context, Food food, Meal meal) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FoodAmountSheet(food: food, meal: meal),
    );

class _FoodAmountSheet extends StatefulWidget {
  const _FoodAmountSheet({required this.food, required this.meal});
  final Food food;
  final Meal meal;

  @override
  State<_FoodAmountSheet> createState() => _FoodAmountSheetState();
}

class _FoodAmountSheetState extends State<_FoodAmountSheet> {
  late final TextEditingController _amount;

  @override
  void initState() {
    super.initState();
    final first = widget.food.servings.firstOrNull;
    _amount = TextEditingController(text: fmtOne(first?.amount ?? 100));
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _value {
    final v = parseNumber(_amount.text);
    return v == null || v <= 0 || v > 10000 ? null : v;
  }

  @override
  Widget build(BuildContext context) {
    final food = widget.food;
    final n = food.forAmount(_value ?? 0);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(food.name, style: Theme.of(context).textTheme.titleLarge),
          if (food.brand != null) Text(food.brand!),
          const SizedBox(height: 14),
          TextField(
            key: const Key('amount-field'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Menge',
              suffixText: food.unit,
            ),
          ),
          if (food.servings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in food.servings)
                  ActionChip(
                    label: Text(s.name),
                    onPressed: () => _amount.text = fmtOne(s.amount),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _NutrientRow(n),
          if (food.source == FoodSource.openFoodFacts)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Quelle: Open Food Facts (ODbL)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('amount-add'),
            onPressed: _value == null
                ? null
                : () async {
                    final navigator = Navigator.of(context);
                    await context.app.logFood(food, widget.meal, _value!);
                    navigator.pop(true);
                  },
            child: Text('Zu ${widget.meal.label} hinzufügen'),
          ),
        ],
      ),
    );
  }
}

class _NutrientRow extends StatelessWidget {
  const _NutrientRow(this.n);
  final Nutrients n;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _cell('kcal', fmtInt(n.kcal)),
      _cell('Eiweiß', '${fmtOne(n.protein)} g'),
      _cell('Kohlenh.', '${fmtOne(n.carbs)} g'),
      _cell('Fett', '${fmtOne(n.fat)} g'),
    ],
  );

  Widget _cell(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
      ),
      Text(label),
    ],
  );
}

/// Eintrag ändern oder löschen.
Future<void> showEntrySheet(BuildContext context, DiaryEntry entry) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EntrySheet(entry: entry),
    );

class _EntrySheet extends StatefulWidget {
  const _EntrySheet({required this.entry});
  final DiaryEntry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _amount = TextEditingController(text: fmtOne(widget.entry.amount));

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(e.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${fmtInt(e.nutrients.kcal)} kcal · '
            'E ${fmtOne(e.nutrients.protein)} g · '
            'K ${fmtOne(e.nutrients.carbs)} g · '
            'F ${fmtOne(e.nutrients.fat)} g'
            '${e.estimated ? ' · geschätzt' : ''}',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Menge', suffixText: e.unit),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('entry-delete'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await context.app.deleteEntry(e);
                    navigator.pop();
                  },
                  child: const Text('Löschen'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    final amount = parseNumber(_amount.text);
                    if (amount == null || amount <= 0 || amount > 10000) return;
                    final navigator = Navigator.of(context);
                    await context.app.updateEntry(e, amount);
                    navigator.pop();
                  },
                  child: const Text('Speichern'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
