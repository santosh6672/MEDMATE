package com.example.medmate

import android.content.Context
import kotlin.math.abs

/**
 * Thin persistence layer for scheduled alarms.
 *
 * Key design decisions
 * ─────────────────────
 * • Composite key  →  "<medicine>|<time>"  prevents one-alarm-per-medicine overwrite bug.
 * • Request-code   →  stored alongside the alarm so BootReceiver and cancellation
 *                     always reconstruct the exact same PendingIntent request code.
 * • No Room dependency here — a simple, auditable SharedPreferences store is fine for
 *   ≤ ~100 alarms. Swap to Room if you need querying, pagination, or missed-alarm history.
 */
object AlarmRepository {

    private const val PREFS_NAME = "alarms_v2"  // bump version to avoid stale v1 data

    // ── Write ─────────────────────────────────────────────────────────────────

    fun save(context: Context, medicine: String, time: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putLong(compositeKey(medicine, time), time)
            .apply()
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /**
     * Returns all stored alarms as a list of (medicine, triggerTimeMs) pairs.
     * The raw pref key encodes both fields; we split on the separator to recover them.
     */
    fun loadAll(context: Context): List<AlarmEntry> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.all.mapNotNull { (key, value) ->
            val parts = key.split("|", limit = 2)
            if (parts.size == 2 && value is Long) {
                AlarmEntry(
                    medicine    = parts[0],
                    triggerTime = value,
                    requestCode = requestCode(parts[0], value)
                )
            } else null
        }
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    fun remove(context: Context, medicine: String, time: Long) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(compositeKey(medicine, time))
            .apply()
    }

    fun removeAll(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun compositeKey(medicine: String, time: Long) = "$medicine|$time"

    /**
     * Collision-resistant PendingIntent request code.
     *
     * Pure String.hashCode() is 32-bit and causes collisions for large alarm sets.
     * XOR-mixing the lower 16 bits of the timestamp spreads the distribution
     * without wrapping into negative territory (abs guards that).
     */
    fun requestCode(medicine: String, time: Long): Int =
        abs(compositeKey(medicine, time).hashCode() xor (time and 0xFFFF).toInt())

    // ── Data class ────────────────────────────────────────────────────────────

    data class AlarmEntry(
        val medicine: String,
        val triggerTime: Long,
        val requestCode: Int
    )
}