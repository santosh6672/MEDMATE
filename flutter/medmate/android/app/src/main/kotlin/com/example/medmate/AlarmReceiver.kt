package com.example.medmate

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

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
class AlarmReceiver : BroadcastReceiver() {

    companion object {
        const val ALARM_CHANNEL_ID   = "medmate_alarms"
        const val ALARM_CHANNEL_NAME = "Medicine Alarms"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val medicine = intent.getStringExtra("medicine") ?: return
        val time     = intent.getLongExtra("time", 0L)

        ensureNotificationChannel(context)

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // ── Full-screen intent (launches AlarmActivity over lock screen) ───────
        val alarmActivityIntent = Intent(context, AlarmActivity::class.java).apply {
            putExtra("medicine", medicine)
            putExtra("time", time)
            putExtra("snoozeCount", intent.getIntExtra("snoozeCount", 0))
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val fullScreenPi = PendingIntent.getActivity(
            context,
            AlarmRepository.requestCode(medicine, time),
            alarmActivityIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, ALARM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm) // replace with your own icon
            .setContentTitle("💊 Medicine Reminder")
            .setContentText("Time to take: $medicine")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setAutoCancel(false)
            .setOngoing(true)
            .setContentIntent(fullScreenPi)

        // Android 14+ requires USE_FULL_SCREEN_INTENT to be user-granted.
        val canFullScreen = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            nm.canUseFullScreenIntent()
        } else {
            true
        }

        if (canFullScreen) {
            builder.setFullScreenIntent(fullScreenPi, true)
        }

        nm.notify(AlarmRepository.requestCode(medicine, time), builder.build())

        // IMPORTANT: Do NOT reschedule the next day's alarm here.
        // That is handled by AlarmActivity.dismissAlarm().
    }

    private fun ensureNotificationChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(ALARM_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ALARM_CHANNEL_ID,
            ALARM_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Full-screen medicine reminders"
            enableVibration(true)
            setBypassDnd(true)
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
        }
        nm.createNotificationChannel(channel)
    }
}