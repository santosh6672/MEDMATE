package com.example.medmate;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * Single source of truth for AlarmManager interactions.
 *
 * All call sites (MainActivity, BootReceiver, AlarmActivity snooze) go through here
 * so that request-code generation and PendingIntent flags are never duplicated.
 */
public class AlarmScheduler {

    // ── Permission guard ──────────────────────────────────────────────────────

    public static boolean canScheduleExact(Context context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        return am != null && am.canScheduleExactAlarms();
    }

    // ── Schedule ──────────────────────────────────────────────────────────────

    /**
     * Schedules (or replaces) an exact, Doze-penetrating alarm.
     * Safe to call on all API levels from 21 → 36 (Android 16).
     */
    public static void schedule(Context context, String medicine, long time) {
        if (!canScheduleExact(context)) return; // caller must have checked first

        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                time,
                buildPendingIntent(context, medicine, time)
        );
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    public static void cancel(Context context, String medicine, long time) {
        AlarmManager am = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.cancel(buildPendingIntent(context, medicine, time));
    }

    // ── PendingIntent factory ─────────────────────────────────────────────────

    /**
     * Reconstructs the exact same PendingIntent that was used to schedule the alarm.
     * Must be byte-for-byte identical (action, component, extras, request code) for
     * AlarmManager.cancel() to work correctly.
     */
    public static PendingIntent buildPendingIntent(Context context, String medicine, long time) {
        Intent intent = new Intent(context, AlarmReceiver.class);
        intent.putExtra("medicine", medicine);
        intent.putExtra("time", time);
        return PendingIntent.getBroadcast(
                context,
                AlarmRepository.requestCode(medicine, time),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }
}