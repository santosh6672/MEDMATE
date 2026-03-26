import 'package:flutter/material.dart';

import '../constants.dart';
import '../models/user_anchors.dart';
import '../services/anchor_storage.dart';
import 'dashboard_screen.dart';

class AnchorSetupScreen extends StatefulWidget {
  final bool isEditing;

  const AnchorSetupScreen({super.key, this.isEditing = false});

  @override
  State<AnchorSetupScreen> createState() => _AnchorSetupScreenState();
}

class _AnchorSetupScreenState extends State<AnchorSetupScreen> {
  late TimeOfDay _wakeUp;
  late TimeOfDay _breakfast;
  late TimeOfDay _lunch;
  late TimeOfDay _dinner;
  late TimeOfDay _sleep;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialAnchors();
  }

  Future<void> _loadInitialAnchors() async {
    final stored = await AnchorStorage.loadAnchors();
    if (stored != null) {
      _wakeUp = stored.wakeUp;
      _breakfast = stored.breakfast;
      _lunch = stored.lunch;
      _dinner = stored.dinner;
      _sleep = stored.sleep;
    } else {
      final defaults = UserAnchors.defaults();
      _wakeUp = defaults.wakeUp;
      _breakfast = defaults.breakfast;
      _lunch = defaults.lunch;
      _dinner = defaults.dinner;
      _sleep = defaults.sleep;
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickTime(
      BuildContext context, TimeOfDay initial, ValueChanged<TimeOfDay> onChanged) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: kPrimary,
              onPrimary: kWhite,
              onSurface: kTextDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  Future<void> _saveAnchors() async {
    final anchors = UserAnchors(
      wakeUp: _wakeUp,
      breakfast: _breakfast,
      lunch: _lunch,
      dinner: _dinner,
      sleep: _sleep,
    );
    await AnchorStorage.saveAnchors(anchors);

    if (!mounted) return;

    if (widget.isEditing) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
        (_) => false,
      );
    }
  }

  Widget _buildTimeTile({
    required String title,
    required TimeOfDay time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kPrimary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: kPrimary),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            time.format(context),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kTextDark,
            ),
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: kBg,
        body: Center(child: CircularProgressIndicator(color: kPrimary)),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Daily Schedule'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isEditing
                    ? 'Update your typical daily schedule.'
                    : 'Let\'s set up your typical daily schedule to help MedMate schedule your reminders.',
                style: const TextStyle(fontSize: 16, color: kTextGrey),
              ),
              const SizedBox(height: 24),
              _buildTimeTile(
                title: 'Wake Up',
                time: _wakeUp,
                icon: Icons.wb_sunny_outlined,
                onTap: () => _pickTime(
                  context,
                  _wakeUp,
                  (t) => setState(() => _wakeUp = t),
                ),
              ),
              _buildTimeTile(
                title: 'Breakfast',
                time: _breakfast,
                icon: Icons.breakfast_dining_outlined,
                onTap: () => _pickTime(
                  context,
                  _breakfast,
                  (t) => setState(() => _breakfast = t),
                ),
              ),
              _buildTimeTile(
                title: 'Lunch',
                time: _lunch,
                icon: Icons.lunch_dining_outlined,
                onTap: () => _pickTime(
                  context,
                  _lunch,
                  (t) => setState(() => _lunch = t),
                ),
              ),
              _buildTimeTile(
                title: 'Dinner',
                time: _dinner,
                icon: Icons.dinner_dining_outlined,
                onTap: () => _pickTime(
                  context,
                  _dinner,
                  (t) => setState(() => _dinner = t),
                ),
              ),
              _buildTimeTile(
                title: 'Sleep',
                time: _sleep,
                icon: Icons.bedtime_outlined,
                onTap: () => _pickTime(
                  context,
                  _sleep,
                  (t) => setState(() => _sleep = t),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _saveAnchors,
                  child: const Text(
                    'Save Schedule',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: kWhite,
                    ),
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
