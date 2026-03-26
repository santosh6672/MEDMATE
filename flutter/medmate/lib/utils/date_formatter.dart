extension DateFormatter on String? {
  static const _months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];

  String toDisplayDate() {
    final s = this;
    if (s == null || s.isEmpty) return '—';
    try {
      final dt = DateTime.parse(s).toLocal();
      return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return s.length >= 10 ? s.substring(0, 10) : s;
    }
  }
}
