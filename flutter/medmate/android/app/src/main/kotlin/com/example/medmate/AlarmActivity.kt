package com.example.medmate

import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.view.WindowManager
import android.view.animation.AnimationUtils
import android.widget.Button
import android.widget.TextView
import android.speech.tts.TextToSpeech
import java.util.Locale
import org.json.JSONArray
import org.json.JSONObject
import androidx.core.app.NotificationCompat

class AlarmActivity : Activity() {

    companion object {
        private const val SNOOZE_DURATION_MS = 5 * 60 * 1000L
        private const val MAX_SNOOZE_COUNT = 3
        private val VIBRATION_PATTERN = longArrayOf(0, 500, 1000)
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        acquireWakeLock()

        configureWindowFlags()
        setContentView(R.layout.activity_alarm)

        val medicine = intent.getStringExtra("medicine") ?: "Medicine"
        val snoozeCount = intent.getIntExtra("snoozeCount", 0)

        findViewById<TextView>(R.id.title).text = medicine
        findViewById<TextView>(R.id.timeText).text = "Time to take $medicine"

        val icon = findViewById<TextView>(R.id.medicineIcon)
        icon.startAnimation(AnimationUtils.loadAnimation(this, R.anim.pulse))

        startAlarm()
        initTTS(medicine)

        // TAKEN button
        findViewById<Button>(R.id.takenBtn).setOnClickListener {
            markMedicineTaken(medicine)
        }

        // Snooze button
        val snoozeBtn = findViewById<Button>(R.id.snoozeBtn)
        if (snoozeCount >= MAX_SNOOZE_COUNT) {
            snoozeBtn.isEnabled = false
            snoozeBtn.text = "No more snoozes"
        } else {
            snoozeBtn.setOnClickListener {
                snoozeAlarm(medicine, snoozeCount)
            }
        }

        // DISMISS (now "Skip") button
        findViewById<Button>(R.id.dismissBtn).setOnClickListener {
            dismissAlarm(medicine)
        }
    }

    private var tts: TextToSpeech? = null

    private fun initTTS(medicine: String) {
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
                tts?.speak("Time to take $medicine", TextToSpeech.QUEUE_FLUSH, null, null)
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAlarm()
        tts?.stop()
        tts?.shutdown()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AlarmActivity::wakeLock")
        wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes max
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun configureWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        }
        @Suppress("DEPRECATION")
        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        )
    }

    private fun startAlarm() {
        setMaxAlarmVolume()
        startSound()
        startVibration()
    }

    private fun setMaxAlarmVolume() {
        val am = getSystemService(AUDIO_SERVICE) as AudioManager
        am.setStreamVolume(
            AudioManager.STREAM_ALARM,
            am.getStreamMaxVolume(AudioManager.STREAM_ALARM),
            0
        )
    }

    private fun startSound() {
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: Settings.System.DEFAULT_ALARM_ALERT_URI

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        mediaPlayer = try {
            MediaPlayer().apply {
                setAudioAttributes(audioAttributes)
                setDataSource(this@AlarmActivity, alarmUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            try {
                RingtoneManager.getRingtone(this, alarmUri)?.apply { play() }
            } catch (_: Exception) { /* silent failure */ }
            null
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as Vibrator
        }
        vibrator?.vibrate(
            VibrationEffect.createWaveform(VIBRATION_PATTERN, 0)
        )
    }

    private fun stopAlarm() {
        releaseWakeLock()

        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
        } catch (_: Exception) { }
        mediaPlayer = null

        vibrator?.cancel()
        vibrator = null
    }

    private fun dismissAlarm(medicine: String) {
        stopAlarm()
        cancelOngoingNotification()

        val originalTime = intent.getLongExtra("time", 0L)
        val nextTime = originalTime + 24 * 60 * 60 * 1000L

        AlarmRepository.remove(this, medicine, originalTime)
        AlarmRepository.save(this, medicine, nextTime)

        if (AlarmScheduler.canScheduleExact(this)) {
            AlarmScheduler.schedule(this, medicine, nextTime)
        }

        finish()
    }

    private fun snoozeAlarm(medicine: String, currentSnoozeCount: Int) {
        val originalTime = intent.getLongExtra("time", 0L)
        val snoozeTime = System.currentTimeMillis() + SNOOZE_DURATION_MS
        val nextSnoozeCount = currentSnoozeCount + 1

        AlarmScheduler.cancel(this, medicine, originalTime)
        AlarmRepository.remove(this, medicine, originalTime)

        AlarmRepository.save(this, medicine, snoozeTime)

        if (AlarmScheduler.canScheduleExact(this)) {
            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("medicine", medicine)
                putExtra("time", snoozeTime)
                putExtra("snoozeCount", nextSnoozeCount)
            }
            val pi = PendingIntent.getBroadcast(
                this,
                AlarmRepository.requestCode(medicine, snoozeTime),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            (getSystemService(ALARM_SERVICE) as AlarmManager)
                .setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, snoozeTime, pi)
        }

        stopAlarm()
        cancelOngoingNotification()
        finish()
    }

    private fun cancelOngoingNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val time = intent.getLongExtra("time", 0L)
        if (time != 0L) {
            nm.cancel(AlarmRepository.requestCode(intent.getStringExtra("medicine") ?: "", time))
        }
    }

    private fun markMedicineTaken(medicine: String) {
        stopAlarm()
        cancelOngoingNotification()

        // Update the taken flag in the reminder storage
        updateReminderTakenStatus(medicine)

        // Reschedule for tomorrow (like dismiss)
        val originalTime = intent.getLongExtra("time", 0L)
        val nextTime = originalTime + 24 * 60 * 60 * 1000L

        AlarmRepository.remove(this, medicine, originalTime)
        AlarmRepository.save(this, medicine, nextTime)

        if (AlarmScheduler.canScheduleExact(this)) {
            AlarmScheduler.schedule(this, medicine, nextTime)
        }

        finish()
    }

    private fun updateReminderTakenStatus(medicineName: String) {
        // Flutter's shared_preferences plugin stores data in "FlutterSharedPreferences"
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = "flutter.scheduled_medicines"   // standard key prefix for the plugin
        val jsonStr = prefs.getString(key, null) ?: return

        try {
            val jsonArray = JSONArray(jsonStr)
            val originalTime = intent.getLongExtra("time", 0L)

            // Convert the alarm timestamp to local hour/minute
            val calendar = java.util.Calendar.getInstance()
            calendar.timeInMillis = originalTime
            val targetHour = calendar.get(java.util.Calendar.HOUR_OF_DAY)
            val targetMinute = calendar.get(java.util.Calendar.MINUTE)

            var modified = false
            for (i in 0 until jsonArray.length()) {
                val item = jsonArray.getJSONObject(i)
                val name = item.getString("name")
                val hour = item.getInt("hour")
                val minute = item.getInt("minute")

                // Match exact medicine and time (hour/minute)
                if (name == medicineName && hour == targetHour && minute == targetMinute) {
                    item.put("taken", true)
                    modified = true
                    break
                }
            }

            if (modified) {
                // Apply changes to Flutter's storage
                prefs.edit().putString(key, jsonArray.toString()).apply()
                
                // Also update the backup/fallback just in case
                getSharedPreferences("reminder_storage", Context.MODE_PRIVATE)
                    .edit()
                    .putString("scheduled_medicines", jsonArray.toString())
                    .apply()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}