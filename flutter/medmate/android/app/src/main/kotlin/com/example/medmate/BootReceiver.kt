package com.example.medmate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-schedules all stored alarms after a device reboot.
 *
 * AlarmManager clears all alarms on reboot — this receiver is the only
 * mechanism to restore them.  It runs in Direct Boot aware mode:
 *
 * Direct Boot (Android 7+)
 * ────────────────────────
 * ACTION_BOOT_COMPLETED is not delivered until the user unlocks the device
 * for the first time after reboot.  That is acceptable for a medicine reminder
 * app — if the phone just booted and has not been unlocked, the user is almost
 * certainly asleep and no alarm is imminent.  We therefore do NOT request
 * android:directBootAware in the manifest and simply rely on the standard boot
 * broadcast.  Document this decision so future maintainers don't "fix" it
 * incorrectly.
 *
 * Stale / past alarm guard
 * ────────────────────────
 * setExactAndAllowWhileIdle() with a past timestamp fires IMMEDIATELY.
 * We skip any alarm whose trigger time has already passed and remove it
 * from the repository so it never fires again.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return

        val now    = System.currentTimeMillis()
        val alarms = AlarmRepository.loadAll(context)

        for (entry in alarms) {
            if (entry.triggerTime <= now) {
                // Alarm was missed during the power-off window — remove it.
                // Optionally: persist a "missed" record here and notify the user.
                AlarmRepository.remove(context, entry.medicine, entry.triggerTime)
                continue
            }

            // Guard: only schedule if the system grants exact alarm permission.
            // (On Android < 12 this is always true; on 12+ it requires user grant.)
            if (!AlarmScheduler.canScheduleExact(context)) {
                // We cannot reschedule without the permission.
                // MainActivity will re-queue alarms when the user next opens the app.
                continue
            }

            AlarmScheduler.schedule(context, entry.medicine, entry.triggerTime)
        }
    }
}