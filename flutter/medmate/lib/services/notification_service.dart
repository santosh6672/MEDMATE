import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION SERVICE — 3-Ring Retry Logic
//
// GUARDS:
//   1. Login check     — scheduleReminder() silently does nothing if no
//                        refresh token is saved (user not logged in).
//   2. Past-time guard — skips any ring whose time has already passed today
//                        (prevents flood when emulator/device resumes after
//                        being paused or off for a long time).
// ─────────────────────────────────────────────────────────────────────────────

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

const int _retryIntervalMinutes = 2;
const int _maxAttempts          = 3;
const String _takenActionId     = 'MARK_TAKEN';

// ── Initialise ────────────────────────────────────────────────────────────────

Future<void> initNotifications({
  void Function(int baseId, String medicineName)? onTaken,
}) async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  await notificationsPlugin.initialize(
    const InitializationSettings(android: androidSettings),
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.actionId != _takenActionId) return;

      final parts = (response.payload ?? '').split('|');
      if (parts.length < 3) return;

      final baseId       = int.tryParse(parts[0]) ?? 0;
      final medicineName = parts[1];
      final attempt      = int.tryParse(parts[2]) ?? 1;

      _cancelRemainingRings(baseId, attempt);
      onTaken?.call(baseId, medicineName);
      print('✅ $medicineName marked TAKEN (ring $attempt of $_maxAttempts)');
    },
  );

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestExactAlarmsPermission();
}

// ── Login check helper ────────────────────────────────────────────────────────

/// Returns true only if a refresh token is saved in SharedPreferences.
/// Used to block scheduling when the user is not logged in.
Future<bool> _isUserLoggedIn() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('refresh');
  return token != null && token.isNotEmpty;
}

// ── Schedule all 3 rings for one medicine ─────────────────────────────────────

Future<void> scheduleReminder({
  required int    baseId,
  required String medicineName,
  required int    hour,
  required int    minute,
}) async {
  // ── Guard 1: Only schedule if user is logged in ───────────────────────────
  if (!await _isUserLoggedIn()) {
    print('🔒 scheduleReminder blocked — user not logged in');
    return;
  }

  final now  = DateTime.now();
  DateTime base = DateTime(now.year, now.month, now.day, hour, minute);

  // If Ring 1 time has already passed today → schedule from tomorrow.
  // Primary guard against stale notification floods on emulator resume.
  if (base.isBefore(now)) {
    base = base.add(const Duration(days: 1));
  }

  for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
    final ringTime = base.add(
      Duration(minutes: _retryIntervalMinutes * (attempt - 1)),
    );

    // ── Guard 2: Skip any individual ring that is still in the past ──────────
    // Covers DST change, clock skew, emulator time jump.
    if (ringTime.isBefore(now)) {
      print(
        '⏭ Ring $attempt/$_maxAttempts SKIPPED (past): $medicineName '
        'at ${ringTime.hour}:${ringTime.minute.toString().padLeft(2, "0")}',
      );
      continue;
    }

    final tzTime = tz.TZDateTime.from(ringTime, tz.local);

    await _scheduleRing(
      notificationId: baseId + (attempt - 1),
      medicineName:   medicineName,
      baseId:         baseId,
      attempt:        attempt,
      tzTime:         tzTime,
    );

    print(
      '🔔 Ring $attempt/$_maxAttempts scheduled: $medicineName '
      'at ${ringTime.hour}:${ringTime.minute.toString().padLeft(2, "0")}',
    );
  }
}

// ── Cancel all 3 rings for one medicine ──────────────────────────────────────

Future<void> cancelReminder(int baseId) async {
  for (int i = 0; i < _maxAttempts; i++) {
    await notificationsPlugin.cancel(baseId + i);
  }
  print('🚫 All rings cancelled for baseId $baseId');
}

// ── Cancel ALL notifications (call on logout) ─────────────────────────────────

Future<void> cancelAllNotifications() async {
  await notificationsPlugin.cancelAll();
  print('🚫 All notifications cancelled (user logged out)');
}

// ── Internal: schedule a single ring ─────────────────────────────────────────

Future<void> _scheduleRing({
  required int           notificationId,
  required String        medicineName,
  required int           baseId,
  required int           attempt,
  required tz.TZDateTime tzTime,
}) async {
  const alarmSound = RawResourceAndroidNotificationSound('alarm');

  final vibrationPattern = Int64List.fromList([
    0,   800, 200, 800, 200,
    800, 200, 800, 200, 800,
    200, 800, 200, 800,
  ]);

  final String bodyText = switch (attempt) {
    1 => 'Time to take: $medicineName',
    2 => 'Reminder 2 of 3 — Did you take $medicineName?',
    _ => '⚠️ Final reminder — Please take $medicineName now!',
  };

  final androidDetails = AndroidNotificationDetails(
    'medicine_alarm_channel_v3',
    'Medicine Alarm',
    channelDescription: 'Rings up to $_maxAttempts times until you respond',
    importance:  Importance.max,
    priority:    Priority.high,
    sound:               alarmSound,
    playSound:           true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    vibrationPattern: vibrationPattern,
    enableVibration:  true,
    fullScreenIntent: true,
    category:         AndroidNotificationCategory.alarm,
    actions: const [
      AndroidNotificationAction(
        _takenActionId,
        '✅  Taken',
        cancelNotification: true,
        showsUserInterface: false,
      ),
    ],
    autoCancel: true,
    ongoing:    false,
    styleInformation: BigTextStyleInformation(
      bodyText,
      contentTitle: '💊 Medicine Alarm',
    ),
  );

  await notificationsPlugin.zonedSchedule(
    notificationId,
    '💊 Medicine Alarm',
    bodyText,
    tzTime,
    NotificationDetails(android: androidDetails),
    payload: '$baseId|$medicineName|$attempt',
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

// ── Internal: cancel rings that haven't fired yet ─────────────────────────────

Future<void> _cancelRemainingRings(int baseId, int completedAttempt) async {
  for (int attempt = completedAttempt + 1; attempt <= _maxAttempts; attempt++) {
    await notificationsPlugin.cancel(baseId + (attempt - 1));
    print('🚫 Ring $attempt cancelled for baseId $baseId');
  }
}