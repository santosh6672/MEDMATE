package com.example.medmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Single source of truth for AlarmManager interactions.
 *
 * All call sites (MainActivity, BootReceiver, AlarmActivity snooze) go through here
 * so that request-code generation and PendingIntent flags are never duplicated.
 */
object AlarmScheduler {

    // ── Permission guard ──────────────────────────────────────────────────────

    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    // ── Schedule ──────────────────────────────────────────────────────────────

    /**
     * Schedules (or replaces) an exact, Doze-penetrating alarm.
     * Safe to call on all API levels from 21 → 36 (Android 16).
     */
    fun schedule(context: Context, medicine: String, time: Long) {
        if (!canScheduleExact(context)) return    // caller must have checked first

        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            time,
            buildPendingIntent(context, medicine, time)
        )
    }

    // ── Cancel ────────────────────────────────────────────────────────────────

    fun cancel(context: Context, medicine: String, time: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(buildPendingIntent(context, medicine, time))
    }

    // ── PendingIntent factory ─────────────────────────────────────────────────

    /**
     * Reconstructs the exact same PendingIntent that was used to schedule the alarm.
     * Must be byte-for-byte identical (action, component, extras, request code) for
     * AlarmManager.cancel() to work correctly.
     */
    fun buildPendingIntent(context: Context, medicine: String, time: Long): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra("medicine", medicine)
            putExtra("time", time)
        }
        return PendingIntent.getBroadcast(
            context,
            AlarmRepository.requestCode(medicine, time),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}