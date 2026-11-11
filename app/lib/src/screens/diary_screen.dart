import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/charts.dart';
import '../widgets/streak.dart';
import 'add_food_screen.dart';
import 'fasting_card.dart';
import 'food_amount_sheet.dart';

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  String _title(AppController app) {
    final d = parseDateKey(app.date);
    final now = DateTime.now();
    final diff = DateTime(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return switch (diff) {
      0 => 'Heute',
      -1 => 'Gestern',
      1 => 'Morgen',
      _ => DateFormat('E, d. MMM', 'de').format(d),
    };
  }

  Future<void> _pickDate(BuildContext context, AppController app) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: parseDateKey(app.date),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) await app.goToDate(dateKey(picked));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final day = app.day;
    if (day == null) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          key: const Key('date-title'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => _pickDate(context, app),
          child: Text(_title(app)),
        ),
        actions: [
          if (app.streak case final streak?) StreakChip(streak: streak),
          IconButton(
            tooltip: 'Vorheriger Tag',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => app.shiftDate(-1),
          ),
          IconButton(
            tooltip: 'Nächster Tag',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => app.shiftDate(1),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await app.syncNow();
          await app.syncHealth(force: true);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _SummaryCard(day: day),
            const SizedBox(height: 12),
            if (app.isToday && app.streak != null) ...[
              StreakCard(streak: app.streak!),
              const SizedBox(height: 12),
            ],
            if ((app.profile?.fastingEnabled ?? false) && app.isToday) ...[
              const FastingCard(),
              const SizedBox(height: 12),
            ],
            for (final meal in Meal.values) ...[
              _MealCard(meal: meal, day: day),
              const SizedBox(height: 12),
            ],
            _WaterCard(day: day),
            const SizedBox(height: 12),
            _ActivityCard(day: day),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.day});
  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final consumed = day.consumed;
    final remaining = day.remainingKcal;
    final over = remaining < 0;
    const light = TextStyle(color: Colors.white);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [BocivaColors.green, BocivaColors.forestDeep],
          ),
        ),
        child: CustomPaint(
          painter: const LeafDecoration(color: Color(0x14FFFFFF)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _summaryContent(consumed, remaining, over, light),
          ),
        ),
      ),
    );
  }

  Widget _summaryContent(
    Nutrients consumed,
    double remaining,
    bool over,
    TextStyle light,
  ) => Column(
    children: [
      Row(
        children: [
          CalorieRing(
            fraction: day.budgetKcal <= 0 ? 0 : consumed.kcal / day.budgetKcal,
            over: over,
            size: 148,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  fmtInt(remaining.abs()),
                  key: const Key('kcal-remaining'),
                  style: light.copyWith(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  over ? 'kcal darüber' : 'kcal übrig',
                  style: light.copyWith(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stat('Gegessen', fmtInt(consumed.kcal)),
                const SizedBox(height: 10),
                _Stat('Tagesziel', fmtInt(day.budgetKcal)),
                const SizedBox(height: 10),
                _Stat('Verbrannt', fmtInt(day.burnedKcal)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          _Macro(
            'Eiweiß',
            Icons.fitness_center_rounded,
            consumed.protein,
            day.goals.protein,
            BocivaColors.proteinOnGreen,
          ),
          const SizedBox(width: 12),
          _Macro(
            'Kohlenh.',
            Icons.grass_rounded,
            consumed.carbs,
            day.goals.carbs,
            BocivaColors.carbsOnGreen,
          ),
          const SizedBox(width: 12),
          _Macro(
            'Fett',
            Icons.opacity_rounded,
            consumed.fat,
            day.goals.fat,
            BocivaColors.fatOnGreen,
          ),
        ],
      ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      Text(
        '$value kcal',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.icon, this.value, this.goal, this.color);
  final String label;
  final IconData icon;
  final double value, goal;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ProgressLine(
          fraction: goal <= 0 ? 0 : value / goal,
          color: color,
          track: Colors.white24,
        ),
        const SizedBox(height: 4),
        Text(
          '${fmtInt(value)} / ${fmtInt(goal)} g',
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ],
    ),
  );
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.day});
  final Meal meal;
  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final entries = day.entries.where((e) => e.meal == meal).toList();
    final kcal = day.consumedIn(meal).kcal;
    final theme = Theme.of(context);
    final (icon, color) = switch (meal) {
      Meal.breakfast => (Icons.free_breakfast_rounded, BocivaColors.wheat),
      Meal.lunch => (Icons.lunch_dining_rounded, BocivaColors.protein),
      Meal.dinner => (Icons.dinner_dining_rounded, BocivaColors.coral),
      Meal.snack => (Icons.cookie_rounded, BocivaColors.apple),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            ListTile(
              leading: IconBubble(icon: icon, color: color),
              title: Text(
                meal.label,
                style: theme.textTheme.titleMedium!.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              subtitle: Text(
                entries.isEmpty
                    ? 'Noch nichts eingetragen'
                    : '${fmtInt(kcal)} kcal',
              ),
              trailing: IconButton.filledTonal(
                key: Key('add-${meal.name}'),
                tooltip: '${meal.label} hinzufügen',
                icon: const Icon(Icons.add),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AddFoodScreen(meal: meal),
                  ),
                ),
              ),
            ),
            if (entries.isNotEmpty) const Divider(indent: 16, endIndent: 16),
            for (final e in entries)
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 72, right: 20),
                title: Text(
                  e.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${fmtInt(e.amount)} ${e.unit}'
                  '${e.estimated ? ' · geschätzt' : ''}',
                ),
                trailing: Text('${fmtInt(e.nutrients.kcal)} kcal'),
                onTap: () => showEntrySheet(context, e),
              ),
          ],
        ),
      ),
    );
  }
}

class _WaterCard extends StatelessWidget {
  const _WaterCard({required this.day});
  final DaySummary day;

  Future<void> _custom(BuildContext context) async {
    final app = context.app;
    final controller = TextEditingController();
    final ml = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wassermenge'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'ml'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, parseNumber(controller.text)?.round()),
            child: const Text('Eintragen'),
          ),
        ],
      ),
    );
    if (ml != null && ml > 0 && ml <= 5000) await app.addWater(ml);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBubble(
                  icon: Icons.water_drop_rounded,
                  color: BocivaColors.water,
                ),
                const SizedBox(width: 16),
                Text(
                  'Wasser',
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${fmtInt(day.waterMl)} / ${fmtInt(day.goals.waterMl)} ml',
                  key: const Key('water-total'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ProgressLine(
              fraction: day.goals.waterMl <= 0
                  ? 0
                  : day.waterMl / day.goals.waterMl,
              color: BocivaColors.water,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final ml in const [200, 250, 500])
                  ActionChip(
                    key: Key('water-$ml'),
                    label: Text('+$ml ml'),
                    onPressed: () => app.addWater(ml),
                  ),
                ActionChip(
                  label: const Text('Andere Menge'),
                  onPressed: () => _custom(context),
                ),
                if (day.water.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.undo, size: 16),
                    label: const Text('Rückgängig'),
                    onPressed: app.undoWater,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.day});
  final DaySummary day;

  @override
  Widget build(BuildContext context) {
    final workouts = day.activities
        .where((a) => a.kind == ActivityKind.workout)
        .toList();
    if (day.activities.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const IconBubble(
                  icon: Icons.directions_run_rounded,
                  color: BocivaColors.coral,
                ),
                const SizedBox(width: 16),
                Text(
                  'Aktivität',
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                if (day.steps > 0) Text('${fmtInt(day.steps)} Schritte'),
              ],
            ),
            for (final w in workouts)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${w.title ?? 'Training'} · ${w.minutes} min · '
                  '${fmtInt(w.activeKcal)} kcal',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
