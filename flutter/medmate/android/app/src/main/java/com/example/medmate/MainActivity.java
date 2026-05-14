package com.example.medmate;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.PowerManager;
import android.provider.Settings;

import java.util.ArrayList;
import java.util.List;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {

    private static final String CHANNEL                  = "alarm_channel";
    private static final int    REQUEST_CODE_EXACT_ALARM = 1001;

    // Holds alarms that are waiting for SCHEDULE_EXACT_ALARM permission to be granted
    private final List<long[]> pendingAlarmQueue = new ArrayList<>();
    // Each entry: [medicine hashCode, time] — we store medicine as a parallel list
    private final List<String> pendingMedicines  = new ArrayList<>();

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {

                        case "setAlarm": {
                            String medicine = call.argument("medicine");
                            Long   time     = call.argument("time");

                            if (medicine == null) {
                                result.error("INVALID_ARG", "medicine is required", null);
                                return;
                            }
                            if (time == null) {
                                result.error("INVALID_ARG", "time is required", null);
                                return;
                            }
                            if (time <= System.currentTimeMillis()) {
                                result.error("INVALID_TIME", "Cannot schedule alarm in the past", null);
                                return;
                            }
                            handleSetAlarm(medicine, time);
                            result.success(true);
                            break;
                        }

                        case "cancelAlarmsForMedicine": {
                            String medicine = call.argument("medicine");
                            if (medicine == null) {
                                result.error("INVALID_ARG", "medicine is required", null);
                                return;
                            }
                            cancelAllAlarmsForMedicine(medicine);
                            result.success(true);
                            break;
                        }

                        case "cancelAllAlarms": {
                            cancelAllAlarms();
                            result.success(true);
                            break;
                        }

                        case "cancelAlarm": {
                            String medicine = call.argument("medicine");
                            Long   time     = call.argument("time");
                            if (medicine == null) {
                                result.error("INVALID_ARG", "medicine is required", null);
                                return;
                            }
                            if (time == null) {
                                result.error("INVALID_ARG", "time is required", null);
                                return;
                            }
                            AlarmScheduler.cancel(this, medicine, time);
                            AlarmRepository.remove(this, medicine, time);
                            result.success(true);
                            break;
                        }

                        case "requestBatteryOptimizationExemption": {
                            requestBatteryOptimizationExemption();
                            result.success(null);
                            break;
                        }

                        case "isExactAlarmPermissionGranted": {
                            result.success(AlarmScheduler.canScheduleExact(this));
                            break;
                        }

                        case "requestExactAlarmPermission": {
                            requestExactAlarmPermission();
                            result.success(null);
                            break;
                        }

                        case "canUseFullScreenIntent": {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                android.app.NotificationManager nm =
                                        (android.app.NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
                                result.success(nm != null && nm.canUseFullScreenIntent());
                            } else {
                                result.success(true);
                            }
                            break;
                        }

                        case "requestFullScreenIntent": {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT);
                                intent.setData(Uri.parse("package:" + getPackageName()));
                                startActivity(intent);
                            }
                            result.success(null);
                            break;
                        }

                        case "isBatteryOptimizationExempt": {
                            PowerManager pm = getSystemService(PowerManager.class);
                            result.success(pm != null && pm.isIgnoringBatteryOptimizations(getPackageName()));
                            break;
                        }

                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    // ── Permission check + schedule ────────────────────────────────────────────

    private void handleSetAlarm(String medicine, long time) {
        if (!AlarmScheduler.canScheduleExact(this)) {
            // Queue the alarm and ask the user to grant the permission.
            pendingMedicines.add(medicine);
            pendingAlarmQueue.add(new long[]{time});
            requestExactAlarmPermission();
            return;
        }
        commitAlarm(medicine, time);
    }

    private void commitAlarm(String medicine, long time) {
        AlarmRepository.save(this, medicine, time);
        AlarmScheduler.schedule(this, medicine, time);
    }

    private void drainPendingAlarmQueue() {
        if (!AlarmScheduler.canScheduleExact(this)) return; // still not granted
        for (int i = 0; i < pendingMedicines.size(); i++) {
            commitAlarm(pendingMedicines.get(i), pendingAlarmQueue.get(i)[0]);
        }
        pendingMedicines.clear();
        pendingAlarmQueue.clear();
    }

    private void cancelAllAlarmsForMedicine(String medicine) {
        List<AlarmRepository.AlarmEntry> alarms = AlarmRepository.loadAll(this);
        for (AlarmRepository.AlarmEntry entry : alarms) {
            if (entry.medicine.equals(medicine)) {
                AlarmScheduler.cancel(this, entry.medicine, entry.triggerTime);
                AlarmRepository.remove(this, entry.medicine, entry.triggerTime);
            }
        }
    }

    private void cancelAllAlarms() {
        List<AlarmRepository.AlarmEntry> alarms = AlarmRepository.loadAll(this);
        for (AlarmRepository.AlarmEntry entry : alarms) {
            AlarmScheduler.cancel(this, entry.medicine, entry.triggerTime);
            AlarmRepository.remove(this, entry.medicine, entry.triggerTime);
        }
    }

    // ── System permission requests ─────────────────────────────────────────────

    private void requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent intent = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivityForResult(intent, REQUEST_CODE_EXACT_ALARM);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_CODE_EXACT_ALARM) {
            drainPendingAlarmQueue();
        }
    }

    /**
     * Guides the user to the system battery-optimisation exemption screen.
     * This is the single most effective reliability improvement for OEM devices
     * (Xiaomi MIUI, Realme ColorOS, Samsung OneUI "Sleeping Apps", etc.).
     *
     * Requires  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"/>
     * in AndroidManifest.xml.
     */
    private void requestBatteryOptimizationExemption() {
        PowerManager pm = getSystemService(PowerManager.class);
        if (pm != null && !pm.isIgnoringBatteryOptimizations(getPackageName())) {
            Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
            intent.setData(Uri.parse("package:" + getPackageName()));
            startActivity(intent);
        }
    }
}