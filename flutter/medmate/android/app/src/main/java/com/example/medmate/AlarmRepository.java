package com.example.medmate;

import android.content.Context;
import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

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
public class AlarmRepository {

    private static final String PREFS_NAME = "alarms_v2"; // bump version to avoid stale v1 data

    // ── Write ─────────────────────────────────────────────────────────────────

    public static void save(Context context, String medicine, long time) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(compositeKey(medicine, time), time)
                .apply();
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /**
     * Returns all stored alarms as a list of AlarmEntry objects.
     * The raw pref key encodes both fields; we split on the separator to recover them.
     */
    public static List<AlarmEntry> loadAll(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        Map<String, ?> all = prefs.getAll();
        List<AlarmEntry> entries = new ArrayList<>();

        for (Map.Entry<String, ?> entry : all.entrySet()) {
            String key = entry.getKey();
            Object value = entry.getValue();
            String[] parts = key.split("\\|", 2);
            if (parts.length == 2 && value instanceof Long) {
                long triggerTime = (Long) value;
                entries.add(new AlarmEntry(parts[0], triggerTime, requestCode(parts[0], triggerTime)));
            }
        }
        return entries;
    }

    // ── Delete ────────────────────────────────────────────────────────────────

    public static void remove(Context context, String medicine, long time) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(compositeKey(medicine, time))
                .apply();
    }

    public static void removeAll(Context context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .clear()
                .apply();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String compositeKey(String medicine, long time) {
        return medicine + "|" + time;
    }

    /**
     * Collision-resistant PendingIntent request code.
     *
     * Pure String.hashCode() is 32-bit and causes collisions for large alarm sets.
     * XOR-mixing the lower 16 bits of the timestamp spreads the distribution
     * without wrapping into negative territory (Math.abs guards that).
     */
    public static int requestCode(String medicine, long time) {
        return Math.abs(compositeKey(medicine, time).hashCode() ^ (int) (time & 0xFFFFL));
    }

    // ── Data class ────────────────────────────────────────────────────────────

    public static class AlarmEntry {
        public final String medicine;
        public final long triggerTime;
        public final int requestCode;

        public AlarmEntry(String medicine, long triggerTime, int requestCode) {
            this.medicine = medicine;
            this.triggerTime = triggerTime;
            this.requestCode = requestCode;
        }
    }
}