extension AppDateUtils on String? {
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return (dateStr != null && dateStr.length >= 10) ? dateStr.substring(0, 10) : (dateStr ?? '—');
    }
  }
}
