package com.example.medmate

import android.app.AlarmManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "alarm_channel"

    // Holds alarms that are waiting for SCHEDULE_EXACT_ALARM permission to be granted
    private val pendingAlarmQueue = mutableListOf<Pair<String, Long>>()

    companion object {
        private const val REQUEST_CODE_EXACT_ALARM = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "setAlarm" -> {
                        val medicine = call.argument<String>("medicine")
                            ?: return@setMethodCallHandler result.error(
                                "INVALID_ARG", "medicine is required", null
                            )
                        val time = call.argument<Long>("time")
                            ?: return@setMethodCallHandler result.error(
                                "INVALID_ARG", "time is required", null
                            )

                        if (time <= System.currentTimeMillis()) {
                            return@setMethodCallHandler result.error(
                                "INVALID_TIME", "Cannot schedule alarm in the past", null
                            )
                        }

                        handleSetAlarm(medicine, time)
                        result.success(true)
                    }

                    "cancelAlarmsForMedicine" -> {
                        val medicine = call.argument<String>("medicine")
                            ?: return@setMethodCallHandler result.error("INVALID_ARG", "medicine is required", null)
                        cancelAllAlarmsForMedicine(medicine)
                        result.success(true)
                    }

                    "cancelAllAlarms" -> {
                        cancelAllAlarms()
                        result.success(true)
                    }

                    "cancelAlarm" -> {
                        val medicine = call.argument<String>("medicine")
                            ?: return@setMethodCallHandler result.error(
                                "INVALID_ARG", "medicine is required", null
                            )
                        val time = call.argument<Long>("time")
                            ?: return@setMethodCallHandler result.error(
                                "INVALID_ARG", "time is required", null
                            )

                        AlarmScheduler.cancel(this, medicine, time)
                        AlarmRepository.remove(this, medicine, time)
                        result.success(true)
                    }

                    "requestBatteryOptimizationExemption" -> {
                        requestBatteryOptimizationExemption()
                        result.success(null)
                    }

                    "isExactAlarmPermissionGranted" -> {
                        result.success(AlarmScheduler.canScheduleExact(this))
                    }
                    
                    "requestExactAlarmPermission" -> {
                        requestExactAlarmPermission()
                        result.success(null)
                    }

                    "canUseFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                            result.success(nm.canUseFullScreenIntent())
                        } else {
                            result.success(true)
                        }
                    }

                    "requestFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    "isBatteryOptimizationExempt" -> {
                        val pm = getSystemService(PowerManager::class.java)
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ── Permission check + schedule ────────────────────────────────────────────

    private fun handleSetAlarm(medicine: String, time: Long) {
        if (!AlarmScheduler.canScheduleExact(this)) {
            // Queue the alarm and ask the user to grant the permission.
            pendingAlarmQueue.add(medicine to time)
            requestExactAlarmPermission()
            return
        }
        commitAlarm(medicine, time)
    }

    private fun commitAlarm(medicine: String, time: Long) {
        AlarmRepository.save(this, medicine, time)
        AlarmScheduler.schedule(this, medicine, time)
    }

    private fun drainPendingAlarmQueue() {
        if (!AlarmScheduler.canScheduleExact(this)) return   // still not granted
        val iterator = pendingAlarmQueue.iterator()
        while (iterator.hasNext()) {
            val (medicine, time) = iterator.next()
            commitAlarm(medicine, time)
            iterator.remove()
        }
    }

    private fun cancelAllAlarmsForMedicine(medicine: String) {
        val alarms = AlarmRepository.loadAll(this)
        alarms.forEach { entry ->
            if (entry.medicine == medicine) {
                AlarmScheduler.cancel(this, entry.medicine, entry.triggerTime)
                AlarmRepository.remove(this, entry.medicine, entry.triggerTime)
            }
        }
    }

    private fun cancelAllAlarms() {
        val alarms = AlarmRepository.loadAll(this)
        alarms.forEach { entry ->
            AlarmScheduler.cancel(this, entry.medicine, entry.triggerTime)
            AlarmRepository.remove(this, entry.medicine, entry.triggerTime)
        }
    }

    // ── System permission requests ─────────────────────────────────────────────

    private fun requestExactAlarmPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivityForResult(intent, REQUEST_CODE_EXACT_ALARM)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_EXACT_ALARM) {
            drainPendingAlarmQueue()
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
    private fun requestBatteryOptimizationExemption() {
        val pm = getSystemService(PowerManager::class.java)
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:$packageName")
            }
            startActivity(intent)
        }
    }
}