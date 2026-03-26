import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

// ── Singleton plugin instance ──────────────────────────────────────────────

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ── Notification channel constants ────────────────────────────────────────

const String _channelId   = 'med_channel';
const String _channelName = 'Medicine Reminders';

// ── Custom sound ──────────────────────────────────────────────────────────
// File lives at: android/app/src/main/res/raw/alarm.mp3
// Reference WITHOUT the file extension — Android resolves it automatically.
const _alarmSound = RawResourceAndroidNotificationSound('alarm');

// ── Initialisation ─────────────────────────────────────────────────────────

/// Call once from main() before runApp().
///
/// Steps performed:
///   1. Initialise timezone data and set device-local timezone.
///   2. Configure the flutter_local_notifications plugin.
///   3. Create the Android notification channel with the custom alarm sound.
///   4. Request POST_NOTIFICATIONS permission (Android 13+ / API 33+).
///   5. Request exact-alarm permission (Android 12+ / API 31+).
Future<void> initNotifications() async {
  // 1. Timezone setup ───────────────────────────────────────────────────────
  tz.initializeTimeZones();
  final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone();
  tz.setLocalLocation(tz.getLocation(tzInfo.identifier));

  // 2. Plugin initialisation ────────────────────────────────────────────────
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse:          _onNotificationTapped,
    onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
  );

  // 3. Create the Android notification channel ──────────────────────────────
  // The channel's sound is set ONCE at creation and cannot be changed after.
  // To change the sound later, use a new channel ID (e.g. 'med_channel_v2').
  await _createNotificationChannel();

  // 4 & 5. Runtime permissions ──────────────────────────────────────────────
  // Postponed to be called after login (e.g., DashboardScreen) instead of startup.
}

/// Creates the notification channel with alarm.mp3 as the custom sound.
///
/// ⚠️  Android caches channel settings after first creation. If you need to
///     change the sound, bump the channel ID to force a fresh channel.
Future<void> _createNotificationChannel() async {
  final channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description:     'Daily medicine intake reminders',
    importance:      Importance.max,
    // ── Custom sound ──────────────────────────────────────────────────
    // Points to res/raw/alarm.mp3 (no extension).
    // Android plays the file for up to ~10 s before the system cuts it off.
    // If alarm.mp3 is shorter than 10 s it plays once and stops naturally.
    sound:           _alarmSound,
    playSound:       true,
    enableVibration: true,
    enableLights:    true,
    showBadge:       true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

// ── Notification tap callback ──────────────────────────────────────────────

@pragma('vm:entry-point')
void _onNotificationTapped(NotificationResponse response) {
  // TODO: navigate to the relevant screen using a global navigator key.
  // final payload = response.payload; // contains medicine name
}

// ── Schedule a daily repeating reminder ───────────────────────────────────

/// Schedules a daily notification for [medicineName] at [hour]:[minute].
///
/// Plays alarm.mp3 for up to 10 seconds on firing.
/// Returns `true` on success, `false` if scheduling fails.
Future<bool> scheduleReminder({
  required int    baseId,
  required String medicineName,
  required int    hour,
  required int    minute,
}) async {
  try {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Daily medicine intake reminders',
      importance:         Importance.max,
      priority:           Priority.high,
      // ── Custom sound (must match the channel's sound) ──────────────
      // Both channel AND notification details must reference the same
      // sound. If they differ, Android ignores the per-notification value
      // and uses the channel's sound instead.
      sound:              _alarmSound,
      playSound:          true,
      // ── Vibration pattern ─────────────────────────────────────────
      // [delay, vibrate, pause, vibrate] in milliseconds.
      enableVibration:    true,
      vibrationPattern:   Int64List.fromList([0, 500, 200, 500]),
      // ── Misc ──────────────────────────────────────────────────────
      ongoing:            false,
      ticker:             'Time to take $medicineName',
      fullScreenIntent:   false,
    );

    final details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      baseId,
      'Medicine Reminder 💊',
      'Time to take $medicineName',
      _nextInstanceOfTime(hour, minute),
      details,
      payload:                 medicineName,
      androidScheduleMode:     AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.wallClockTime,
    );

    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[NotificationService] scheduleReminder failed: $e');
    return false;
  }
}

/// Returns the next [tz.TZDateTime] matching [hour]:[minute] in local time.
/// Advances to tomorrow if that time has already passed today.
tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local,
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  );
  if (scheduled.isBefore(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

// ── Cancel helpers ─────────────────────────────────────────────────────────

Future<void> cancelNotification(int id) async {
  await flutterLocalNotificationsPlugin.cancel(id);
}

Future<void> cancelAllNotifications() async {
  await flutterLocalNotificationsPlugin.cancelAll();
}

// ── Diagnostic helper (dev / debug only) ──────────────────────────────────

Future<List<PendingNotificationRequest>> getPendingNotifications() async {
  return flutterLocalNotificationsPlugin.pendingNotificationRequests();
}