import 'package:flutter/material.dart';
import '../constants.dart';
import '../services/reminder_storage.dart';
import '../services/alarm_service.dart';
import '../widgets/common_widgets.dart';

class ManualAddScreen extends StatefulWidget {
  const ManualAddScreen({super.key});

  @override
  State<ManualAddScreen> createState() => _ManualAddScreenState();
}

class _ManualAddScreenState extends State<ManualAddScreen> {
  final _nameController = TextEditingController();
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _dosesPerDay = 1;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: kPrimary,
              onPrimary: kWhite,
              onSurface: kTextDark,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _saveReminder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter medicine name')),
      );
      return;
    }

    final now = DateTime.now();
    var scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final baseId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final reminder = {
      'name': name,
      'hour': _selectedTime.hour,
      'minute': _selectedTime.minute,
      'doseNumber': 1,
      'dosesPerDay': _dosesPerDay,
      'taken': false,
      'baseId': baseId,
    };

    await ReminderStorage.saveReminders([reminder]);
    await AlarmService.instance.setAlarm(
      medicine: name,
      time: scheduledTime,
    );

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Add Medicine'),
        backgroundColor: kPrimary,
        foregroundColor: kWhite,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Medicine Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: kTextDark,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: inputDecoration('Medicine Name', Icons.medication_outline),
            ),
            const SizedBox(height: 20),
            const Text(
              'Reminder Time',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _selectTime(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: kWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, color: kPrimary),
                    const SizedBox(width: 12),
                    Text(
                      _selectedTime.format(context),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    const Text(
                      'Change',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saveReminder,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Reminder',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
