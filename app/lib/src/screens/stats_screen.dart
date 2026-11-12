import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/streak.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int _days = 7, _loadedVersion = -1, _loadedDays = 0;
  List<DaySummary> _summaries = const [];
  List<WeightEntry> _weights = const [];
  List<FastingSession> _fasts = const [];
  String? _review;
  bool _reviewing = false;

  Future<void> _load(AppController app) async {
    final profile = app.profile;
    if (profile == null) return;
    _loadedVersion = app.dataVersion;
    _loadedDays = _days;
    final today = DateTime.now();
    final summaries = await app.repo.summaries(dateKey(today), _days, profile);
    final weights = await app.repo.weights(
      dateKey(today.subtract(const Duration(days: 180))),
      dateKey(today),
    );
    final fasts = (await app.repo.fastingSessions())
        .where((f) => !f.isActive)
        .take(10)
        .toList();
    if (mounted) {
      setState(() {
        _summaries = summaries;
        _weights = weights;
        _fasts = fasts;
      });
    }
  }

  Future<void> _addWeight(AppController app) async {
    final controller = TextEditingController(
      text: _weights.isNotEmpty ? fmtInput(_weights.last.kg) : '',
    );
    final kg = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gewicht eintragen'),
        content: TextField(
          key: const Key('weight-field'),
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('weight-save'),
            onPressed: () => Navigator.pop(ctx, parseNumber(controller.text)),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (kg != null && kg >= 20 && kg <= 400) {
      await app.saveWeight(kg, onDate: dateKey(DateTime.now()));
    }
  }

  Future<bool> _askConsent(AppController app) async {
    if (await app.reviewConsented()) return true;
    if (!mounted) return false;
    final health = app.healthEnabled
        ? ' (auch aus ${app.health.platformName})'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tagessummen an ${app.aiDestination} senden?'),
        content: Text(
          'Für die Auswertung gehen pro Tag gegessene Kalorien, Eiweiß, '
          'Kohlenhydrate, Fett, Wasser und verbrannte Kalorien$health an '
          'diesen Dienst, dazu deine Tagesziele. Was du gegessen hast und '
          'dein Profil bleiben bei dir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            key: const Key('ai-review-consent'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Einverstanden'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    await app.consentToReview();
    return true;
  }

  Future<void> _runReview(AppController app) async {
    if (!await _askConsent(app) || !mounted) return;
    setState(() {
      _reviewing = true;
      _review = null;
    });
    try {
      final text = await app.reviewRecentDays(_days);
      if (mounted) setState(() => _review = text);
    } on Exception catch (e) {
      if (mounted) setState(() => _review = '$e');
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }

  List<String> get _labels => [
    for (final d in _summaries)
      DateFormat(
        _days <= 7 ? 'E' : 'd.',
        'de',
      ).format(parseDateKey(d.date)).replaceAll('.', ''),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (_loadedVersion != app.dataVersion || _loadedDays != _days) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(app));
    }
    final logged = _summaries.where((d) => d.entries.isNotEmpty).toList();
    final avg = logged.isEmpty
        ? 0.0
        : logged.fold(0.0, (s, d) => s + d.consumed.kcal) / logged.length;
    final theme = Theme.of(context);
    final heading = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w800,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Verlauf')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 Tage')),
              ButtonSegment(value: 30, label: Text('30 Tage')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() {
              _days = s.first;
              _review = null;
            }),
          ),
          const SizedBox(height: 12),
          if (app.streak case final streak?) ...[
            Card(
              key: const Key('stats-streak'),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FlameBadge(lit: streak.todayDone, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Serie', style: heading),
                              Text(
                                '${daysLabel(streak.current)} in Folge · '
                                'längste ${daysLabel(streak.longest)}',
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Einzelheiten',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => showStreakSheet(context, streak),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    StreakCalendar(streak: streak),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Kalorien', style: heading),
                  Text(
                    logged.isEmpty
                        ? 'Noch keine Einträge'
                        : 'Im Schnitt ${fmtInt(avg)} kcal an ${logged.length} '
                              '${logged.length == 1 ? 'Tag' : 'Tagen'} mit Einträgen',
                  ),
                  const SizedBox(height: 12),
                  BarChart(
                    values: [for (final d in _summaries) d.consumed.kcal],
                    labels: _labels,
                    goal: _summaries.lastOrNull?.goals.kcal,
                    color: theme.brightness == Brightness.dark
                        ? BocivaColors.leaf
                        : BocivaColors.green,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wasser', style: heading),
                  const SizedBox(height: 12),
                  BarChart(
                    values: [for (final d in _summaries) d.waterMl.toDouble()],
                    labels: _labels,
                    goal: _summaries.lastOrNull?.goals.waterMl.toDouble(),
                    color: BocivaColors.water,
                    height: 110,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Gewicht', style: heading)),
                      TextButton.icon(
                        key: const Key('weight-add'),
                        icon: const Icon(Icons.add),
                        label: const Text('Eintragen'),
                        onPressed: () => _addWeight(app),
                      ),
                    ],
                  ),
                  if (_weights.isEmpty)
                    const Text('Noch kein Gewicht eingetragen.')
                  else ...[
                    Text(
                      'Aktuell ${fmtOne(_weights.last.kg)} kg',
                      key: const Key('weight-current'),
                    ),
                    const SizedBox(height: 12),
                    LineChart(
                      values: [for (final w in _weights) w.kg],
                      color: BocivaColors.coral,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if ((app.profile?.fastingEnabled ?? false) && _fasts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Fasten', style: heading),
                    ),
                    for (final f in _fasts)
                      ListTile(
                        dense: true,
                        title: Text(
                          DateFormat('E, d. MMM', 'de').format(f.start),
                        ),
                        subtitle: Text(
                          '${f.elapsed(DateTime.now()).inHours} h '
                          '${f.elapsed(DateTime.now()).inMinutes % 60} min '
                          'von ${f.targetHours} h',
                        ),
                        trailing: IconButton(
                          tooltip: 'Löschen',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => app.deleteFasting(f.id),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
          if (app.aiDestination != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('KI-Auswertung', style: heading),
                    const SizedBox(height: 4),
                    Text(
                      'Sendet nur die Tagessummen an ${app.aiDestination}.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonal(
                      key: const Key('ai-review'),
                      onPressed: _reviewing ? null : () => _runReview(app),
                      child: Text('$_days Tage auswerten'),
                    ),
                    if (_reviewing)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (_review != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_review!),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
