import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';

class CustomFoodScreen extends StatefulWidget {
  const CustomFoodScreen({super.key, this.barcode, this.initialName = ''});
  final String? barcode;
  final String initialName;

  @override
  State<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

class _CustomFoodScreenState extends State<CustomFoodScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _brand = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController(text: '0');
  final _carbs = TextEditingController(text: '0');
  final _fat = TextEditingController(text: '0');
  String _unit = 'g';

  @override
  void dispose() {
    for (final c in [_name, _brand, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _number(String? v) {
    final d = parseNumber(v ?? '');
    return d == null || d < 0 || d > 1000 ? 'Bitte eine Zahl eingeben' : null;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final food = Food(
      id: newId(),
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: widget.barcode,
      unit: _unit,
      per100: Nutrients(
        kcal: parseNumber(_kcal.text)!,
        protein: parseNumber(_protein.text)!,
        carbs: parseNumber(_carbs.text)!,
        fat: parseNumber(_fat.text)!,
      ),
    );
    await context.app.saveCustomFood(food);
    navigator.pop(food);
  }

  Widget _field(TextEditingController c, String label, {Key? key}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: key,
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: _number,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Lebensmittel anlegen')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const Key('custom-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Bitte einen Namen eingeben' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _brand,
            decoration: const InputDecoration(labelText: 'Marke (optional)'),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'g', label: Text('je 100 g')),
              ButtonSegment(value: 'ml', label: Text('je 100 ml')),
            ],
            selected: {_unit},
            onSelectionChanged: (s) => setState(() => _unit = s.first),
          ),
          const SizedBox(height: 12),
          _field(_kcal, 'Kalorien (kcal)', key: const Key('custom-kcal')),
          _field(_protein, 'Eiweiß (g)'),
          _field(_carbs, 'Kohlenhydrate (g)'),
          _field(_fat, 'Fett (g)'),
          FilledButton(
            key: const Key('custom-save'),
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
    ),
  );
}
