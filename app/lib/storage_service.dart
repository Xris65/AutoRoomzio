import 'dart:convert'; // used by saveVacations/getVacations
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/colleague.dart';

/// Uses FlutterSecureStorage for sensitive credentials (refresh token)
/// and shared_preferences for app settings and cache.
class StorageService {
  final FlutterSecureStorage _secureStorage;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const String _refreshTokenKey = 'refresh_token';

  // === UI Settings ===

  Future<void> saveIgnoredUpdateVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ignored_update_version', version);
  }

  Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('ignored_update_version');
  }

  Future<void> saveShowDelegatedBookings(bool show) async {
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
  Future<void> savePullToRefresh(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pull_to_refresh', enabled);
  }

  Future<bool> getPullToRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('pull_to_refresh') ?? true;
  }


  

  Future<void> saveShowAutomation(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_automation_card', show);
  }

  Future<bool> getShowAutomation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_automation_card') ?? true;
  }

  Future<void> saveShowStats(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_stats_card', show);
  }

  Future<bool> getShowStats() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('show_stats_card') ?? true;
  }
  // ── Token ─────────────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async {
    try {
      await _secureStorage.write(key: _refreshTokenKey, value: token);
    } catch (_) {
      // Unit test fallback or unsupported channel environment
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_refreshTokenKey, token);
      return;
    }
  }

  Future<String?> getRefreshToken() async {
    try {
      final secureToken = await _secureStorage.read(key: _refreshTokenKey);
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
    } catch (_) {
      // Handled: platform channel missing in unit test runner
    }

    // Legacy fallback & auto-migration
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_refreshTokenKey);

    if (legacyToken != null && legacyToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _refreshTokenKey, value: legacyToken);
        // Only delete from SharedPreferences once confirmed written to secure storage
        await prefs.remove(_refreshTokenKey);
      } catch (_) {
        // In headless unit tests where native channel is missing, keep in SharedPreferences
        // so repeat calls during the test run still succeed.
      }
      return legacyToken;
    }

    return null;
  }

  Future<void> clearAuthToken() async {
    try {
      await _secureStorage.delete(key: _refreshTokenKey);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
    await prefs.remove('access_token');
    await prefs.remove('token_expiry');
  }

  Future<void> clearTokens() async {
    await clearAuthToken();
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

  // Building / Site aliases
  Future<void> saveBuildingId(String id) => saveSiteId(id);
  Future<String?> getBuildingId() => getSiteId();

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

  // Room / Workspace aliases
  Future<void> saveRoomId(String id) => saveWorkspaceId(id);
  Future<String?> getRoomId() => getWorkspaceId();

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

  Future<void> saveIgnoredDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('ignored_dates', dates);
  }

  Future<List<String>> getIgnoredDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('ignored_dates') ?? [];
  }

  Future<void> saveBookedElsewhereDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('booked_elsewhere_dates', dates);
  }

  // --- ALL-TIME STATS TRACKING ---
  Future<void> saveAllTimeBookedDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('all_time_booked_dates', dates);
  }

  Future<List<String>> getAllTimeBookedDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('all_time_booked_dates') ?? [];
  }

  Future<void> saveAllTimeElsewhereDates(List<String> dates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('all_time_elsewhere_dates', dates);
  }

  Future<List<String>> getAllTimeElsewhereDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('all_time_elsewhere_dates') ?? [];
  }
  // -------------------------------
  
  Future<Map<String, String>> getDelegatedBookingsMap() async {
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
  }

  Future<List<String>> getBookedElsewhereDates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('booked_elsewhere_dates') ?? [];
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

  Future<void> saveAutomationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('automation_enabled', enabled);
  }

  Future<bool> getAutomationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('automation_enabled') ?? false;
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

  Future<void> saveAutomationTime(int hour, int minute) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_time_hour', hour);
    await prefs.setInt('auto_time_minute', minute);
  }

  Future<Map<String, int>> getAutomationTime() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'hour': prefs.getInt('auto_time_hour') ?? 8,
      'minute': prefs.getInt('auto_time_minute') ?? 0,
    };
  }

  Future<void> saveNotifySuccess(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_success', val);
  }
  
  Future<bool> getNotifySuccess() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notify_success') ?? true;
  }
  
  Future<void> saveNotifyFailure(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notify_failure', val);
  }
  
  Future<bool> getNotifyFailure() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('notify_failure') ?? true;
  }

  Future<void> saveThemeColorIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_index', index);
  }

  Future<int> getThemeColorIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('theme_color_index') ?? 0;
  }

  Future<void> saveAutoSync(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_sync', val);
  }

  Future<bool> getAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_sync') ?? true;
  }

  Future<void> saveProjectionsCount(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('projections_count', val);
  }

  Future<int> getProjectionsCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('projections_count') ?? 4;
  }

  Future<void> saveInitialTab(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('initial_tab', val);
  }

  Future<int> getInitialTab() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('initial_tab') ?? 0;
  }

  Future<void> saveThemeModeIndex(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', val);
  }

  Future<int> getThemeModeIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('theme_mode') ?? 0; // 0: system, 1: light, 2: dark
  }



  // ── Hide weekends in calendar ─────────────────────────────────────────────

  Future<void> saveHideWeekends(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hide_weekends', val);
  }

  Future<bool> getHideWeekends() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hide_weekends') ?? true; // Actif par défaut
  }

  // ── Last sync timestamp (cache TTL) ──────────────────────────────────────

  Future<void> saveLastSyncTime({bool forceReset = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (forceReset) {
      await prefs.remove('last_sync_time');
    } else {
      await prefs.setInt('last_sync_time', DateTime.now().millisecondsSinceEpoch);
    }
  }

  Future<DateTime?> getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_sync_time');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }
  // ── New Customizations ───────────────────────────────────────────────────

  Future<void> saveVacations(List<Map<String, String>> vacations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vacation_periods', jsonEncode(vacations));
  }

  Future<List<Map<String, String>>> getVacations() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('vacation_periods');
    if (jsonString != null) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonString);
        return decoded.map((e) => Map<String, String>.from(e)).toList();
      } catch (_) {
        return [];
      }
    } else {
      // Backward-compat: migrate old single-vacation keys
      final oldStart = prefs.getString('vacation_start');
      final oldEnd = prefs.getString('vacation_end');
      if (oldStart != null && oldEnd != null) {
        return [{'start': oldStart, 'end': oldEnd}];
      }
      return [];
    }
  }

  // Kept for background_task backward-compat
  Future<Map<String, String?>> getVacationDates() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'start': prefs.getString('vacation_start'),
      'end': prefs.getString('vacation_end'),
    };
  }

  Future<void> saveCompactMode(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('compact_mode', val);
  }

  Future<bool> getCompactMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('compact_mode') ?? false;
  }

  Future<void> saveFontFamilyIndex(int val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('font_family_index', val);
  }

  Future<int> getFontFamilyIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('font_family_index') ?? 0;
  }

  Future<void> saveUiScale(double val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('ui_scale', val);
  }

  Future<double> getUiScale() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble('ui_scale') ?? 1.0;
  }


  // ── Clear all (logout) ────────────────────────────────────────────────────

  Future<void> saveHasSeenOptimization(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_optimization', val);
  }

  Future<bool> getHasSeenOptimization() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_seen_optimization') ?? false;
  }

  Future<void> saveAutostartVerified(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autostart_verified', val);
  }

  Future<void> saveBatteryVerified(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_verified', val);
  }

  Future<bool> getBatteryVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('battery_verified') ?? false;
  }

  Future<bool> getAutostartVerified() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('autostart_verified') ?? false;
  }

  Future<void> saveLastAutomationRun() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_automation_run', DateTime.now().millisecondsSinceEpoch);
  }

  Future<DateTime?> getLastAutomationRun() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('last_automation_run');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> clearAll() async {
    try {
      await _secureStorage.deleteAll();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  Future<void> clearAllData() async {
    await clearAll();
  }

  // 📊 Stats Tracking
  Future<void> recordFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('stats_first_use')) {
      await prefs.setString('stats_first_use', DateTime.now().toIso8601String());
    }
  }

  Future<DateTime> getFirstUse() async {
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getString('stats_first_use');
    if (d != null) {
      return DateTime.parse(d);
    } else {
      final now = DateTime.now();
      await prefs.setString('stats_first_use', now.toIso8601String());
      return now;
    }
  }

  Future<void> recordBookingStat(bool isAuto) async {
    final prefs = await SharedPreferences.getInstance();
    if (isAuto) {
      final count = prefs.getInt('stats_auto_count') ?? 0;
      await prefs.setInt('stats_auto_count', count + 1);
    } else {
      final count = prefs.getInt('stats_manual_count') ?? 0;
      await prefs.setInt('stats_manual_count', count + 1);
    }
  }

  Future<Map<String, int>> getBookingStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return {
      'manual': prefs.getInt('stats_manual_count') ?? 0,
      'auto': prefs.getInt('stats_auto_count') ?? 0,
    };
  }

  // ── Favorite Colleagues (Milestone M2 - Requirement R2) ───────────────────

  /// Retrieves the list of favorite colleagues stored in SharedPreferences.
  /// Returns an empty list if no favorites exist or if the stored JSON is malformed.
  Future<List<Colleague>> getFavoriteColleagues() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('favorite_colleagues');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded
            .map((item) => Colleague.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  /// Persists the complete list of favorite colleagues in SharedPreferences.
  Future<void> saveFavoriteColleagues(List<Colleague> colleagues) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(colleagues.map((c) => c.toJson()).toList());
    await prefs.setString('favorite_colleagues', jsonStr);
  }

  /// Adds a colleague to favorites or updates them if their id is already present.
  /// Automatically ensures [isFavorite] is true.
  Future<void> addFavoriteColleague(Colleague colleague) async {
    final current = await getFavoriteColleagues();
    final updatedColleague = colleague.copyWith(isFavorite: true);
    final index = current.indexWhere((c) => c.id == colleague.id);
    if (index >= 0) {
      current[index] = updatedColleague;
    } else {
      current.add(updatedColleague);
    }
    await saveFavoriteColleagues(current);
  }

  /// Removes a colleague from favorites by their unique id.
  Future<void> removeFavoriteColleague(String colleagueId) async {
    final current = await getFavoriteColleagues();
    current.removeWhere((c) =>
        c.id == colleagueId ||
        (colleagueId.isNotEmpty && c.email.isNotEmpty && c.email.toLowerCase() == colleagueId.toLowerCase()));
    await saveFavoriteColleagues(current);
  }

  /// Checks if a colleague with [colleagueId] is in the favorite list.
  Future<bool> isFavoriteColleague(String colleagueId) async {
    final current = await getFavoriteColleagues();
    return current.any((c) => c.id == colleagueId);
  }

}
