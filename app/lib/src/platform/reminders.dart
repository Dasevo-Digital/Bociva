import 'package:bociva_shared/bociva_shared.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Abendliche Erinnerung, damit die Serie nicht reißt.
///
/// Lokale Benachrichtigungen können nicht selbst prüfen, ob heute schon
/// etwas eingetragen ist. Deshalb plant die App jeweils die nächsten Tage
/// im Voraus und lässt den heutigen Abend aus, sobald etwas eingetragen ist.
/// Öffnet jemand die App eine Woche lang nicht, hört die Erinnerung auf.
class Reminders {
  static const _firstId = 7100;
  static const days = 7;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } on Object {
      // Unbekannte Zone: UTC wäre falsch, aber besser als gar keine.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_bociva'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Fragt das System um Erlaubnis. `false`, wenn abgelehnt.
  Future<bool> requestPermission() async {
    await _init();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Plant die Erinnerungen um [minutes] nach Mitternacht für die nächsten
  /// Tage neu.
  Future<void> schedule({required int minutes, required Streak streak}) async {
    await _init();
    await cancel();
    final now = tz.TZDateTime.now(tz.local);
    for (var day = 0; day < days; day++) {
      final at = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) continue;
      if (day == 0 && streak.todayDone) continue;
      await _plugin.zonedSchedule(
        id: _firstId + day,
        scheduledDate: at,
        title: 'Bociva',
        body: reminderText(streak, day),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'streak',
            'Erinnerung am Abend',
            channelDescription:
                'Erinnert abends, wenn noch nichts eingetragen ist.',
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  Future<void> cancel() async {
    await _init();
    for (var day = 0; day < days; day++) {
      await _plugin.cancel(id: _firstId + day);
    }
  }
}

/// Text der Erinnerung in [day] Tagen (0 = heute).
@visibleForTesting
String reminderText(Streak streak, int day) {
  // Bis dahin hält die Serie nur, wenn bis dahin jeden Tag etwas dazukommt;
  // sicher ist die Zahl nur für heute und, wenn heute erledigt, für morgen.
  final known = day == 0 || (day == 1 && streak.todayDone);
  final length = streak.current;
  if (known && length > 0) {
    return 'Deine Serie von ${length == 1 ? '1 Tag' : '$length Tagen'} hält '
        'noch bis Mitternacht. Trag kurz ein, was du gegessen hast.';
  }
  return 'Schon etwas eingetragen? Jeder Tag zählt für deine Serie.';
}
