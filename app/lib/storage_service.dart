import 'dart:convert'; // used by saveVacations/getVacations
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/colleague.dart';

/// Uses FlutterSecureStorage for sensitive credentials (refresh token)
/// and shared_preferences for app settings and cache.
class StorageService {
  final FlutterSecureStorage _secureStorage;
  final bool _useSecureStorage;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            ),
        _useSecureStorage = secureStorage != null || kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');

  static const String _refreshTokenKey = 'refresh_token';
  static const String _rememberEmailKey = 'remember_email';
  static const String _savedEmailKey = 'saved_email';

  // ── Remember Email (Milestone M1 - Requirement R1) ─────────────────────────

  Future<void> saveRememberEmail(bool remember) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberEmailKey, remember);
  }

  Future<bool> getRememberEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberEmailKey) ?? true;
  }

  Future<void> saveSavedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_savedEmailKey, email);
  }

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedEmailKey);
  }

  Future<void> clearSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedEmailKey);
  }

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
    if (!_useSecureStorage) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_refreshTokenKey, token);
      return;
    }
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
    if (!_useSecureStorage) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_refreshTokenKey);
    }
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
    if (_useSecureStorage) {
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
    await prefs.remove('access_token');
    await prefs.remove('token_expiry');
  }

  Future<void> clearTokens() async {
    await clearAuthToken();
    final remember = await getRememberEmail();
    if (!remember) {
      await clearSavedEmail();
    }
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

  Future<Map<String, String>> getRequestedWorkspacesMap() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('requested_workspaces_map');
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    return {};
  }

  Future<void> saveRequestedWorkspacesMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('requested_workspaces_map', jsonEncode(map));
  }

  Future<Map<String, String>> getRequestedWorkspaceNamesMap() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('requested_workspace_names_map');
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }
    return {};
  }

  Future<void> saveRequestedWorkspaceNamesMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('requested_workspace_names_map', jsonEncode(map));
  }

  /// Associates a specific [workspaceId] (and optional [workspaceName]) to a requested [date].
  /// If [workspaceId] is null or empty, removes the association for that date.
  Future<void> saveRequestedWorkspace(String date, String? workspaceId, {String? workspaceName}) async {
    final map = await getRequestedWorkspacesMap();
    final namesMap = await getRequestedWorkspaceNamesMap();
    if (workspaceId != null && workspaceId.isNotEmpty) {
      map[date] = workspaceId;
      if (workspaceName != null && workspaceName.isNotEmpty) {
        namesMap[date] = workspaceName;
      }
    } else {
      map.remove(date);
      namesMap.remove(date);
    }
    await saveRequestedWorkspacesMap(map);
    await saveRequestedWorkspaceNamesMap(namesMap);
  }

  /// Retrieves the specific requested workspace ID for [date] if one was configured.
  Future<String?> getRequestedWorkspace(String date) async {
    final map = await getRequestedWorkspacesMap();
    return map[date];
  }

  /// Retrieves the specific requested workspace name for [date] if one was configured.
  Future<String?> getRequestedWorkspaceName(String date) async {
    final namesMap = await getRequestedWorkspaceNamesMap();
    return namesMap[date];
  }

  /// Adds a date to requested dates, optionally binding a specific workspace.
  Future<void> addRequestedDate(String date, {String? workspaceId, String? workspaceName}) async {
    final dates = await getRequestedDates();
    if (!dates.contains(date)) {
      dates.add(date);
      await saveRequestedDates(dates);
    }
    if (workspaceId != null && workspaceId.isNotEmpty) {
      await saveRequestedWorkspace(date, workspaceId, workspaceName: workspaceName);
    }
  }

  /// Removes a date from requested dates and clears its workspace association.
  Future<void> removeRequestedDate(String date) async {
    final dates = await getRequestedDates();
    if (dates.contains(date)) {
      dates.remove(date);
      await saveRequestedDates(dates);
    }
    await saveRequestedWorkspace(date, null);
  }

  /// Toggles a requested date and optionally sets its workspace association.
  Future<void> toggleRequestedDate(String date, {String? workspaceId, String? workspaceName}) async {
    final dates = await getRequestedDates();
    if (dates.contains(date)) {
      dates.remove(date);
      await saveRequestedDates(dates);
      await saveRequestedWorkspace(date, null);
    } else {
      dates.add(date);
      await saveRequestedDates(dates);
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await saveRequestedWorkspace(date, workspaceId, workspaceName: workspaceName);
      }
    }
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

  /// Persists a delegated booking for a given [date] and [workspaceId].
  /// Supports multiple delegated bookings on the same date via composite keys `'$date#$workspaceId'`.
  Future<void> saveDelegatedBooking(
    String date,
    String workspaceIdOrBooking, [
    String? bookingData,
  ]) async {
    final String workspaceId;
    final String value;
    if (bookingData != null) {
      workspaceId = workspaceIdOrBooking;
      value = bookingData;
    } else {
      if (workspaceIdOrBooking.contains('|')) {
        workspaceId = workspaceIdOrBooking.split('|').first;
        value = workspaceIdOrBooking;
      } else {
        workspaceId = workspaceIdOrBooking;
        value = workspaceIdOrBooking;
      }
    }

    final map = await getDelegatedBookingsMap();
    final compositeKey = '$date#$workspaceId';
    map[compositeKey] = value;
    // Maintain backwards compatibility for single-date lookups
    if (!map.containsKey(date)) {
      map[date] = value;
    }
    await saveDelegatedBookingsMap(map);
  }

  /// Retrieves the delegated booking data for [date] and optional [workspaceId].
  /// If [workspaceId] is specified, searches for that specific desk delegation.
  /// If omitted, returns any delegation existing on that date.
  Future<String?> getDelegatedBooking(String date, [String? workspaceId]) async {
    final map = await getDelegatedBookingsMap();
    if (workspaceId != null && workspaceId.isNotEmpty) {
      final compositeKey = '$date#$workspaceId';
      if (map.containsKey(compositeKey)) {
        return map[compositeKey];
      }
      for (final entry in map.entries) {
        if (entry.key.startsWith('$date#')) {
          final keyWs = entry.key.substring(date.length + 1);
          if (keyWs == workspaceId || entry.value.split('|').first == workspaceId) {
            return entry.value;
          }
        }
      }
      final legacy = map[date];
      if (legacy != null) {
        final legacyWsId = legacy.split('|').first;
        if (legacyWsId == workspaceId || legacyWsId == legacy) {
          return legacy;
        }
      }
      return null;
    }

    if (map.containsKey(date)) {
      return map[date];
    }
    for (final entry in map.entries) {
      if (entry.key.startsWith('$date#')) {
        return entry.value;
      }
    }
    return null;
  }

  /// Removes a specific delegated booking on [date] for [workspaceId],
  /// preserving other bookings on the same date without overwriting them.
  Future<void> removeDelegatedBooking(String date, String workspaceId) async {
    final map = await getDelegatedBookingsMap();
    final compositeKey = '$date#$workspaceId';
    map.remove(compositeKey);

    map.removeWhere((key, val) =>
        key.startsWith('$date#') &&
        (key.substring(date.length + 1) == workspaceId || val.split('|').first == workspaceId));

    final remainingForDate = <String>[];
    for (final entry in map.entries) {
      if (entry.key.startsWith('$date#')) {
        remainingForDate.add(entry.value);
      }
    }

    if (remainingForDate.isNotEmpty) {
      final legacy = map[date];
      if (legacy == null || legacy.split('|').first == workspaceId) {
        map[date] = remainingForDate.first;
      }
    } else {
      map.remove(date);
    }

    await saveDelegatedBookingsMap(map);
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
    final remember = await getRememberEmail();
    final savedEmail = remember ? await getSavedEmail() : null;

    if (_useSecureStorage) {
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (remember && savedEmail != null && savedEmail.isNotEmpty) {
      await prefs.setBool(_rememberEmailKey, true);
      await prefs.setString(_savedEmailKey, savedEmail);
    }
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

  /// Merges remote [apiFavorites] with existing local favorite colleagues.
  /// Local external/manual favorites (e.g. ID starting with 'ext_' or 'custom_',
  /// or any local favorite not returned by the API) are strictly preserved.
  /// Existing colleagues are updated with API metadata while ensuring [isFavorite] is true.
  Future<void> mergeFavoriteColleagues(List<Colleague> apiFavorites) async {
    final current = await getFavoriteColleagues();
    final merged = <Colleague>[];
    final matchedApiIndices = <int>{};

    for (final local in current) {
      // Find matching colleague in apiFavorites
      final apiIndex = apiFavorites.indexWhere((api) =>
          (local.id.isNotEmpty && api.id.isNotEmpty && local.id == api.id) ||
          (local.favoriteId != null && api.favoriteId != null && local.favoriteId == api.favoriteId) ||
          (local.email.isNotEmpty && api.email.isNotEmpty && local.email.toLowerCase() == api.email.toLowerCase()));

      if (apiIndex >= 0) {
        matchedApiIndices.add(apiIndex);
        final apiColleague = apiFavorites[apiIndex];
        merged.add(apiColleague.copyWith(
          isFavorite: true,
          favoriteId: apiColleague.favoriteId ?? local.favoriteId,
        ));
      } else {
        // Local colleague is manual/external (e.g. custom_*, ext_*) or not in API: keep them
        merged.add(local.copyWith(isFavorite: true));
      }
    }

    // Add new API favorites not already in merged
    for (int i = 0; i < apiFavorites.length; i++) {
      if (!matchedApiIndices.contains(i)) {
        final apiColleague = apiFavorites[i];
        final exists = merged.any((c) =>
            (c.id.isNotEmpty && apiColleague.id.isNotEmpty && c.id == apiColleague.id) ||
            (c.email.isNotEmpty && apiColleague.email.isNotEmpty && c.email.toLowerCase() == apiColleague.email.toLowerCase()));
        if (!exists) {
          merged.add(apiColleague.copyWith(isFavorite: true));
        }
      }
    }

    await saveFavoriteColleagues(merged);
  }

  /// Adds a colleague to favorites or updates them if their id is already present.
  /// Automatically ensures [isFavorite] is true.
  Future<void> addFavoriteColleague(Colleague colleague) async {
    final current = await getFavoriteColleagues();
    final effectiveId = colleague.id.isNotEmpty
        ? colleague.id
        : 'ext_${DateTime.now().millisecondsSinceEpoch}';
    final updatedColleague = colleague.copyWith(id: effectiveId, isFavorite: true);
    final index = current.indexWhere((c) =>
        (c.id.isNotEmpty && effectiveId.isNotEmpty && c.id == effectiveId) ||
        (c.email.isNotEmpty && colleague.email.isNotEmpty && c.email.toLowerCase() == colleague.email.toLowerCase()));
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
