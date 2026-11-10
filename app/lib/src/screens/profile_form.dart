import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../format.dart';

class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    this.initial,
    required this.submitLabel,
    this.onSaved,
  });

  final Profile? initial;
  final String submitLabel;
  final VoidCallback? onSaved;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final Profile? _p = widget.initial;
  late Sex _sex = _p?.sex ?? Sex.female;
  late ActivityLevel _activity = _p?.activity ?? ActivityLevel.light;
  late GoalType _goal = _p?.goal ?? GoalType.maintain;
  late double _rate = _p?.weeklyRateKg ?? 0.25;
  late bool _addActivity = _p?.addActivityToBudget ?? false;
  late final _birth = TextEditingController(text: _p?.birthYear.toString());
  late final _height = TextEditingController(
    text: _p == null ? '' : fmtInput(_p.heightCm),
  );
  late final _weight = TextEditingController(
    text: _p == null ? '' : fmtInput(_p.weightKg),
  );
  late final _kcal = TextEditingController(
    text: _p?.kcalOverride == null ? '' : fmtInput(_p!.kcalOverride!),
  );
  late final _water = TextEditingController(
    text: _p?.waterOverrideMl?.toString() ?? '',
  );

  @override
  void dispose() {
    for (final c in [_birth, _height, _weight, _kcal, _water]) {
      c.dispose();
    }
    super.dispose();
  }

  String? Function(String?) _range(double min, double max) => (v) {
    final d = parseNumber(v ?? '');
    return d == null || d < min || d > max
        ? 'Bitte einen Wert von ${fmtInt(min)} bis ${fmtInt(max)}'
        : null;
  };

  String? Function(String?) _optional(double min, double max) =>
      (v) => (v ?? '').trim().isEmpty ? null : _range(min, max)(v);

  Profile? get _draft {
    final birth = parseNumber(_birth.text);
    final height = parseNumber(_height.text);
    final weight = parseNumber(_weight.text);
    if (birth == null || height == null || weight == null) return null;
    return Profile(
      sex: _sex,
      birthYear: birth.round(),
      heightCm: height,
      weightKg: weight,
      activity: _activity,
      goal: _goal,
      weeklyRateKg: _rate,
      // Felder, die dieses Formular nicht zeigt, bleiben erhalten.
      targetWeightKg: _p?.targetWeightKg,
      kcalOverride: parseNumber(_kcal.text),
      waterOverrideMl: parseNumber(_water.text)?.round(),
      proteinPct: _p?.proteinPct ?? 20,
      carbsPct: _p?.carbsPct ?? 50,
      fatPct: _p?.fatPct ?? 30,
      addActivityToBudget: _addActivity,
      fastingEnabled: _p?.fastingEnabled ?? false,
    );
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final app = context.app;
    final isFirst = app.profile == null;
    final profile = _draft!;
    // Das Gewicht im Profil folgt dem jüngsten Gewichtseintrag; eine
    // Änderung hier wird darum ein Eintrag für heute.
    if (isFirst || (profile.weightKg - _p!.weightKg).abs() >= 0.05) {
      await app.repo.saveWeight(
        WeightEntry(date: dateKey(DateTime.now()), kg: profile.weightKg),
      );
    }
    await app.saveProfile(profile);
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final year = DateTime.now().year;
    final draft = _draft;
    final goals = draft == null ? null : calculateGoals(draft, year: year);
    const gap = SizedBox(height: 12);
    return Form(
      key: _form,
      onChanged: () => setState(() {}),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Sex>(
            initialValue: _sex,
            decoration: const InputDecoration(
              labelText: 'Stoffwechsel berechnen als',
            ),
            items: [
              for (final s in Sex.values)
                DropdownMenuItem(value: s, child: Text(s.label)),
            ],
            onChanged: (v) => setState(() => _sex = v!),
          ),
          gap,
          TextFormField(
            key: const Key('profile-birth'),
            controller: _birth,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Geburtsjahr'),
            validator: _range(year - 110, year - 14),
          ),
          gap,
          TextFormField(
            key: const Key('profile-height'),
            controller: _height,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Größe',
              suffixText: 'cm',
            ),
            validator: _range(100, 250),
          ),
          gap,
          TextFormField(
            key: const Key('profile-weight'),
            controller: _weight,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Gewicht',
              suffixText: 'kg',
            ),
            validator: _range(30, 400),
          ),
          gap,
          DropdownButtonFormField<ActivityLevel>(
            initialValue: _activity,
            decoration: const InputDecoration(labelText: 'Alltag'),
            items: [
              for (final a in ActivityLevel.values)
                DropdownMenuItem(value: a, child: Text(a.label)),
            ],
            onChanged: (v) => setState(() => _activity = v!),
          ),
          gap,
          DropdownButtonFormField<GoalType>(
            initialValue: _goal,
            decoration: const InputDecoration(labelText: 'Ziel'),
            items: [
              for (final g in GoalType.values)
                DropdownMenuItem(value: g, child: Text(g.label)),
            ],
            onChanged: (v) => setState(() => _goal = v!),
          ),
          if (_goal != GoalType.maintain) ...[
            gap,
            Text('Tempo: ${fmtOne(_rate)} kg pro Woche'),
            Slider(
              value: _rate,
              min: 0.1,
              max: maxWeeklyRateKg,
              divisions: 13,
              onChanged: (v) => setState(() => _rate = (v * 20).round() / 20),
            ),
          ],
          gap,
          TextFormField(
            controller: _kcal,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Kalorienziel festlegen (optional)',
              suffixText: 'kcal',
            ),
            validator: _optional(800, 8000),
          ),
          gap,
          TextFormField(
            controller: _water,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Wasserziel festlegen (optional)',
              suffixText: 'ml',
            ),
            validator: _optional(500, 8000),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Verbrannte Kalorien zum Budget addieren'),
            subtitle: const Text(
              'Dein Alltag ist im Ziel schon eingerechnet. Wer das einschaltet, '
              'wählt oben besser „Überwiegend sitzend“.',
            ),
            value: _addActivity,
            onChanged: (v) => setState(() => _addActivity = v),
          ),
          if (goals != null) ...[
            gap,
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dein Tagesziel: ${fmtInt(goals.kcal)} kcal',
                      key: const Key('profile-goal'),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'Eiweiß ${fmtInt(goals.protein)} g · '
                      'Kohlenhydrate ${fmtInt(goals.carbs)} g · '
                      'Fett ${fmtInt(goals.fat)} g · '
                      'Wasser ${fmtInt(goals.waterMl)} ml',
                    ),
                    if (goals.limitedToMinimum)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Rechnerisch läge dein Ziel niedriger. Bociva geht '
                          'nicht unter diese Grenze. Sprich für eine stärkere '
                          'Reduktion bitte mit einer Ärztin oder einem Arzt.',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          gap,
          FilledButton(
            key: const Key('profile-save'),
            onPressed: _save,
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}
