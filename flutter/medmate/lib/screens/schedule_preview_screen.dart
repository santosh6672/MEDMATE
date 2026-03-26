import 'package:flutter/material.dart';
import '../constants.dart';
import '../models/user_anchors.dart';
import '../models/med_config.dart';
import '../services/schedule_engine.dart';
import '../services/alarm_service.dart';
import '../services/reminder_storage.dart';

class SchedulePreviewScreen extends StatefulWidget {
  final List medicines;
  final UserAnchors anchors;
  final List<MedConfig> configs;

  const SchedulePreviewScreen({
    super.key,
    required this.medicines,
    required this.anchors,
    required this.configs,
  });

  @override
  State<SchedulePreviewScreen> createState() => _SchedulePreviewScreenState();
}

class _SchedulePreviewScreenState extends State<SchedulePreviewScreen> {
  late List<List<DateTime>> _computedTimes;
  late List<bool> _editedFlags;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _editedFlags = List.filled(widget.medicines.length, false);
    _computedTimes = [];

    for (int i = 0; i < widget.medicines.length; i++) {
      final cfg = widget.configs[i];
      final intent = cfg.intent;

      if (!cfg.useAutomatic || intent == null) {
        final manualTimes = <DateTime>[];
        if (cfg.firstDoseTime != null) {
          final now = DateTime.now();
          for (final t in cfg.allDoseTimes) {
            var alarmTime = DateTime(
                now.year, now.month, now.day, t.hour, t.minute);
            if (alarmTime.isBefore(now)) {
              alarmTime = alarmTime.add(const Duration(days: 1));
            }
            manualTimes.add(alarmTime);
          }
        }
        _computedTimes.add(manualTimes);
        continue;
      }

      final times = ScheduleEngine.computeAllTimes(
        dosesPerDay: cfg.dosesPerDay,
        gapHours: cfg.gapHours,
        intent: intent,
        anchors: widget.anchors,
      );
      _computedTimes.add(times);
    }
  }

  Future<void> _editTime(int medIndex, int doseIndex) async {
    final initialTime = _computedTimes[medIndex][doseIndex];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialTime),
    );
    if (picked != null) {
      final newTime = DateTime(
        initialTime.year,
        initialTime.month,
        initialTime.day,
        picked.hour,
        picked.minute,
      );
      setState(() {
        _computedTimes[medIndex][doseIndex] = newTime;
        _editedFlags[medIndex] = true;
      });
    }
  }

  Future<void> _saveSchedule() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    int saved = 0;
    final List<Map<String, dynamic>> toSave = [];

    for (int i = 0; i < widget.medicines.length; i++) {
      final med = widget.medicines[i];
      final cfg = widget.configs[i];
      final name = med['name'] ?? 'Unknown';
      final times = _computedTimes[i];

      for (int j = 0; j < times.length; j++) {
        final alarmTime = times[j];
        final success = await AlarmService.instance.setAlarm(
          medicine: name,
          time: alarmTime,
        );

        if (success) {
          final baseId =
              ('$name${alarmTime.hour}${alarmTime.minute}').hashCode.abs();
          toSave.add({
            'name': name,
            'hour': alarmTime.hour,
            'minute': alarmTime.minute,
            'baseId': baseId,
            'doseNumber': j + 1,
            'dosesPerDay': cfg.dosesPerDay,
            'foodTag': cfg.foodTag,
            'beforeBed': cfg.beforeBed,
            'taken': false,
            'nextAlarmTime': alarmTime.millisecondsSinceEpoch,
            'useAutomatic': cfg.useAutomatic,
            'intent': cfg.intent?.index,
            'overridden': _editedFlags[i],
            'overrideTime': _editedFlags[i]
                ? alarmTime.millisecondsSinceEpoch
                : null,
          });
          saved++;
        } else {
          debugPrint('Failed to schedule alarm for $name at $alarmTime');
        }
      }
    }

    if (toSave.isNotEmpty) {
      await ReminderStorage.saveReminders(toSave);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              saved > 0 ? Icons.check_circle_rounded : Icons.info_rounded,
              color: kWhite,
              size: 18,
            ),
            const SizedBox(width: 10),
            Text(
              saved > 0 ? '$saved reminder${saved == 1 ? '' : 's'} set!' : 'No reminders set',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: saved > 0 ? kAccent : Colors.grey,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(12),
      ),
    );

    if (saved > 0) Navigator.popUntil(context, (route) => route.isFirst);
  }

  int get _totalDoses =>
      _computedTimes.fold(0, (sum, times) => sum + times.length);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          'Review Schedule',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: kAccent,
        foregroundColor: kWhite,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Summary banner
          _SummaryBanner(
            medicineCount: widget.medicines.length,
            totalDoses: _totalDoses,
          ),

          // Medicine list
          Expanded(
            child: widget.medicines.isEmpty
                ? const Center(
                    child: Text(
                      'No medicines to schedule.',
                      style: TextStyle(color: kTextGrey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: widget.medicines.length,
                    itemBuilder: (context, i) {
                      final med = widget.medicines[i];
                      final times = _computedTimes[i];
                      final isEdited = _editedFlags[i];

                      return _MedicineScheduleCard(
                        index: i,
                        med: med,
                        times: times,
                        isEdited: isEdited,
                        onEditTime: (doseIndex) => _editTime(i, doseIndex),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _ConfirmBar(
        isSaving: _isSaving,
        totalDoses: _totalDoses,
        onConfirm: _saveSchedule,
      ),
    );
  }
}

// ── Summary Banner ─────────────────────────────────────────────────────────────

class _SummaryBanner extends StatelessWidget {
  final int medicineCount;
  final int totalDoses;

  const _SummaryBanner({
    required this.medicineCount,
    required this.totalDoses,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kAccent,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: kWhite.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_available_rounded,
                color: kWhite, size: 20),
            const SizedBox(width: 10),
            Text(
              '$totalDoses daily dose${totalDoses == 1 ? '' : 's'} across $medicineCount medicine${medicineCount == 1 ? '' : 's'}',
              style: const TextStyle(
                color: kWhite,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const Spacer(),
            const Text(
              'Tap time to edit',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Medicine Schedule Card ─────────────────────────────────────────────────────

class _MedicineScheduleCard extends StatelessWidget {
  final int index;
  final dynamic med;
  final List<DateTime> times;
  final bool isEdited;
  final ValueChanged<int> onEditTime;

  const _MedicineScheduleCard({
    required this.index,
    required this.med,
    required this.times,
    required this.isEdited,
    required this.onEditTime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: kAccent.withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: kAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: kAccent,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    med['name'] ?? 'Unknown Medicine',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: kTextDark,
                    ),
                  ),
                ),
                if (isEdited)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded,
                            size: 10, color: Colors.orange),
                        SizedBox(width: 3),
                        Text(
                          'Edited',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Doses
          if (times.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: kRed.withOpacity(0.7), size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'No times configured',
                    style: TextStyle(color: kRed, fontSize: 13),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(times.length, (doseIndex) {
                  final time = times[doseIndex];
                  final displayTime = TimeOfDay.fromDateTime(time)
                      .format(context);
                  return _DoseChip(
                    doseNumber: doseIndex + 1,
                    time: displayTime,
                    onTap: () => onEditTime(doseIndex),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Dose Chip ──────────────────────────────────────────────────────────────────

class _DoseChip extends StatelessWidget {
  final int doseNumber;
  final String time;
  final VoidCallback onTap;

  const _DoseChip({
    required this.doseNumber,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: kAccent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kAccent.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dose $doseNumber',
              style: TextStyle(
                fontSize: 10,
                color: kAccent.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_rounded,
                    size: 11, color: Colors.grey.shade400),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Confirm Bar ────────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  final bool isSaving;
  final int totalDoses;
  final VoidCallback onConfirm;

  const _ConfirmBar({
    required this.isSaving,
    required this.totalDoses,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: kWhite,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: isSaving ? null : onConfirm,
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kWhite,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_rounded,
                        color: kWhite, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm & Save $totalDoses Reminder${totalDoses == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kWhite,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}