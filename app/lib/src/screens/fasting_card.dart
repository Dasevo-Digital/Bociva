import 'dart:async';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/charts.dart';

class FastingCard extends StatefulWidget {
  const FastingCard({super.key});

  @override
  State<FastingCard> createState() => _FastingCardState();
}

class _FastingCardState extends State<FastingCard> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  String _duration(Duration d) =>
      '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')} h';

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final session = app.fasting;
    final theme = Theme.of(context);
    final title = theme.textTheme.titleMedium!.copyWith(
      fontWeight: FontWeight.w800,
    );
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: session == null
            ? Row(
                children: [
                  const Icon(Icons.timelapse, color: BocivaColors.apricot),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Intervallfasten', style: title)),
                  FilledButton.tonal(
                    key: const Key('fasting-start'),
                    onPressed: () => _showStartSheet(context),
                    child: const Text('Starten'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timelapse, color: BocivaColors.apricot),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Fasten läuft', style: title)),
                      Text(
                        '${_duration(session.elapsed(now))} / '
                        '${session.targetHours} h',
                        key: const Key('fasting-elapsed'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ProgressLine(
                    fraction: session.progress(now),
                    color: BocivaColors.apricot,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.progress(now) >= 1
                              ? 'Ziel erreicht'
                              : 'Ziel um '
                                    '${DateFormat('E, HH:mm', 'de').format(session.targetEnd)}',
                        ),
                      ),
                      TextButton(
                        key: const Key('fasting-end'),
                        onPressed: app.endFasting,
                        child: const Text('Beenden'),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

Future<void> _showStartSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _StartSheet(),
    );

class _StartSheet extends StatefulWidget {
  const _StartSheet();

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  int _hours = 16;
  DateTime? _start;

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null) return;
    final now = DateTime.now();
    var start = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    // Eine spätere Uhrzeit meint den gestrigen Abend.
    if (start.isAfter(now)) start = start.subtract(const Duration(days: 1));
    setState(() => _start = start);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Fasten starten', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            for (final hours in fastingPlans)
              ChoiceChip(
                key: Key('fasting-plan-$hours'),
                label: Text('$hours:${24 - hours}'),
                selected: _hours == hours,
                onSelected: (_) => setState(() => _hours = hours),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(
            _start == null
                ? 'Beginn: jetzt'
                : 'Beginn: ${DateFormat('E, HH:mm', 'de').format(_start!)}',
          ),
          trailing: const Text('Ändern'),
          onTap: _pickStart,
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('fasting-confirm'),
          onPressed: () async {
            final navigator = Navigator.of(context);
            await context.app.startFasting(_hours, startAt: _start);
            navigator.pop();
          },
          child: const Text('Starten'),
        ),
      ],
    ),
  );
}
