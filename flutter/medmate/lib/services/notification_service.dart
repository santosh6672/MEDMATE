import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');

  const settings = InitializationSettings(android: android);

  await flutterLocalNotificationsPlugin.initialize(settings);
}

Future<void> scheduleReminder({
  required int baseId,
  required String medicineName,
  required int hour,
  required int minute,
}) async {
  const androidDetails = AndroidNotificationDetails(
    'med_channel',
    'Medicine Reminders',
    importance: Importance.max,
    priority: Priority.high,
  );

  const details = NotificationDetails(android: androidDetails);

  await flutterLocalNotificationsPlugin.show(
    baseId,
    'Medicine Reminder',
    'Time to take $medicineName',
    details,
  );
}

Future<void> cancelAllNotifications() async {
  await flutterLocalNotificationsPlugin.cancelAll();
}