import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/reminder_storage.dart';
import '../widgets/common_widgets.dart';
import '../widgets/schedule_widgets.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import 'prescriptions_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> allMedicines = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadTodaySchedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    loadTodaySchedule();
  }

  Future<void> loadTodaySchedule() async {
    List<Map<String, dynamic>> meds = await ReminderStorage.loadReminders();
    setState(() {
      allMedicines = meds;
      isLoading = false;
    });
  }

  Future<void> markDoseTaken(int originalIndex) async {
    await ReminderStorage.markAsTaken(originalIndex);
    await loadTodaySchedule();
  }

  String formatTime(int hour, int minute) {
    final h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? "PM" : "AM";
    return "$h:$m $period";
  }

  // ── Group flat dose list into one entry per medicine name ─────────────────
  List<Map<String, dynamic>> get groupedMedicines {
    final Map<String, Map<String, dynamic>> groups = {};

    for (int i = 0; i < allMedicines.length; i++) {
      final med  = allMedicines[i];
      final name = med["name"] ?? "Unknown";

      if (!groups.containsKey(name)) {
        groups[name] = {
          "name":    name,
          "dosage":  med["dosage"]  ?? "—",
          "foodTag": med["foodTag"] ?? "No preference",
          "doses":   <Map<String, dynamic>>[],
        };
      }

      (groups[name]!["doses"] as List).add({
        "hour":        med["hour"]        ?? 0,
        "minute":      med["minute"]      ?? 0,
        "doseNumber":  med["doseNumber"]  ?? 1,
        "dosesPerDay": med["dosesPerDay"] ?? 1,
        "taken":       med["taken"]       == true,
        "beforeBed":   med["beforeBed"]   == true,
        "originalIndex": i,
      });
    }

    for (final g in groups.values) {
      (g["doses"] as List).sort((a, b) =>
          (a["hour"] * 60 + a["minute"])
              .compareTo(b["hour"] * 60 + b["minute"]));
      final doses  = g["doses"] as List;
      g["allTaken"] = doses.every((d) => d["taken"] == true);
      g["anyTaken"] = doses.any((d)  => d["taken"] == true);
    }

    return groups.values.toList();
  }

  List<Map<String, dynamic>> get upcomingGroups =>
      groupedMedicines.where((g) => g["allTaken"] != true).toList();

  List<Map<String, dynamic>> get takenGroups =>
      groupedMedicines.where((g) => g["allTaken"] == true).toList();

  int get totalDoses     => allMedicines.length;
  int get takenDoses     => allMedicines.where((m) => m["taken"] == true).length;
  int get remainingDoses => totalDoses - takenDoses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MedMate"),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()));
              loadTodaySchedule();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: loadTodaySchedule,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Greeting card ──────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: kPrimary,
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Good Morning! 🌿",
                              style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 4),
                          const Text("Stay healthy today!",
                              style: TextStyle(color: kWhite, fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          Row(children: [
                            StatBox(label: "Total",     value: "$totalDoses",     icon: Icons.medication),
                            const SizedBox(width: 10),
                            StatBox(label: "Taken",     value: "$takenDoses",     icon: Icons.check_circle_outline),
                            const SizedBox(width: 10),
                            StatBox(label: "Remaining", value: "$remainingDoses", icon: Icons.pending_outlined),
                          ]),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Quick Actions ──────────────────────────────────────
                    const Text("Quick Actions",
                        style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.bold, color: kTextDark)),
                    const SizedBox(height: 14),

                    Row(children: [
                      Expanded(
                        child: DashCard(
                          icon: Icons.document_scanner,
                          label: "Scan\nPrescription",
                          color: kPrimary,
                          onTap: () async {
                            await Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => const UploadScreen()));
                            loadTodaySchedule();
                          },
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: DashCard(
                          icon: Icons.history,
                          label: "My\nPrescriptions",
                          color: kAccent,
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const PrescriptionsListScreen())),
                        ),
                      ),
                    ]),

                    const SizedBox(height: 28),

                    // ── Today's Schedule ───────────────────────────────────
                    const Text("Today's Schedule",
                        style: TextStyle(fontSize: 18,
                            fontWeight: FontWeight.bold, color: kTextDark)),
                    const SizedBox(height: 14),

                    // Empty state
                    if (allMedicines.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                            color: kWhite,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200)),
                        child: const Column(children: [
                          Icon(Icons.medication_outlined,
                              size: 48, color: kTextGrey),
                          SizedBox(height: 10),
                          Text("No medicines scheduled yet.",
                              style: TextStyle(color: kTextGrey, fontSize: 15)),
                          SizedBox(height: 4),
                          Text("Scan a prescription to get started.",
                              style: TextStyle(color: kTextGrey, fontSize: 13)),
                        ]),
                      ),

                    // ── Upcoming ───────────────────────────────────────────
                    if (upcomingGroups.isNotEmpty) ...[
                      SectionLabel(
                          label: "⏰  Upcoming",
                          color: kPrimary,
                          count: upcomingGroups.length),
                      const SizedBox(height: 10),
                      ...upcomingGroups.map((group) => GroupedScheduleCard(
                            group: group,
                            formatTime: formatTime,
                            onMarkTaken: (originalIndex) =>
                                markDoseTaken(originalIndex),
                          )),
                      const SizedBox(height: 20),
                    ],

                    // ── All taken ──────────────────────────────────────────
                    if (takenGroups.isNotEmpty) ...[
                      SectionLabel(
                          label: "✅  Taken Today",
                          color: kAccent,
                          count: takenGroups.length),
                      const SizedBox(height: 10),
                      ...takenGroups.map((group) => GroupedScheduleCard(
                            group: group,
                            formatTime: formatTime,
                            onMarkTaken: null,
                          )),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}