import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_methods = """  Future<void> saveShowDelegatedBookings(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_delegated_bookings', show);
  }

  Future<bool> getShowDelegatedBookings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_delegated_bookings') ?? true;
  }

  Future<void> saveDelegatedDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('delegated_dates', dates);
  }

  Future<List<String>> getDelegatedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('delegated_dates') ?? [];
  }
"""

content = content.replace("  Future<void> savePullToRefresh", new_methods + "  Future<void> savePullToRefresh")

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)
