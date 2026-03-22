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
  List<Map<String, dynamic>> _allMedicines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _checkDailyReset();
    await _loadSchedule();
  }

  Future<void> _checkDailyReset() async {
    final last = await ReminderStorage.getLastResetDate();
    final now = DateTime.now();
    final today = '${now.year}-${now.month}-${now.day}';

    if (last != today) {
      await ReminderStorage.resetTakenStatus();
      await ReminderStorage.setLastResetDate(today);
    }
  }

  Future<void> _loadSchedule() async {
    final data = await ReminderStorage.loadReminders();

    if (!mounted) return;

    setState(() {
      _allMedicines = data;
      _isLoading = false;
    });
  }

  Future<void> _markTaken(int index) async {
    await ReminderStorage.markAsTaken(index);
    await _loadSchedule();
  }

  int get _total => _allMedicines.length;
  int get _taken =>
      _allMedicines.where((e) => e['taken'] == true).length;

  double get _progress =>
      _total == 0 ? 0 : _taken / _total;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    if (h < 21) return 'Good Evening';
    return 'Good Night';
  }

  String _format(int h, int m) {
    final hh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm ${h >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('MedMate'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileScreen(),
                ),
              );
              _loadSchedule();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: kPrimary),
            )
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [

                  // 🔥 HERO CARD
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimary, kPrimary.withBlue(180)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greeting,
                          style: const TextStyle(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Stay consistent today 💊',
                          style: TextStyle(
                            color: kWhite,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Progress
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 6,
                            backgroundColor:
                                Colors.white.withOpacity(0.2),
                            valueColor:
                                const AlwaysStoppedAnimation(kWhite),
                          ),
                        ),
                        const SizedBox(height: 8),

                        Text(
                          '$_taken / $_total completed',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ⚡ QUICK ACTIONS
                  const Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: DashCard(
                          icon: Icons.camera_alt_outlined,
                          label: 'Scan',
                          color: kPrimary,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const UploadScreen(),
                              ),
                            );
                            _loadSchedule();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DashCard(
                          icon: Icons.history,
                          label: 'History',
                          color: kAccent,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const PrescriptionsListScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 📋 SCHEDULE
                  const Text(
                    "Today's Schedule",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_allMedicines.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(30),
                      decoration: BoxDecoration(
                        color: kWhite,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(
                        child: Text(
                          'No reminders yet',
                          style: TextStyle(color: kTextGrey),
                        ),
                      ),
                    ),

                  ..._allMedicines.asMap().entries.map((e) {
                    final i = e.key;
                    final m = e.value;

                    final taken = m['taken'] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: taken
                              ? kAccent.withOpacity(0.3)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            taken
                                ? Icons.check_circle
                                : Icons.access_time,
                            color: taken ? kAccent : kPrimary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m['name'] ?? 'Medicine',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  _format(
                                    m['hour'],
                                    m['minute'],
                                  ),
                                  style: const TextStyle(
                                    color: kTextGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!taken)
                            GestureDetector(
                              onTap: () => _markTaken(i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(20),
                                  border: Border.all(color: kPrimary),
                                ),
                                child: const Text(
                                  'Taken',
                                  style: TextStyle(
                                    color: kPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}