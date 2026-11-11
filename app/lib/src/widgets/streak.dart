import 'dart:math';

import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';
import 'brand.dart';
import 'charts.dart';

String daysLabel(int n) => n == 1 ? '1 Tag' : '$n Tage';

String _weekday(String date) =>
    DateFormat('E', 'de').format(parseDateKey(date)).replaceAll('.', '');

/// Flamme im runden Abzeichen; grau, solange heute nichts eingetragen ist.
class FlameBadge extends StatelessWidget {
  const FlameBadge({super.key, required this.lit, this.size = 52});
  final bool lit;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: lit
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [BocivaColors.wheat, BocivaColors.apple],
              )
            : null,
        color: lit
            ? null
            : dark
            ? const Color(0xFF2C3A31)
            : const Color(0xFFEDE5DC),
        boxShadow: lit
            ? [
                BoxShadow(
                  color: BocivaColors.apple.withValues(alpha: 0.35),
                  blurRadius: size / 4,
                  offset: Offset(0, size / 12),
                ),
              ]
            : null,
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        size: size * 0.6,
        color: lit
            ? Colors.white
            : dark
            ? const Color(0xFF6E7F73)
            : const Color(0xFFB3A79B),
      ),
    );
  }
}

/// Kleine Anzeige für die Titelleiste.
class StreakChip extends StatelessWidget {
  const StreakChip({super.key, required this.streak});
  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lit = streak.todayDone;
    return Tooltip(
      message: '${daysLabel(streak.current)} in Folge',
      child: InkWell(
        key: const Key('streak-chip'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => showStreakSheet(context, streak),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: lit ? BocivaColors.coral : scheme.outline,
              ),
              const SizedBox(width: 2),
              Text(
                '${streak.current}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: !lit
                      ? scheme.onSurfaceVariant
                      : scheme.brightness == Brightness.dark
                      ? BocivaColors.coral
                      : BocivaColors.coralDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Die letzten sieben Tage als Punkte.
class StreakWeek extends StatelessWidget {
  const StreakWeek({super.key, required this.streak});
  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final d in streak.lastDays(7))
          Column(
            children: [
              _DayDot(
                done: streak.tracked(d),
                today: d == streak.today,
                dark: dark,
              ),
              const SizedBox(height: 4),
              Text(
                _weekday(d),
                style: theme.textTheme.labelSmall!.copyWith(
                  fontWeight: d == streak.today ? FontWeight.w800 : null,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({required this.done, required this.today, required this.dark});
  final bool done, today, dark;

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: done
          ? BocivaColors.green
          : dark
          ? const Color(0xFF2C3A31)
          : Colors.white.withValues(alpha: 0.8),
      border: today && !done
          ? Border.all(color: BocivaColors.coral, width: 2)
          : null,
    ),
    child: done
        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
        : null,
  );
}

({String title, String text}) _wording(Streak s) {
  if (s.current == 0) {
    return (
      title: 'Starte deine Serie',
      text: 'Trag heute dein Essen ein. Jeder Tag in Folge zählt.',
    );
  }
  final title = '${daysLabel(s.current)} in Folge';
  if (s.atRisk) {
    return (
      title: title,
      text: 'Trag heute etwas ein, damit deine Serie hält.',
    );
  }
  return (
    title: title,
    text: s.current == 1
        ? 'Der erste Tag ist geschafft. Bis morgen!'
        : 'Heute erledigt, weiter so!',
  );
}

/// Serie auf der Tagebuchseite, mit Maskottchen.
class StreakCard extends StatelessWidget {
  const StreakCard({super.key, required this.streak});
  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final words = _wording(streak);
    final next = streak.nextMilestone;
    return Card(
      key: const Key('streak-card'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showStreakSheet(context, streak),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark
                  ? const [Color(0xFF2B2420), Color(0xFF19271F)]
                  : const [BocivaColors.peach, Color(0xFFFFF4EA)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Mascot(height: 84),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            words.title,
                            key: const Key('streak-title'),
                            style: theme.textTheme.titleMedium!.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(words.text, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FlameBadge(lit: streak.todayDone, size: 46),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: StreakWeek(streak: streak),
                ),
                if (next != null && streak.current > 0) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: ProgressLine(
                            fraction: streak.current / next,
                            color: BocivaColors.coral,
                            track: dark
                                ? const Color(0xFF3A2F2A)
                                : Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Noch ${daysLabel(next - streak.current)} bis $next',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Einzelheiten: aktuelle und längste Serie, Meilensteine.
Future<void> showStreakSheet(BuildContext context, Streak streak) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final words = _wording(streak);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              children: [
                const BurstMascot(height: 150),
                const SizedBox(height: 8),
                Text(
                  words.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall!.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(words.text, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _Figure('Aktuell', daysLabel(streak.current)),
                    _Figure('Längste', daysLabel(streak.longest)),
                    _Figure('Insgesamt', daysLabel(streak.totalDays)),
                  ],
                ),
                const SizedBox(height: 20),
                StreakWeek(streak: streak),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Meilensteine',
                    style: theme.textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in Streak.milestones.take(9))
                      _Milestone(days: m, reached: streak.longest >= m),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Ein Tag zählt, sobald du mindestens eine Mahlzeit '
                  'einträgst. Ohne Eintrag bis Mitternacht beginnt die Serie '
                  'von vorn.',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.primary,
            ),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Milestone extends StatelessWidget {
  const _Milestone({required this.days, required this.reached});
  final int days;
  final bool reached;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: reached
            ? BocivaColors.coral.withValues(alpha: 0.16)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      child: Column(
        children: [
          Icon(
            reached
                ? Icons.local_fire_department_rounded
                : Icons.lock_outline_rounded,
            color: reached ? BocivaColors.coral : scheme.outline,
            size: 22,
          ),
          Text(
            '$days',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: reached ? null : scheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kalender der letzten Wochen für den Verlauf.
class StreakCalendar extends StatelessWidget {
  const StreakCalendar({super.key, required this.streak, this.weeks = 5});
  final Streak streak;
  final int weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final today = parseDateKey(streak.today);
    // Ganze Wochen von Montag bis Sonntag, die letzte enthält heute.
    final monday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - 1) - (weeks - 1) * 7,
    );
    final labels = [
      for (var i = 0; i < 7; i++)
        _weekday(dateKey(DateTime(monday.year, monday.month, monday.day + i))),
    ];
    return Column(
      children: [
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(l, style: theme.textTheme.labelSmall),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Center(
                      child: _CalendarDay(
                        date: DateTime(
                          monday.year,
                          monday.month,
                          monday.day + w * 7 + i,
                        ),
                        streak: streak,
                        dark: dark,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.streak,
    required this.dark,
  });
  final DateTime date;
  final Streak streak;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final key = dateKey(date);
    final future = key.compareTo(streak.today) > 0;
    final done = streak.tracked(key);
    final isToday = key == streak.today;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done
            ? BocivaColors.green
            : future
            ? Colors.transparent
            : dark
            ? const Color(0xFF223529)
            : BocivaColors.cream,
        border: isToday && !done
            ? Border.all(color: BocivaColors.coral, width: 2)
            : null,
      ),
      child: Text(
        '${date.day}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: done
              ? Colors.white
              : future
              ? Theme.of(context).colorScheme.outlineVariant
              : null,
        ),
      ),
    );
  }
}

/// Maskottchen mit grünen Freudenstrichen wie im Markenbild.
class BurstMascot extends StatelessWidget {
  const BurstMascot({super.key, this.height = 160});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    width: height * 1.5,
    child: CustomPaint(
      painter: _BurstPainter(),
      child: Center(child: Mascot(height: height * 0.86)),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.height * 0.035;
    final center = size.center(Offset.zero);
    final r1 = size.height * 0.5, r2 = size.height * 0.64;
    // Je drei Striche links oben und rechts oben.
    const angles = [-160.0, -135.0, -110.0, -70.0, -45.0, -20.0];
    for (var i = 0; i < angles.length; i++) {
      final a = angles[i] * pi / 180;
      final dir = Offset(cos(a), sin(a));
      paint.color = i.isEven ? BocivaColors.leaf : BocivaColors.coral;
      canvas.drawLine(center + dir * r1, center + dir * r2, paint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter oldDelegate) => false;
}

String _milestoneText(int days) => switch (days) {
  3 => 'Drei Tage am Stück. Ein richtig guter Anfang!',
  7 => 'Eine ganze Woche! Daraus wird gerade eine Gewohnheit.',
  14 => 'Zwei Wochen drangeblieben. Stark!',
  30 => 'Ein ganzer Monat. Du bist nicht mehr zu bremsen.',
  365 => 'Ein ganzes Jahr! Unglaublich.',
  _ => '$days Tage in Folge. Beeindruckend!',
};

/// Würdigt eine verlängerte Serie: bei Meilensteinen groß, sonst kurz.
Future<void> celebrateStreak(BuildContext context, Streak streak) async {
  if (!streak.isMilestone) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('streak-snack'),
          content: Row(
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: BocivaColors.coral,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  streak.current == 1
                      ? 'Tag 1 deiner Serie. Bis morgen!'
                      : '${daysLabel(streak.current)} in Folge, weiter so!',
                ),
              ),
            ],
          ),
        ),
      );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return Dialog(
        key: const Key('streak-dialog'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BurstMascot(height: 170),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const FlameBadge(lit: true, size: 40),
                  const SizedBox(width: 10),
                  Text(
                    daysLabel(streak.current),
                    style: theme.textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _milestoneText(streak.current),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('streak-dialog-ok'),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Weiter so'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
