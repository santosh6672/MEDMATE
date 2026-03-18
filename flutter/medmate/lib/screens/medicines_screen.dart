import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants.dart';
import '../services/reminder_storage.dart';
import '../services/notification_service.dart';

// No API call — receives medicines passed from UploadScreen or PrescriptionsListScreen
// Data shape: [ { "name", "dosage", "frequency" }, ... ]

class MedicinesScreen extends StatefulWidget {
  final List medicines;
  const MedicinesScreen({super.key, required this.medicines});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

// ── Per-medicine schedule config ──────────────────────────────────────────────
class _MedConfig {
  int dosesPerDay;
  int gapHours;
  TimeOfDay? firstDoseTime;
  String foodTag;       // "With food" | "Empty stomach" | "No preference"
  bool beforeBed;       // snap last dose to bedtime
  TimeOfDay bedtime;    // only used when beforeBed = true
  String maxDoseInput;  // free-text mg value for warning check

  _MedConfig({
    required this.dosesPerDay,
    required this.gapHours,
    this.firstDoseTime,
    this.foodTag = "No preference",
    this.beforeBed = false,
    this.bedtime = const TimeOfDay(hour: 22, minute: 0),
    this.maxDoseInput = "",
  });

  // ── All dose times, respecting Before Bed override on last slot ──────────
  List<TimeOfDay> get allDoseTimes {
    if (firstDoseTime == null) return [];
    final times = List.generate(dosesPerDay, (i) {
      final totalMinutes =
          firstDoseTime!.hour * 60 + firstDoseTime!.minute + i * gapHours * 60;
      return TimeOfDay(
        hour: (totalMinutes ~/ 60) % 24,
        minute: totalMinutes % 60,
      );
    });
    // Override last slot with bedtime when beforeBed is on
    if (beforeBed && dosesPerDay > 1) {
      times[times.length - 1] = bedtime;
    }
    return times;
  }

  // ── Max dose warning ──────────────────────────────────────────────────────
  String maxDoseWarning(String dosageStr) {
    if (maxDoseInput.trim().isEmpty) return "";
    final maxVal = double.tryParse(maxDoseInput.trim());
    if (maxVal == null) return "";
    final dosageMatch = RegExp(r'(\d+\.?\d*)').firstMatch(dosageStr);
    if (dosageMatch == null) return "";
    final doseVal = double.tryParse(dosageMatch.group(1)!);
    if (doseVal == null) return "";
    final totalDaily = doseVal * dosesPerDay;
    if (totalDaily > maxVal) {
      return "⚠️ Total daily: ${totalDaily.toStringAsFixed(0)} mg "
          "exceeds your max of ${maxVal.toStringAsFixed(0)} mg";
    }
    return "";
  }
}

// ── Frequency text → dose count parser ───────────────────────────────────────
int _parseDoseCount(String frequency) {
  final f = frequency.toLowerCase();
  if (f.contains('four') || f.contains('4 time') || f.contains('qid')) return 4;
  if (f.contains('three') || f.contains('3 time') || f.contains('thrice') || f.contains('tid')) return 3;
  if (f.contains('twice') || f.contains('2 time') || f.contains('two time') || f.contains('bid')) return 2;
  if (f.contains('once') || f.contains('1 time') || f.contains('od') || f.contains('daily')) return 1;
  return 1;
}

int _defaultGap(int doses) {
  switch (doses) {
    case 2: return 8;
    case 3: return 6;
    case 4: return 4;
    default: return 12;
  }
}

String _fmt(TimeOfDay t) {
  final h = t.hour > 12 ? t.hour - 12 : (t.hour == 0 ? 12 : t.hour);
  final m = t.minute.toString().padLeft(2, '0');
  return "$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}";
}

Color _foodColor(String tag) {
  if (tag == "With food") return kAccent;
  if (tag == "Empty stomach") return kRed;
  return kTextGrey;
}

IconData _foodIcon(String tag) {
  if (tag == "With food") return Icons.restaurant;
  if (tag == "Empty stomach") return Icons.no_meals;
  return Icons.remove_circle_outline;
}

const _purple = Color(0xFF7C4DFF);
const _orange = Color(0xFFFF6F00);

// ═════════════════════════════════════════════════════════════════════════════

class _MedicinesScreenState extends State<MedicinesScreen> {
  late List<_MedConfig> configs;
  late List<TextEditingController> _maxControllers;

  @override
  void initState() {
    super.initState();
    configs = widget.medicines.map((med) {
      final doses = _parseDoseCount(med["frequency"] ?? "");
      return _MedConfig(dosesPerDay: doses, gapHours: _defaultGap(doses));
    }).toList();
    _maxControllers = List.generate(
        widget.medicines.length, (_) => TextEditingController());
  }

  @override
  void dispose() {
    for (final c in _maxControllers) c.dispose();
    super.dispose();
  }

  Future<void> _pickFirstDose(int i) async {
    final p = await showTimePicker(
        context: context,
        initialTime: configs[i].firstDoseTime ?? TimeOfDay.now());
    if (p != null) setState(() => configs[i].firstDoseTime = p);
  }

  Future<void> _pickBedtime(int i) async {
    final p = await showTimePicker(
        context: context, initialTime: configs[i].bedtime);
    if (p != null) setState(() => configs[i].bedtime = p);
  }

  void _showGapPicker(int index) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Gap between doses",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextDark)),
            const SizedBox(height: 4),
            const Text("Hours between each intake",
                style: TextStyle(fontSize: 13, color: kTextGrey)),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [2, 4, 6, 8, 12].map((h) {
                final sel = configs[index].gapHours == h;
                return GestureDetector(
                  onTap: () {
                    setState(() => configs[index].gapHours = h);
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: sel ? kPrimary : kWhite,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? kPrimary : Colors.grey.shade300),
                    ),
                    child: Text("Every ${h}h",
                        style: TextStyle(
                            color: sel ? kWhite : kTextDark,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showFoodPicker(int index) {
    final options = ["With food", "Empty stomach", "No preference"];
    final icons = [
      Icons.restaurant,
      Icons.no_meals,
      Icons.remove_circle_outline
    ];
    final colors = [kAccent, kRed, kTextGrey];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Intake instruction",
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextDark)),
            const SizedBox(height: 12),
            ...List.generate(options.length, (i) {
              final sel = configs[index].foodTag == options[i];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: colors[i].withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Icon(icons[i], color: colors[i], size: 20),
                ),
                title: Text(options[i],
                    style: TextStyle(
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.normal,
                        color: sel ? kPrimary : kTextDark)),
                trailing: sel
                    ? const Icon(Icons.check_circle, color: kPrimary)
                    : null,
                onTap: () {
                  setState(() => configs[index].foodTag = options[i]);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> saveReminders() async {
    // Block if any max-dose warning
    for (int i = 0; i < widget.medicines.length; i++) {
      final w = configs[i].maxDoseWarning(widget.medicines[i]["dosage"] ?? "");
      if (w.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "Fix max dose issue for ${widget.medicines[i]["name"]} before saving."),
          backgroundColor: kRed,
        ));
        return;
      }
    }

    int savedCount = 0;
    final List<Map<String, dynamic>> toSave = [];

    for (int i = 0; i < widget.medicines.length; i++) {
      final cfg = configs[i];
      if (cfg.firstDoseTime == null) continue;
      final med = widget.medicines[i];
      final name = med["name"] ?? "Unknown";
      final doseTimes = cfg.allDoseTimes;

      for (int d = 0; d < doseTimes.length; d++) {
        final time = doseTimes[d];
        final isLast = d == doseTimes.length - 1;
        final baseId =
            ('$name${time.hour}${time.minute}').hashCode.abs();

        await scheduleReminder(
          baseId: baseId,
          medicineName: name,
          hour: time.hour,
          minute: time.minute,
        );

        toSave.add({
          "name":        name,
          "dosage":      med["dosage"]    ?? "—",
          "frequency":   med["frequency"] ?? "—",
          "hour":        time.hour,
          "minute":      time.minute,
          "baseId":      baseId,
          "doseNumber":  d + 1,
          "dosesPerDay": cfg.dosesPerDay,
          "foodTag":     cfg.foodTag,
          "beforeBed":   cfg.beforeBed && isLast,
          "taken":       false,
        });
        savedCount++;
      }
    }

    if (toSave.isNotEmpty) await ReminderStorage.saveReminders(toSave);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(savedCount > 0
          ? "$savedCount dose reminder(s) saved! Each rings 3×."
          : "No reminders set — pick a first dose time first."),
      backgroundColor: savedCount > 0 ? kAccent : kTextGrey,
    ));
    if (savedCount > 0) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("Set Medicine Schedule"),
          backgroundColor: kPrimary,
          foregroundColor: kWhite),
      body: Column(
        children: [

          // Top info banner
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: kAccent.withOpacity(0.1),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: kAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Found ${widget.medicines.length} medicine(s). "
                    "Configure each — every dose rings 3× until confirmed.",
                    style: const TextStyle(color: kAccent, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.medicines.length,
              itemBuilder: (context, index) {
                final med     = widget.medicines[index];
                final cfg     = configs[index];
                final times   = cfg.allDoseTimes;
                final dosage  = med["dosage"] ?? "—";
                final warning = cfg.maxDoseWarning(dosage);

                return Card(
                  margin: const EdgeInsets.only(bottom: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // Medicine name
                        Row(children: [
                          const Icon(Icons.medication,
                              color: kPrimary, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(med["name"] ?? "Unknown",
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: kTextDark)),
                          ),
                        ]),
                        Padding(
                          padding: const EdgeInsets.only(left: 30, top: 3),
                          child: Text("$dosage  •  ${med["frequency"] ?? "—"}",
                              style: const TextStyle(
                                  fontSize: 13, color: kTextGrey)),
                        ),

                        const SizedBox(height: 14),
                        const Divider(),
                        const SizedBox(height: 12),

                        // ═══ 1. Doses per day ════════════════════════════════
                        Row(children: [
                          const Icon(Icons.repeat, color: kPrimary, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text("Doses per day",
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: kTextDark)),
                          ),
                          _DoseStepper(
                            value: cfg.dosesPerDay,
                            onDecrement: cfg.dosesPerDay > 1
                                ? () => setState(() {
                                      configs[index].dosesPerDay--;
                                      configs[index].gapHours =
                                          _defaultGap(configs[index].dosesPerDay);
                                    })
                                : null,
                            onIncrement: cfg.dosesPerDay < 4
                                ? () => setState(() {
                                      configs[index].dosesPerDay++;
                                      configs[index].gapHours =
                                          _defaultGap(configs[index].dosesPerDay);
                                    })
                                : null,
                          ),
                        ]),

                        const SizedBox(height: 12),

                        // ═══ 2. Gap between doses ════════════════════════════
                        if (cfg.dosesPerDay > 1) ...[
                          _RowTile(
                            icon: Icons.timer_outlined,
                            iconColor: kPrimary,
                            label: "Gap between doses",
                            trailing: Text("Every ${cfg.gapHours}h",
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: kPrimary)),
                            onTap: () => _showGapPicker(index),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // ═══ 3. First dose time ══════════════════════════════
                        _RowTile(
                          icon: cfg.firstDoseTime != null
                              ? Icons.alarm_on
                              : Icons.alarm_add,
                          iconColor: cfg.firstDoseTime != null
                              ? kAccent
                              : kPrimary,
                          bgColor: cfg.firstDoseTime != null
                              ? kAccent.withOpacity(0.06)
                              : null,
                          borderColor: cfg.firstDoseTime != null
                              ? kAccent.withOpacity(0.3)
                              : null,
                          label: cfg.firstDoseTime != null
                              ? "First dose: ${_fmt(cfg.firstDoseTime!)}"
                              : "Set first dose time",
                          labelColor: cfg.firstDoseTime != null
                              ? kAccent
                              : kTextDark,
                          onTap: () => _pickFirstDose(index),
                        ),

                        // Dose time chips
                        if (times.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: times.asMap().entries.map((e) {
                              final isBedSlot = cfg.beforeBed &&
                                  e.key == times.length - 1 &&
                                  cfg.dosesPerDay > 1;
                              final cc = isBedSlot ? _purple : kPrimary;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: cc.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: cc.withOpacity(0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isBedSlot
                                          ? Icons.bedtime_outlined
                                          : Icons.notifications_outlined,
                                      color: cc,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${isBedSlot ? '🌙 Bedtime' : 'Dose ${e.key + 1}'}: ${_fmt(e.value)}",
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: cc,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 5),
                          Row(children: const [
                            Icon(Icons.info_outline,
                                color: kTextGrey, size: 12),
                            SizedBox(width: 4),
                            Text(
                              "Each dose rings 3× (every 2 min) until tapped",
                              style: TextStyle(
                                  fontSize: 11, color: kTextGrey),
                            ),
                          ]),
                          const SizedBox(height: 10),
                        ],

                        // ═══ 4. Before bed toggle ════════════════════════════
                        if (cfg.dosesPerDay > 1) ...[
                          _BeforeBedRow(
                            value: cfg.beforeBed,
                            bedtime: cfg.bedtime,
                            onToggle: (v) =>
                                setState(() => configs[index].beforeBed = v),
                            onPickBedtime: () => _pickBedtime(index),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // ═══ 5. Food / intake tag ════════════════════════════
                        _RowTile(
                          icon: _foodIcon(cfg.foodTag),
                          iconColor: _foodColor(cfg.foodTag),
                          bgColor:
                              _foodColor(cfg.foodTag).withOpacity(0.06),
                          borderColor:
                              _foodColor(cfg.foodTag).withOpacity(0.25),
                          label: cfg.foodTag,
                          labelColor: _foodColor(cfg.foodTag),
                          onTap: () => _showFoodPicker(index),
                        ),

                        const SizedBox(height: 10),

                        // ═══ 6. Max daily dose warning ═══════════════════════
                        _MaxDoseRow(
                          controller: _maxControllers[index],
                          onChanged: (v) => setState(
                              () => configs[index].maxDoseInput = v),
                        ),

                        if (warning.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: kRed.withOpacity(0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kRed.withOpacity(0.35)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: kRed, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(warning,
                                    style: const TextStyle(
                                        color: kRed,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                              ),
                            ]),
                          ),
                        ],

                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                onPressed: saveReminders,
                icon: const Icon(Icons.notifications_active, color: kWhite),
                label: const Text("Save All Reminders",
                    style: TextStyle(fontSize: 16, color: kWhite)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═════════════════════════════════════════════════════════════════════════════

class _RowTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color? bgColor;
  final Color? borderColor;
  final String label;
  final Color? labelColor;
  final Widget? trailing;
  final VoidCallback onTap;

  const _RowTile({
    required this.icon,
    required this.iconColor,
    this.bgColor,
    this.borderColor,
    required this.label,
    this.labelColor,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bgColor ?? kWhite,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: borderColor ?? Colors.grey.shade300),
        ),
        child: Row(children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: labelColor ?? kTextDark)),
          ),
          trailing ?? Icon(Icons.chevron_right, color: iconColor, size: 18),
        ]),
      ),
    );
  }
}

// Before Bed toggle + bedtime sub-row
class _BeforeBedRow extends StatelessWidget {
  final bool value;
  final TimeOfDay bedtime;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickBedtime;

  const _BeforeBedRow({
    required this.value,
    required this.bedtime,
    required this.onToggle,
    required this.onPickBedtime,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: value ? _purple.withOpacity(0.06) : kWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: value
                ? _purple.withOpacity(0.3)
                : Colors.grey.shade300),
      ),
      child: Column(children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            const Icon(Icons.bedtime_outlined,
                color: _purple, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Before bed",
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: kTextDark)),
                  Text("Snap last dose to your bedtime",
                      style: TextStyle(
                          fontSize: 11, color: kTextGrey)),
                ],
              ),
            ),
            Switch(
                value: value,
                onChanged: onToggle,
                activeColor: _purple),
          ]),
        ),
        if (value) ...[
          const Divider(height: 1),
          InkWell(
            onTap: onPickBedtime,
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              child: Row(children: [
                const Icon(Icons.access_time,
                    color: _purple, size: 16),
                const SizedBox(width: 8),
                Text("Bedtime: ${_fmt(bedtime)}",
                    style: const TextStyle(
                        fontSize: 13,
                        color: _purple,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text("Change",
                    style: TextStyle(
                        fontSize: 12,
                        color: _purple,
                        decoration: TextDecoration.underline)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

// Max daily dose input row
class _MaxDoseRow extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _MaxDoseRow(
      {required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: _orange, size: 18),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Max daily dose (mg)",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: kTextDark)),
              Text("Leave blank to skip check",
                  style: TextStyle(fontSize: 11, color: kTextGrey)),
            ],
          ),
        ),
        SizedBox(
          width: 82,
          height: 36,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
            ],
            textAlign: TextAlign.center,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 14, color: kTextDark),
            decoration: InputDecoration(
              hintText: "e.g. 1000",
              hintStyle: TextStyle(
                  fontSize: 11, color: Colors.grey.shade400),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 9),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: kPrimary),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// Dose stepper (−  N  +)
class _DoseStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const _DoseStepper(
      {required this.value,
      required this.onDecrement,
      required this.onIncrement});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _StepBtn(icon: Icons.remove, onTap: onDecrement),
      SizedBox(
        width: 34,
        child: Text("$value",
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextDark)),
      ),
      _StepBtn(icon: Icons.add, onTap: onIncrement),
    ]);
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: active
              ? kPrimary.withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active
                  ? kPrimary.withOpacity(0.3)
                  : Colors.grey.shade200),
        ),
        child: Icon(icon,
            size: 16,
            color: active ? kPrimary : Colors.grey.shade400),
      ),
    );
  }
}