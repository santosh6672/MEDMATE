import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import '../services/reminder_storage.dart';
import '../services/alarm_service.dart';
import '../widgets/common_widgets.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import 'prescriptions_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _allMedicines = [];
  bool _isLoading = true;
  String _userName = '';
  int _streak = 0;
  double _adherence = 0.0;
  late AnimationController _progressController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _init();
  }

  Future<void> _init() async {
    // Load user data
    final prefs = await SharedPreferences.getInstance();
    _userName = prefs.getString('username') ?? 'User';

    // Request permissions using AlarmService
    await AlarmService.instance.checkAndRequestPermissions();

    // Daily reset
    await ReminderStorage.checkAndResetIfNewDay();
    await _loadSchedule();

    // Load stats (you need to compute streak and adherence from your data)
    _computeStats();
    _startProgressAnimation();
  }

  Future<void> _loadSchedule() async {
    final data = await ReminderStorage.loadReminders();
    if (!mounted) return;
    setState(() {
      _allMedicines = data;
      _isLoading = false;
    });
    _computeStats();
  }

  void _computeStats() {
    final total = _allMedicines.length;
    final taken = _allMedicines.where((e) => e['taken'] == true).length;
    _adherence = total == 0 ? 0 : taken / total;
    _streak = _adherence > 0.8 ? 3 : (_adherence > 0 ? 1 : 0); // dummy
  }

  void _startProgressAnimation() {
    _progressAnimation = Tween<double>(begin: 0, end: _adherence).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOutCubic),
    );
    _progressController.forward();
  }

  Future<void> _toggleTaken(int baseId, bool currentlyTaken) async {
    if (currentlyTaken) {
      await ReminderStorage.unmarkAsTakenByBaseId(baseId);
    } else {
      await ReminderStorage.markAsTakenByBaseId(baseId);
    }
    await _loadSchedule();
    _computeStats();
    _progressController.reset();
    _startProgressAnimation();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentlyTaken ? 'Unmarked' : 'Marked as taken'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _toggleTaken(baseId, !currentlyTaken),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Grouping methods
  List<Map<String, dynamic>> get _missedDoses =>
      _allMedicines.where((e) => _isMissed(e)).toList();
  List<Map<String, dynamic>> get _upcomingDoses =>
      _allMedicines.where((e) => !_isMissed(e) && e['taken'] != true).toList();
  List<Map<String, dynamic>> get _completedDoses =>
      _allMedicines.where((e) => e['taken'] == true).toList();

  bool _isMissed(Map<String, dynamic> medicine) {
    final now = DateTime.now();
    final doseTime = DateTime(
        now.year, now.month, now.day, medicine['hour'], medicine['minute']);
    return doseTime.isBefore(now) && medicine['taken'] != true;
  }

  String _format(int h, int m) {
    final hh = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm ${h >= 12 ? 'PM' : 'AM'}';
  }

  String _getDynamicMessage() {
    if (_adherence >= 0.9) return '🎉 Perfect! Keep it up!';
    if (_adherence >= 0.6) return '👍 Good job, almost there!';
    if (_adherence > 0) return '💪 Let’s finish the day strong!';
    return '🌟 Start your day with a dose!';
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
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
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
              _loadSchedule();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Header (personalised)
                  _buildHeader(),
                  const SizedBox(height: 20),

                  // Hero card (circular progress)
                  _buildHeroCard(),
                  const SizedBox(height: 24),

                  // Quick actions (enhanced)
                  _buildQuickActions(),
                  const SizedBox(height: 24),

                  // Insights section (intelligent)
                  _buildInsights(),
                  const SizedBox(height: 24),

                  // Schedule grouped
                  const Text(
                    "Today's Schedule",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
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
                    )
                  else
                    Column(
                      children: [
                        if (_missedDoses.isNotEmpty)
                          _buildSection('⚠ Missed', _missedDoses, isMissed: true),
                        if (_upcomingDoses.isNotEmpty)
                          _buildSection('⏳ Upcoming', _upcomingDoses),
                        if (_completedDoses.isNotEmpty)
                          _buildSection('✔ Completed', _completedDoses, isCompleted: true),
                      ],
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to manual medicine add screen
          // You can add a new screen or reuse upload screen
        },
        backgroundColor: kPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Good ${_getTimeOfDay()}, $_userName 👋',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: kTextDark,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.local_fire_department, color: Colors.orange, size: 16),
            const SizedBox(width: 4),
            Text(
              '$_streak-day streak',
              style: const TextStyle(fontSize: 14, color: kTextGrey),
            ),
          ],
        ),
      ],
    );
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimary, kPrimary.withBlue(180)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getDynamicMessage(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(_adherence * 100).toInt()}% completed',
                    style: const TextStyle(
                      color: kWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_allMedicines.length - _completedDoses.length} doses left',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: _progressAnimation.value,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  valueColor: const AlwaysStoppedAnimation(kWhite),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DashCard(
                icon: Icons.camera_alt_outlined,
                label: 'Scan',
                description: 'Upload prescription',
                color: kPrimary,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const UploadScreen()),
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
                description: 'Past prescriptions',
                color: kAccent,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PrescriptionsListScreen(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: DashCard(
                icon: Icons.medication,
                label: 'Add Manual',
                description: 'Enter medicine',
                color: kPrimary,
                onTap: () {
                  // Navigate to manual add screen
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DashCard(
                icon: Icons.insights,
                label: 'Reports',
                description: 'View stats',
                color: kPrimary,
                onTap: () {
                  // Show insights in detail
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInsights() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📊 Today\'s Performance',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${(_adherence * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kPrimary,
                      ),
                    ),
                    const Text('Adherence', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _missedDoses.length.toString(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const Text('Missed', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _completedDoses.length.toString(),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: kAccent,
                      ),
                    ),
                    const Text('Taken', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (_missedDoses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '⚠ You missed ${_missedDoses.length} dose(s). Set reminders earlier!',
                style: const TextStyle(fontSize: 12, color: kRed),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> doses,
      {bool isMissed = false, bool isCompleted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isMissed
                  ? Colors.red
                  : isCompleted
                      ? kAccent
                      : kPrimary,
            ),
          ),
        ),
        ...doses.map((dose) => _buildMedicineCard(dose, isMissed)),
      ],
    );
  }

  Widget _buildMedicineCard(Map<String, dynamic> dose, bool isMissed) {
    final baseId = dose['baseId'] as int;
    final taken = dose['taken'] == true;
    final name = dose['name'] as String;
    final hour = dose['hour'] as int;
    final minute = dose['minute'] as int;
    final doseNumber = dose['doseNumber'] as int?;
    final dosesPerDay = dose['dosesPerDay'] as int?;
    final timeStr = _format(hour, minute);

    // Calculate time remaining or overdue
    final now = DateTime.now();
    final doseTime = DateTime(now.year, now.month, now.day, hour, minute);
    String timeStatus = '';
    Color timeColor = kTextGrey;
    if (isMissed) {
      final diff = now.difference(doseTime);
      final mins = diff.inMinutes;
      timeStatus = '⚠ ${mins} min overdue';
      timeColor = Colors.red;
    } else if (!taken && doseTime.isAfter(now)) {
      final diff = doseTime.difference(now);
      final mins = diff.inMinutes;
      if (mins < 60) {
        timeStatus = '⏰ in $mins min';
        timeColor = kPrimary;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isMissed
              ? Colors.red.withOpacity(0.3)
              : taken
                  ? kAccent.withOpacity(0.3)
                  : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggleTaken(baseId, taken),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (taken ? kAccent : (isMissed ? Colors.red : kPrimary))
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  taken
                      ? Icons.check_circle
                      : isMissed
                          ? Icons.warning_amber_rounded
                          : Icons.medication,
                  color: taken
                      ? kAccent
                      : isMissed
                          ? Colors.red
                          : kPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: kTextGrey),
                        const SizedBox(width: 4),
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: 12, color: kTextGrey),
                        ),
                        if (dosesPerDay != null && dosesPerDay > 1) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Dose $doseNumber of $dosesPerDay',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (timeStatus.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          timeStatus,
                          style: TextStyle(fontSize: 11, color: timeColor),
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: taken
                      ? kAccent.withOpacity(0.1)
                      : kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: taken ? kAccent : kPrimary,
                  ),
                ),
                child: Text(
                  taken ? 'Undo' : 'Taken',
                  style: TextStyle(
                    color: taken ? kAccent : kPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}