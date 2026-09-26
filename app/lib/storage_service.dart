import 'package:shared_preferences/shared_preferences.dart';

/// Uses shared_preferences for all platforms.
/// On Android, SharedPreferences data is stored in the app's private sandbox,
/// which is sufficient security for a personal automation tool.
class StorageService {
  // ── Token ─────────────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('refresh_token', token);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('refresh_token');
  }

  // ── Workspace settings ────────────────────────────────────────────────────

  Future<void> saveSiteId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('site_id', id);
  }

  Future<String?> getSiteId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('site_id');
  }

  Future<void> saveFloorId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('floor_id', id);
  }

  Future<String?> getFloorId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('floor_id');
  }

  Future<void> saveWorkspaceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace_id', id);
  }

  Future<String?> getWorkspaceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workspace_id');
  }

  Future<void> saveWorkspaceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workspace_name', name);
  }

  Future<String?> getWorkspaceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('workspace_name');
  }

  Future<void> resetWorkspace() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('floor_id');
    await prefs.remove('workspace_id');
    await prefs.remove('workspace_name');
  }

  // ── Calendar Dates ────────────────────────────────────────────────────────
  
  Future<void> saveRequestedDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('requested_dates', dates);
  }

  Future<List<String>> getRequestedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('requested_dates') ?? [];
  }

  Future<void> saveBookedDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('booked_dates', dates);
  }

  Future<List<String>> getBookedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('booked_dates') ?? [];
  }

  // ── Days (recurring) ──────────────────────────────────────────────────────

  Future<void> saveDays(List<int> days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('selected_days', days.map((e) => e.toString()).toList());
  }

  Future<List<int>> getDays() async {
    final prefs = await SharedPreferences.getInstance();
    final days = prefs.getStringList('selected_days');
    // Default to Tue (2) and Thu (4) — matching the original Python script
    return days?.map(int.parse).toList() ?? [2, 4];
  }

  // ── Settings ─────────────────────────────────────────────────────────────
  
  Future<bool?> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('dark_mode');
  }

  Future<void> saveDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', isDark);
  }

  // ── Clear all (logout) ────────────────────────────────────────────────────

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
