import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<void> saveBookedElsewhereDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('booked_elsewhere_dates', dates);
  }"""
  
good = """  Future<void> saveBookedElsewhereDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('booked_elsewhere_dates', dates);
  }
  
  Future<List<String>> getDelegatedBookings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('delegated_bookings') ?? [];
  }
  
  Future<void> saveDelegatedBookings(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('delegated_bookings', dates);
  }"""
content = content.replace(bad, good)

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)