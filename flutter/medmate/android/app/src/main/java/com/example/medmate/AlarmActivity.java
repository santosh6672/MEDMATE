package com.example.medmate;

import android.app.Activity;
import android.app.AlarmManager;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.provider.Settings;
import android.speech.tts.TextToSpeech;
import android.view.WindowManager;
import android.view.animation.AnimationUtils;
import android.widget.Button;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.Calendar;
import java.util.Locale;

public class AlarmActivity extends Activity {

    private static final long SNOOZE_DURATION_MS = 5 * 60 * 1000L;
    private static final int  MAX_SNOOZE_COUNT   = 3;
    private static final long[] VIBRATION_PATTERN = {0, 500, 1000};

    private MediaPlayer mediaPlayer;
    private Vibrator    vibrator;
    private PowerManager.WakeLock wakeLock;
    private TextToSpeech tts;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        acquireWakeLock();
        configureWindowFlags();
        setContentView(R.layout.activity_alarm);

        String medicine   = getIntent().getStringExtra("medicine");
        if (medicine == null) medicine = "Medicine";
        int snoozeCount   = getIntent().getIntExtra("snoozeCount", 0);

        ((TextView) findViewById(R.id.title)).setText(medicine);
        ((TextView) findViewById(R.id.timeText)).setText("Time to take " + medicine);

        TextView icon = findViewById(R.id.medicineIcon);
        icon.startAnimation(AnimationUtils.loadAnimation(this, R.anim.pulse));

        startAlarm();
        initTTS(medicine);

        final String finalMedicine = medicine;

        // TAKEN button
        findViewById(R.id.takenBtn).setOnClickListener(v -> markMedicineTaken(finalMedicine));

        // Snooze button
        Button snoozeBtn = findViewById(R.id.snoozeBtn);
        if (snoozeCount >= MAX_SNOOZE_COUNT) {
            snoozeBtn.setEnabled(false);
            snoozeBtn.setText("No more snoozes");
        } else {
            final int finalSnoozeCount = snoozeCount;
            snoozeBtn.setOnClickListener(v -> snoozeAlarm(finalMedicine, finalSnoozeCount));
        }

        // DISMISS (Skip) button
        findViewById(R.id.dismissBtn).setOnClickListener(v -> dismissAlarm(finalMedicine));
    }

    private void initTTS(String medicine) {
        final String msg = "Time to take " + medicine;
        tts = new TextToSpeech(this, status -> {
            if (status == TextToSpeech.SUCCESS) {
                tts.setLanguage(Locale.US);
                tts.speak(msg, TextToSpeech.QUEUE_FLUSH, null, null);
            }
        });
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        stopAlarm();
        if (tts != null) {
            tts.stop();
            tts.shutdown();
        }
    }

    // ── Wake lock ─────────────────────────────────────────────────────────────

    private void acquireWakeLock() {
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "AlarmActivity::wakeLock");
        wakeLock.acquire(10 * 60 * 1000L); // 10 minutes max
    }

    private void releaseWakeLock() {
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        wakeLock = null;
    }

    // ── Window flags ──────────────────────────────────────────────────────────

    private void configureWindowFlags() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true);
            setTurnScreenOn(true);
        }
        //noinspection deprecation
        getWindow().addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON |
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
        );
    }

    // ── Alarm audio / vibration ───────────────────────────────────────────────

    private void startAlarm() {
        setMaxAlarmVolume();
        startSound();
        startVibration();
    }

    private void setMaxAlarmVolume() {
        AudioManager am = (AudioManager) getSystemService(AUDIO_SERVICE);
        if (am == null) return;
        am.setStreamVolume(
                AudioManager.STREAM_ALARM,
                am.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                0
        );
    }

    private void startSound() {
        Uri alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
        if (alarmUri == null) alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
        if (alarmUri == null) alarmUri = Settings.System.DEFAULT_ALARM_ALERT_URI;

        AudioAttributes audioAttributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();

        try {
            mediaPlayer = new MediaPlayer();
            mediaPlayer.setAudioAttributes(audioAttributes);
            mediaPlayer.setDataSource(this, alarmUri);
            mediaPlayer.setLooping(true);
            mediaPlayer.prepare();
            mediaPlayer.start();
        } catch (Exception e) {
            mediaPlayer = null;
            try {
                RingtoneManager.getRingtone(this, alarmUri).play();
            } catch (Exception ignored) { /* silent failure */ }
        }
    }

    private void startVibration() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager vm = (VibratorManager) getSystemService(VIBRATOR_MANAGER_SERVICE);
            vibrator = vm != null ? vm.getDefaultVibrator() : null;
        } else {
            //noinspection deprecation
            vibrator = (Vibrator) getSystemService(VIBRATOR_SERVICE);
        }
        if (vibrator != null) {
            vibrator.vibrate(VibrationEffect.createWaveform(VIBRATION_PATTERN, 0));
        }
    }

    private void stopAlarm() {
        releaseWakeLock();
        try {
            if (mediaPlayer != null) {
                mediaPlayer.stop();
                mediaPlayer.release();
            }
        } catch (Exception ignored) { }
        mediaPlayer = null;

        if (vibrator != null) vibrator.cancel();
        vibrator = null;
    }

    // ── Actions ───────────────────────────────────────────────────────────────

    private void dismissAlarm(String medicine) {
        stopAlarm();
        cancelOngoingNotification();

        long originalTime = getIntent().getLongExtra("time", 0L);
        long nextTime     = originalTime + 24 * 60 * 60 * 1000L;

        AlarmRepository.remove(this, medicine, originalTime);
        AlarmRepository.save(this, medicine, nextTime);

        if (AlarmScheduler.canScheduleExact(this)) {
            AlarmScheduler.schedule(this, medicine, nextTime);
        }
        finish();
    }

    private void snoozeAlarm(String medicine, int currentSnoozeCount) {
        long originalTime    = getIntent().getLongExtra("time", 0L);
        long snoozeTime      = System.currentTimeMillis() + SNOOZE_DURATION_MS;
        int  nextSnoozeCount = currentSnoozeCount + 1;

        AlarmScheduler.cancel(this, medicine, originalTime);
        AlarmRepository.remove(this, medicine, originalTime);
        AlarmRepository.save(this, medicine, snoozeTime);

        if (AlarmScheduler.canScheduleExact(this)) {
            Intent intent = new Intent(this, AlarmReceiver.class);
            intent.putExtra("medicine", medicine);
            intent.putExtra("time", snoozeTime);
            intent.putExtra("snoozeCount", nextSnoozeCount);

            PendingIntent pi = PendingIntent.getBroadcast(
                    this,
                    AlarmRepository.requestCode(medicine, snoozeTime),
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );
            AlarmManager am = (AlarmManager) getSystemService(ALARM_SERVICE);
            if (am != null) {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, snoozeTime, pi);
            }
        }

        stopAlarm();
        cancelOngoingNotification();
        finish();
    }

    private void cancelOngoingNotification() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (nm == null) return;
        long time = getIntent().getLongExtra("time", 0L);
        if (time != 0L) {
            String medicine = getIntent().getStringExtra("medicine");
            if (medicine == null) medicine = "";
            nm.cancel(AlarmRepository.requestCode(medicine, time));
        }
    }

    private void markMedicineTaken(String medicine) {
        stopAlarm();
        cancelOngoingNotification();
        updateReminderTakenStatus(medicine);

        long originalTime = getIntent().getLongExtra("time", 0L);
        long nextTime     = originalTime + 24 * 60 * 60 * 1000L;

        AlarmRepository.remove(this, medicine, originalTime);
        AlarmRepository.save(this, medicine, nextTime);

        if (AlarmScheduler.canScheduleExact(this)) {
            AlarmScheduler.schedule(this, medicine, nextTime);
        }
        finish();
    }

    private void updateReminderTakenStatus(String medicineName) {
        // Flutter's shared_preferences plugin stores data in "FlutterSharedPreferences"
        android.content.SharedPreferences prefs =
                getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        String key    = "flutter.scheduled_medicines"; // standard key prefix for the plugin
        String jsonStr = prefs.getString(key, null);
        if (jsonStr == null) return;

        try {
            JSONArray jsonArray  = new JSONArray(jsonStr);
            long originalTime    = getIntent().getLongExtra("time", 0L);

            Calendar calendar = Calendar.getInstance();
            calendar.setTimeInMillis(originalTime);
            int targetHour   = calendar.get(Calendar.HOUR_OF_DAY);
            int targetMinute = calendar.get(Calendar.MINUTE);

            boolean modified = false;
            for (int i = 0; i < jsonArray.length(); i++) {
                JSONObject item   = jsonArray.getJSONObject(i);
                String name       = item.getString("name");
                int    hour       = item.getInt("hour");
                int    minute     = item.getInt("minute");

                if (name.equals(medicineName) && hour == targetHour && minute == targetMinute) {
                    item.put("taken", true);
                    modified = true;
                    break;
                }
            }

            if (modified) {
                // Apply changes to Flutter's storage
                prefs.edit().putString(key, jsonArray.toString()).apply();

                // Also update the backup/fallback just in case
                getSharedPreferences("reminder_storage", Context.MODE_PRIVATE)
                        .edit()
                        .putString("scheduled_medicines", jsonArray.toString())
                        .apply();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}