import re

with open('lib/storage_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = """  Future<List<String>> getDelegatedBookings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('delegated_bookings') ?? [];
  }
  
  Future<void> saveDelegatedBookings(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('delegated_bookings', dates);
  }"""
  
good = """  Future<Map<String, String>> getDelegatedBookingsMap() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('delegated_bookings_map');
    if (jsonStr != null) {
      final Map<String, dynamic> decoded = jsonDecode(jsonStr);
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    }
    return {};
  }
  
  Future<void> saveDelegatedBookingsMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('delegated_bookings_map', jsonEncode(map));
  }"""
content = content.replace(bad, good)

if "import 'dart:convert';" not in content:
    content = "import 'dart:convert';\n" + content

with open('lib/storage_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)