package com.example.medmate;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

import androidx.core.app.NotificationCompat;

/**
 * Receives the AlarmManager broadcast and surfaces the alarm to the user.
 *
 * Why a Notification + fullScreenIntent instead of startActivity() directly
 * ──────────────────────────────────────────────────────────────────────────
 * • Android 10+ restricts background Activity launches; a BroadcastReceiver
 *   context is considered background even within its short execution window on
 *   Android 14+.
 * • The correct pattern — used by AOSP Clock and all production alarm apps — is
 *   to post a Notification whose fullScreenIntent points at AlarmActivity.
 *   The system then decides: if the device is locked/off → full-screen launch;
 *   if the user is actively using the phone → heads-up notification with an
 *   action to open the alarm. Either way the user is notified.
 * • USE_FULL_SCREEN_INTENT requires explicit user grant on Android 14+.
 *   We check canUseFullScreenIntent() and fall back to a high-priority
 *   heads-up notification if the permission is missing.
 */
public class AlarmReceiver extends BroadcastReceiver {

    public static final String ALARM_CHANNEL_ID   = "medmate_alarms";
    public static final String ALARM_CHANNEL_NAME = "Medicine Alarms";

    @Override
    public void onReceive(Context context, Intent intent) {
        String medicine = intent.getStringExtra("medicine");
        if (medicine == null) return;
        long time = intent.getLongExtra("time", 0L);

        ensureNotificationChannel(context);

        NotificationManager nm = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;

        // ── Full-screen intent (launches AlarmActivity over lock screen) ───────
        Intent alarmActivityIntent = new Intent(context, AlarmActivity.class);
        alarmActivityIntent.putExtra("medicine", medicine);
        alarmActivityIntent.putExtra("time", time);
        alarmActivityIntent.putExtra("snoozeCount", intent.getIntExtra("snoozeCount", 0));
        alarmActivityIntent.setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK |
                Intent.FLAG_ACTIVITY_CLEAR_TOP |
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        );

        PendingIntent fullScreenPi = PendingIntent.getActivity(
                context,
                AlarmRepository.requestCode(medicine, time),
                alarmActivityIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, ALARM_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm) // replace with your own icon
                .setContentTitle("💊 Medicine Reminder")
                .setContentText("Time to take: " + medicine)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(false)
                .setOngoing(true)
                .setContentIntent(fullScreenPi);

        // Android 14+ requires USE_FULL_SCREEN_INTENT to be user-granted.
        boolean canFullScreen;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            canFullScreen = nm.canUseFullScreenIntent();
        } else {
            canFullScreen = true;
        }

        if (canFullScreen) {
            builder.setFullScreenIntent(fullScreenPi, true);
        }

        nm.notify(AlarmRepository.requestCode(medicine, time), builder.build());

        // IMPORTANT: Do NOT reschedule the next day's alarm here.
        // That is handled by AlarmActivity.dismissAlarm().
    }

    private void ensureNotificationChannel(Context context) {
        NotificationManager nm = (NotificationManager)
                context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null) return;
        if (nm.getNotificationChannel(ALARM_CHANNEL_ID) != null) return;

        NotificationChannel channel = new NotificationChannel(
                ALARM_CHANNEL_ID,
                ALARM_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription("Full-screen medicine reminders");
        channel.enableVibration(true);
        channel.setBypassDnd(true);
        channel.setLockscreenVisibility(NotificationCompat.VISIBILITY_PUBLIC);
        nm.createNotificationChannel(channel);
    }
}