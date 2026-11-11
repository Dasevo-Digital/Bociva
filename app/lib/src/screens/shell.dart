import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/material.dart';

import '../controller.dart';
import '../widgets/streak.dart';
import 'diary_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

/// Rahmen: unten Navigation auf dem Telefon, links im breiten Browserfenster.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _index = 0;
  String _today = dateKey(DateTime.now());

  static const _pages = [DiaryScreen(), StatsScreen(), SettingsScreen()];
  static const _items = [
    (Icons.today_outlined, Icons.today, 'Tagebuch'),
    (Icons.insights_outlined, Icons.insights, 'Verlauf'),
    (Icons.tune_outlined, Icons.tune, 'Mehr'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final previous = _today;
      _today = dateKey(DateTime.now());
      context.app.onResume(previousToday: previous);
    }
  }

  /// Erst zeigen, wenn die Eingabemasken geschlossen sind; sonst schlösse
  /// deren `pop` die Würdigung.
  void _maybeCelebrate(AppController app) {
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (!app.hasCelebration || !current) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final streak = app.takeCelebration();
      if (streak != null) celebrateStreak(context, streak);
    });
  }

  @override
  Widget build(BuildContext context) {
    _maybeCelebrate(context.app);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(index: _index, children: _pages);
    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (icon, selected, label) in _items)
                  NavigationRailDestination(
                    icon: Icon(icon),
                    selectedIcon: Icon(selected),
                    label: Text(label),
                  ),
              ],
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: body,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final (icon, selected, label) in _items)
            NavigationDestination(
              icon: Icon(icon),
              selectedIcon: Icon(selected),
              label: label,
            ),
        ],
      ),
    );
  }
}
