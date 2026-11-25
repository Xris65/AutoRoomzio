import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/automation_rule.dart';
import 'models/colleague.dart';
import 'models/desk_occupant.dart';
import 'models/reservation_entry.dart';
import 'services/reservation_store.dart';

export 'models/automation_rule.dart';
export 'models/reservation_entry.dart';

/// Unified preference store adapter:
/// - Uses [SharedPreferencesAsync] in production / Web / Windows / WorkManager
///   background isolates so reads and writes hit platform storage directly
///   without a stale cross-isolate in-memory cache.
/// - Delegates to `SharedPreferences.getInstance()` when running under
///   `flutter test` so `SharedPreferences.setMockInitialValues(...)` works
///   transparently across the existing test suite.
class _PrefsStore implements ReservationPrefsBackend {
  const _PrefsStore();

  bool get _useTestPrefs => StorageService._isFlutterTestEnvironment();

  Future<SharedPreferences> _legacy() => SharedPreferences.getInstance();

  SharedPreferencesAsync _async() => SharedPreferencesAsync();

  @override
  Future<String?> getString(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).getString(key);
    }
    return _async().getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (_useTestPrefs) {
      await (await _legacy()).setString(key, value);
      return;
    }
    await _async().setString(key, value);
  }

  Future<bool?> getBool(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).getBool(key);
    }
    return _async().getBool(key);
  }

  Future<void> setBool(String key, bool value) async {
    if (_useTestPrefs) {
      await (await _legacy()).setBool(key, value);
      return;
    }
    await _async().setBool(key, value);
  }

  Future<int?> getInt(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).getInt(key);
    }
    return _async().getInt(key);
  }

  Future<void> setInt(String key, int value) async {
    if (_useTestPrefs) {
      await (await _legacy()).setInt(key, value);
      return;
    }
    await _async().setInt(key, value);
  }

  Future<double?> getDouble(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).getDouble(key);
    }
    return _async().getDouble(key);
  }

  Future<void> setDouble(String key, double value) async {
    if (_useTestPrefs) {
      await (await _legacy()).setDouble(key, value);
      return;
    }
    await _async().setDouble(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).getStringList(key);
    }
    return _async().getStringList(key);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    if (_useTestPrefs) {
      await (await _legacy()).setStringList(key, value);
      return;
    }
    await _async().setStringList(key, value);
  }

  Future<bool> containsKey(String key) async {
    if (_useTestPrefs) {
      return (await _legacy()).containsKey(key);
    }
    return _async().containsKey(key);
  }

  // ignore: unused_element
  Future<Set<String>> getKeys({Set<String>? allowList}) async {
    if (_useTestPrefs) {
      final Set<String> keys = (await _legacy()).getKeys();
      if (allowList == null) return keys;
      return keys.where(allowList.contains).toSet();
    }
    return _async().getKeys(allowList: allowList);
  }

  @override
  Future<void> remove(String key) async {
    if (_useTestPrefs) {
      await (await _legacy()).remove(key);
      return;
    }
    await _async().remove(key);
  }

  Future<void> clear({Set<String>? allowList}) async {
    if (_useTestPrefs) {
      final SharedPreferences prefs = await _legacy();
      if (allowList == null) {
        await prefs.clear();
      } else {
        for (final String key in allowList) {
          await prefs.remove(key);
        }
      }
      return;
    }
    await _async().clear(allowList: allowList);
  }

  Future<void> reload() async {
    if (_useTestPrefs) {
      await (await _legacy()).reload();
    }
    // SharedPreferencesAsync reads directly from platform storage with no cache.
  }
}

/// Uses FlutterSecureStorage for sensitive credentials (refresh token)
/// with volatile in-memory fallback, and [_PrefsStore] / [ReservationStore]
/// for app settings, cache, and unified reservation persistence.
class StorageService {
  static const _PrefsStore _prefs = _PrefsStore();
  static final ReservationStore _defaultReservationStore =
      ReservationStore(backend: _prefs);

  final FlutterSecureStorage _secureStorage;
  final bool _useSecureStorage;
  final ReservationStore _reservationStore;

  StorageService({
    FlutterSecureStorage? secureStorage,
    ReservationStore? reservationStore,
  })  : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: false),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            ),
        _useSecureStorage =
            secureStorage != null || kIsWeb || !_isFlutterTestEnvironment(),
        _reservationStore = reservationStore ?? _defaultReservationStore;

  ReservationStore get reservationStore => _reservationStore;

  static bool _isFlutterTestEnvironment() {
    if (kIsWeb) return false;
    if (const bool.fromEnvironment('FLUTTER_TEST')) return true;
    try {
      final bindingType = WidgetsBinding.instance.runtimeType.toString();
      if (bindingType.contains('Test')) {
        return true;
      }
    } catch (_) {}
    return Zone.current[#test.invoker] != null;
  }

  static const String _refreshTokenKey = 'refresh_token';
  static const String _rememberEmailKey = 'remember_email';
  static const String _savedEmailKey = 'saved_email';
  static const String _mapSelectedFloorIdKey = 'map_selected_floor_id';
  static const int _maxFloorCacheEntries = 12;

  /// Strictly volatile RAM-only fallback when secure storage is blocked/locked.
  /// Never persisted in plaintext to SharedPreferences.
  static String? _volatileRefreshToken;

  static final Map<String, ({String rawJson, dynamic value})> _planCache =
      <String, ({String rawJson, dynamic value})>{};
  static final Map<String, ({String rawJson, List<Map<String, dynamic>> value})>
      _floorWorkspacesCache =
      <String, ({String rawJson, List<Map<String, dynamic>> value})>{};
  static final Map<String, ({String rawJson, Map<String, DeskOccupant> value})>
      _floorOccupantsCache =
      <String, ({String rawJson, Map<String, DeskOccupant> value})>{};
  static ({String rawJson, List<AutomationRule> value})? _automationRulesCache;

  static void _putBoundedCache<K, V>(Map<K, V> cache, K key, V value) {
    if (cache.containsKey(key)) {
      cache.remove(key);
    } else if (cache.length >= _maxFloorCacheEntries) {
      cache.remove(cache.keys.first);
    }
    cache[key] = value;
  }

  /// Clears all in-memory decoded JSON caches.
  void clearMemoryCache() {
    _planCache.clear();
    _floorWorkspacesCache.clear();
    _floorOccupantsCache.clear();
    _automationRulesCache = null;
    _reservationStore.clearCache();
  }

  /// Clears in-memory caches and reloads SharedPreferences from disk.
  Future<void> reloadFromDisk() async {
    clearMemoryCache();
    await _prefs.reload();
  }

  static dynamic _clonePlanData(dynamic data) {
    if (data is List<Object?>) {
      return data.map<dynamic>(_clonePlanData).toList();
    }
    if (data is Map<Object?, Object?>) {
      return data.map<String, dynamic>(
        (k, v) => MapEntry<String, dynamic>(k.toString(), _clonePlanData(v)),
      );
    }
    return data;
  }

  static Map<String, dynamic> _cloneStringMap(Map<Object?, Object?> source) {
    return source.map<String, dynamic>(
      (k, v) => MapEntry<String, dynamic>(k.toString(), _clonePlanData(v)),
    );
  }

  static List<Map<String, dynamic>> _cloneWorkspaceList(
    List<Map<String, dynamic>> list,
  ) {
    return list.map<Map<String, dynamic>>(_cloneStringMap).toList();
  }

  static Map<String, String> _decodeStringMap(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return <String, String>{};
    }
    try {
      final Object? decoded = jsonDecode(jsonStr);
      if (decoded is Map<Object?, Object?>) {
        return decoded.map<String, String>(
          (k, v) => MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return <String, String>{};
  }

  // ── Remember Email (Milestone M1 - Requirement R1) ─────────────────────────

  Future<void> saveRememberEmail(bool remember) async {
    await _prefs.setBool(_rememberEmailKey, remember);
  }

  Future<bool> getRememberEmail() async {
    return await _prefs.getBool(_rememberEmailKey) ?? true;
  }

  Future<void> saveSavedEmail(String email) async {
    await _prefs.setString(_savedEmailKey, email);
  }

  Future<String?> getSavedEmail() async {
    return _prefs.getString(_savedEmailKey);
  }

  Future<void> clearSavedEmail() async {
    await _prefs.remove(_savedEmailKey);
  }

  // === UI Settings ===

  Future<void> saveIgnoredUpdateVersion(String version) async {
    await _prefs.setString('ignored_update_version', version);
  }

  Future<String?> getIgnoredUpdateVersion() async {
    return _prefs.getString('ignored_update_version');
  }

  Future<void> saveShowDelegatedBookings(bool show) async {
    await _prefs.setBool('show_delegated_bookings', show);
  }

  Future<bool> getShowDelegatedBookings() async {
    return await _prefs.getBool('show_delegated_bookings') ?? true;
  }

  Future<void> saveDelegatedDates(List<String> dates) async {
    await _prefs.setStringList('delegated_dates', dates);
  }

  Future<List<String>> getDelegatedDates() async {
    return await _prefs.getStringList('delegated_dates') ?? <String>[];
  }

  Future<void> savePullToRefresh(bool enabled) async {
    await _prefs.setBool('pull_to_refresh', enabled);
  }

  Future<bool> getPullToRefresh() async {
    return await _prefs.getBool('pull_to_refresh') ?? true;
  }

  Future<void> saveShowAutomation(bool show) async {
    await _prefs.setBool('show_automation_card', show);
  }

  Future<bool> getShowAutomation() async {
    return await _prefs.getBool('show_automation_card') ?? true;
  }

  Future<void> saveShowStats(bool show) async {
    await _prefs.setBool('show_stats_card', show);
  }

  Future<bool> getShowStats() async {
    return await _prefs.getBool('show_stats_card') ?? true;
  }

  static const String _showFavoriteWeekIndicatorsKey =
      'show_favorite_week_indicators';

  Future<void> saveShowFavoriteWeekIndicators(bool show) async {
    await _prefs.setBool(_showFavoriteWeekIndicatorsKey, show);
  }

  Future<bool> getShowFavoriteWeekIndicators() async {
    return await _prefs.getBool(_showFavoriteWeekIndicatorsKey) ?? true;
  }

  static const String _skipPublicHolidaysKey = 'skip_public_holidays';
  static const String _holidayCountryCodeKey = 'holiday_country_code';

  Future<void> saveSkipPublicHolidays(bool skip) async {
    await _prefs.setBool(_skipPublicHolidaysKey, skip);
  }

  Future<bool> getSkipPublicHolidays() async {
    return await _prefs.getBool(_skipPublicHolidaysKey) ?? true;
  }

  Future<void> saveHolidayCountryCode(String code) async {
    await _prefs.setString(_holidayCountryCodeKey, code);
  }

  Future<String> getHolidayCountryCode() async {
    return await _prefs.getString(_holidayCountryCodeKey) ?? 'FR';
  }

  // ── Token ─────────────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) async {
    if (!_useSecureStorage) {
      _volatileRefreshToken = null;
      await _prefs.setString(_refreshTokenKey, token);
      return;
    }
    try {
      await _secureStorage.write(key: _refreshTokenKey, value: token);
      _volatileRefreshToken = null;
    } catch (_) {
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
        await _secureStorage.write(key: _refreshTokenKey, value: token);
        _volatileRefreshToken = null;
      } catch (retryError) {
        debugPrint(
          '⚠️ Failed to persist refresh token to secure storage; storing in volatile memory only: $retryError',
        );
        _volatileRefreshToken = token;
      }
    }
  }

  Future<String?> getRefreshToken() async {
    if (!_useSecureStorage) {
      return await _prefs.getString(_refreshTokenKey) ?? _volatileRefreshToken;
    }
    try {
      final secureToken = await _secureStorage.read(key: _refreshTokenKey);
      if (secureToken != null && secureToken.isNotEmpty) {
        return secureToken;
      }
    } catch (_) {
      // Handled: locked keystore, missing Web crypto.subtle, or test channel
    }

    if (_volatileRefreshToken != null && _volatileRefreshToken!.isNotEmpty) {
      return _volatileRefreshToken;
    }

    // Legacy fallback & auto-migration
    final legacyToken = await _prefs.getString(_refreshTokenKey);

    if (legacyToken != null && legacyToken.isNotEmpty) {
      try {
        await _secureStorage.write(key: _refreshTokenKey, value: legacyToken);
        // Only delete from SharedPreferences once confirmed written to secure storage
        await _prefs.remove(_refreshTokenKey);
      } catch (_) {
        _volatileRefreshToken = legacyToken;
      }
      return legacyToken;
    }

    return null;
  }

  Future<void> clearAuthToken() async {
    _volatileRefreshToken = null;
    if (_useSecureStorage) {
      try {
        await _secureStorage.delete(key: _refreshTokenKey);
      } catch (_) {}
    }

    await _prefs.remove(_refreshTokenKey);
    await _prefs.remove('access_token');
    await _prefs.remove('token_expiry');
  }

  Future<void> clearTokens() async {
    clearMemoryCache();
    _volatileRefreshToken = null;
    await clearAuthToken();
    final remember = await getRememberEmail();
    if (!remember) {
      await clearSavedEmail();
    }
  }

  // ── Workspace settings ────────────────────────────────────────────────────

  Future<void> saveSiteId(String id) async {
    await _prefs.setString('site_id', id);
  }

  Future<String?> getSiteId() async {
    return _prefs.getString('site_id');
  }

  // Building / Site aliases
  Future<void> saveBuildingId(String id) => saveSiteId(id);
  Future<String?> getBuildingId() => getSiteId();

  Future<void> saveFloorId(String id) async {
    await _prefs.setString('floor_id', id);
  }

  Future<String?> getFloorId() async {
    return _prefs.getString('floor_id');
  }

  Future<void> saveMapSelectedFloorId(String id) async {
    await _prefs.setString(_mapSelectedFloorIdKey, id);
  }

  Future<String?> getMapSelectedFloorId() async {
    return _prefs.getString(_mapSelectedFloorIdKey);
  }

  Future<void> saveWorkspaceId(String id) async {
    await _prefs.setString('workspace_id', id);
  }

  Future<String?> getWorkspaceId() async {
    return _prefs.getString('workspace_id');
  }

  // Room / Workspace aliases
  Future<void> saveRoomId(String id) => saveWorkspaceId(id);
  Future<String?> getRoomId() => getWorkspaceId();

  Future<void> saveWorkspaceName(String name) async {
    await _prefs.setString('workspace_name', name);
  }

  Future<String?> getWorkspaceName() async {
    return _prefs.getString('workspace_name');
  }

  Future<void> resetWorkspace() async {
    clearMemoryCache();
    await _prefs.remove('floor_id');
    await _prefs.remove(_mapSelectedFloorIdKey);
    await _prefs.remove('workspace_id');
    await _prefs.remove('workspace_name');
  }

  // ── Calendar Dates ────────────────────────────────────────────────────────

  Future<void> saveRequestedDates(List<String> dates) async {
    await _prefs.setStringList('requested_dates', dates);
  }

  Future<List<String>> getRequestedDates() async {
    return await _prefs.getStringList('requested_dates') ?? <String>[];
  }

  Future<Map<String, String>> getRequestedWorkspacesMap() async {
    return _decodeStringMap(await _prefs.getString('requested_workspaces_map'));
  }

  Future<void> saveRequestedWorkspacesMap(Map<String, String> map) async {
    await _prefs.setString('requested_workspaces_map', jsonEncode(map));
  }

  Future<Map<String, String>> getRequestedWorkspaceNamesMap() async {
    return _decodeStringMap(
      await _prefs.getString('requested_workspace_names_map'),
    );
  }

  Future<void> saveRequestedWorkspaceNamesMap(Map<String, String> map) async {
    await _prefs.setString('requested_workspace_names_map', jsonEncode(map));
  }

  /// Associates a specific [workspaceId] (and optional [workspaceName]) to a requested [date].
  /// If [workspaceId] is null or empty, removes the association for that date.
  Future<void> saveRequestedWorkspace(
    String date,
    String? workspaceId, {
    String? workspaceName,
  }) async {
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
  Future<void> addRequestedDate(
    String date, {
    String? workspaceId,
    String? workspaceName,
  }) async {
    final dates = await getRequestedDates();
    if (!dates.contains(date)) {
      dates.add(date);
      await saveRequestedDates(dates);
    }
    if (workspaceId != null && workspaceId.isNotEmpty) {
      await saveRequestedWorkspace(
        date,
        workspaceId,
        workspaceName: workspaceName,
      );
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
  Future<void> toggleRequestedDate(
    String date, {
    String? workspaceId,
    String? workspaceName,
  }) async {
    final dates = await getRequestedDates();
    if (dates.contains(date)) {
      dates.remove(date);
      await saveRequestedDates(dates);
      await saveRequestedWorkspace(date, null);
    } else {
      dates.add(date);
      await saveRequestedDates(dates);
      if (workspaceId != null && workspaceId.isNotEmpty) {
        await saveRequestedWorkspace(
          date,
          workspaceId,
          workspaceName: workspaceName,
        );
      }
    }
  }

  Future<void> saveBookedDates(List<String> dates) async {
    await _reservationStore.replaceHereDates(
      dates,
      defaultWorkspaceId: await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  Future<List<String>> getBookedDates() async {
    final Set<String> dates = await _reservationStore.hereDates(
      await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
    return dates.toList();
  }

  Future<void> saveIgnoredDates(List<String> dates) async {
    await _prefs.setStringList('ignored_dates', dates);
  }

  Future<List<String>> getIgnoredDates() async {
    return await _prefs.getStringList('ignored_dates') ?? <String>[];
  }

  Future<void> saveBookedElsewhereDates(List<String> dates) async {
    await _reservationStore.replaceElsewhereDates(
      dates,
      defaultWorkspaceId: await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  // --- ALL-TIME STATS TRACKING ---
  Future<void> saveAllTimeBookedDates(List<String> dates) async {
    await _reservationStore.mergeAllTimeBookedDates(
      dates,
      defaultWorkspaceId: await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  Future<List<String>> getAllTimeBookedDates() async {
    return _reservationStore.allTimeBookedDates(
      await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  Future<void> saveAllTimeElsewhereDates(List<String> dates) async {
    await _reservationStore.mergeAllTimeElsewhereDates(dates);
  }

  Future<List<String>> getAllTimeElsewhereDates() async {
    return _reservationStore.allTimeElsewhereDates(
      await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }
  // -------------------------------

  Future<Map<String, String>> getDelegatedBookingsMap() async {
    return _decodeStringMap(await _prefs.getString('delegated_bookings_map'));
  }

  Future<void> saveDelegatedBookingsMap(Map<String, String> map) async {
    await _prefs.setString('delegated_bookings_map', jsonEncode(map));
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
  Future<String?> getDelegatedBooking(
    String date, [
    String? workspaceId,
  ]) async {
    final map = await getDelegatedBookingsMap();
    if (workspaceId != null && workspaceId.isNotEmpty) {
      final compositeKey = '$date#$workspaceId';
      if (map.containsKey(compositeKey)) {
        return map[compositeKey];
      }
      for (final entry in map.entries) {
        if (entry.key.startsWith('$date#')) {
          final keyWs = entry.key.substring(date.length + 1);
          if (keyWs == workspaceId ||
              entry.value.split('|').first == workspaceId) {
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

    map.removeWhere(
      (key, val) =>
          key.startsWith('$date#') &&
          (key.substring(date.length + 1) == workspaceId ||
              val.split('|').first == workspaceId),
    );

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
    final Map<String, String> elsewhere = await getBookedElsewhereMap();
    return elsewhere.keys.toList();
  }

  // ── Personal Elsewhere Reservations Map ───────────────────────────────────
  Future<void> saveBookedElsewhereMap(Map<String, String> map) async {
    await _reservationStore.replaceElsewhereMap(
      map,
      defaultWorkspaceId: await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  Future<Map<String, String>> getBookedElsewhereMap() async {
    return _reservationStore.elsewhereMap(
      await getWorkspaceId(),
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  // ── Enriched User Reservations Map per Date ──────────────────────────────

  /// Retrieves the enriched reservations map: { "YYYY-MM-DD": { "workspaceId": "...", "workspaceName": "..." } }
  Future<Map<String, Map<String, String>>> getUserReservationsMap() async {
    return _reservationStore.toLegacyUserReservationsMap();
  }

  /// Persists the enriched reservations map to the canonical `reservations_v2` store.
  Future<void> saveUserReservationsMap(
    Map<String, Map<String, String>> map,
  ) async {
    await _reservationStore.replaceFromLegacyUserReservationsMap(map);
  }

  /// Saves or updates a single user reservation.
  Future<void> saveUserReservation(
    String date,
    String workspaceId,
    String workspaceName,
  ) async {
    await _reservationStore.upsert(
      ReservationEntry(
        dateIso: date,
        workspaceId: workspaceId,
        workspaceName: workspaceName,
        updatedAt: DateTime.now().toIso8601String(),
      ),
    );
  }

  /// Removes a single user reservation.
  Future<void> removeUserReservation(String date) async {
    await _reservationStore.remove(date);
  }

  /// Dynamically partitions all cached reservations against the provided [currentWorkspaceId].
  Future<({Set<String> here, Map<String, String> elsewhere})>
      partitionUserReservations(String? currentWorkspaceId) async {
    return _reservationStore.partition(
      currentWorkspaceId,
      defaultWorkspaceName: await getWorkspaceName(),
    );
  }

  // ── Calendar Occupied by Others Map ───────────────────────────────────────
  Future<void> saveOccupiedByOthers(Map<String, String> map) async {
    await _prefs.setString('occupied_by_others_map', jsonEncode(map));
  }

  Future<Map<String, String>> getOccupiedByOthers() async {
    return _decodeStringMap(await _prefs.getString('occupied_by_others_map'));
  }

  // ── Days (recurring) ──────────────────────────────────────────────────────

  Future<void> saveDays(List<int> days) async {
    await _prefs.setStringList(
      'selected_days',
      days.map((e) => e.toString()).toList(),
    );
  }

  Future<List<int>> getDays() async {
    final days = await _prefs.getStringList('selected_days');
    // Default to Tue (2) and Thu (4) — matching the original Python script
    return days?.map(int.parse).toList() ?? <int>[2, 4];
  }

  Future<void> saveAutomationEnabled(bool enabled) async {
    await _prefs.setBool('automation_enabled', enabled);
  }

  Future<bool> getAutomationEnabled() async {
    return await _prefs.getBool('automation_enabled') ?? false;
  }

  // ── Multi-Desk Automation Rules (v1.7.0) ──────────────────────────────────

  static const String _automationRulesKey = 'automation_rules_v1';

  Future<bool> hasAutomationRules() async {
    return _prefs.containsKey(_automationRulesKey);
  }

  Future<List<AutomationRule>> getAutomationRules() async {
    final jsonStr = await _prefs.getString(_automationRulesKey);
    if (jsonStr == null) {
      _automationRulesCache = null;
      final wsId = await getWorkspaceId();
      if (wsId != null && wsId.isNotEmpty) {
        final siteId = await getSiteId() ?? '';
        final floorId = await getFloorId() ?? '';
        final rawWsName = await getWorkspaceName();
        final wsName =
            (rawWsName != null && rawWsName.isNotEmpty) ? rawWsName : wsId;
        final legacyDays = AutomationRule.normalizeDays(await getDays());
        final migrated = <AutomationRule>[
          AutomationRule(
            id: wsId,
            siteId: siteId,
            floorId: floorId,
            workspaceId: wsId,
            workspaceName: wsName,
            days: legacyDays,
          ),
        ];
        await saveAutomationRules(migrated);
        return migrated;
      }
      return <AutomationRule>[];
    }

    if (jsonStr.isEmpty) {
      _automationRulesCache = null;
      return <AutomationRule>[];
    }
    final cached = _automationRulesCache;
    if (cached != null && cached.rawJson == jsonStr) {
      return List<AutomationRule>.from(cached.value);
    }
    try {
      final Object? decoded = jsonDecode(jsonStr);
      if (decoded is List<Object?>) {
        final parsed = decoded
            .whereType<Map<Object?, Object?>>()
            .map((e) => AutomationRule.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _automationRulesCache = (
          rawJson: jsonStr,
          value: List<AutomationRule>.unmodifiable(parsed),
        );
        return parsed;
      }
    } catch (_) {}
    return <AutomationRule>[];
  }

  Future<void> saveAutomationRules(List<AutomationRule> rules) async {
    _automationRulesCache = null;
    final seenDays = <int>{};
    final normalized = <AutomationRule>[];
    for (final rule in rules) {
      final uniqueDays = <int>[];
      for (final d in AutomationRule.normalizeDays(rule.days)) {
        if (seenDays.add(d)) {
          uniqueDays.add(d);
        }
      }
      normalized.add(rule.copyWith(days: uniqueDays));
    }

    await _prefs.setString(
      _automationRulesKey,
      jsonEncode(normalized.map((r) => r.toJson()).toList()),
    );

    final allAssignedDays =
        normalized.expand((r) => r.days).toSet().toList()..sort();
    await saveDays(allAssignedDays);
  }

  Future<AutomationRule?> getAutomationRuleForWeekday(int weekday) async {
    final rules = await getAutomationRules();
    for (final rule in rules) {
      if (rule.days.contains(weekday)) {
        return rule;
      }
    }
    return null;
  }

  Future<Map<int, AutomationRule>> getWeekdayAutomationMap() async {
    final rules = await getAutomationRules();
    final map = <int, AutomationRule>{};
    for (final rule in rules) {
      for (final day in rule.days) {
        map.putIfAbsent(day, () => rule);
      }
    }
    return map;
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<bool?> getDarkMode() async {
    return _prefs.getBool('dark_mode');
  }

  Future<void> saveDarkMode(bool isDark) async {
    await _prefs.setBool('dark_mode', isDark);
  }

  Future<void> saveAutomationTime(int hour, int minute) async {
    await _prefs.setInt('auto_time_hour', hour);
    await _prefs.setInt('auto_time_minute', minute);
  }

  Future<Map<String, int>> getAutomationTime() async {
    return <String, int>{
      'hour': await _prefs.getInt('auto_time_hour') ?? 8,
      'minute': await _prefs.getInt('auto_time_minute') ?? 0,
    };
  }

  Future<void> saveNotifySuccess(bool val) async {
    await _prefs.setBool('notify_success', val);
  }

  Future<bool> getNotifySuccess() async {
    return await _prefs.getBool('notify_success') ?? true;
  }

  Future<void> saveNotifyFailure(bool val) async {
    await _prefs.setBool('notify_failure', val);
  }

  Future<bool> getNotifyFailure() async {
    return await _prefs.getBool('notify_failure') ?? true;
  }

  Future<void> saveThemeColorIndex(int index) async {
    await _prefs.setInt('theme_color_index', index);
  }

  Future<int> getThemeColorIndex() async {
    return await _prefs.getInt('theme_color_index') ?? 0;
  }

  Future<void> saveAutoSync(bool val) async {
    await _prefs.setBool('auto_sync', val);
  }

  Future<bool> getAutoSync() async {
    return await _prefs.getBool('auto_sync') ?? true;
  }

  Future<void> saveProjectionsCount(int val) async {
    await _prefs.setInt('projections_count', val);
  }

  Future<int> getProjectionsCount() async {
    return await _prefs.getInt('projections_count') ?? 4;
  }

  Future<void> saveInitialTab(int val) async {
    await _prefs.setInt('initial_tab', val);
  }

  Future<int> getInitialTab() async {
    return await _prefs.getInt('initial_tab') ?? 0;
  }

  Future<void> saveThemeModeIndex(int val) async {
    await _prefs.setInt('theme_mode', val);
  }

  Future<int> getThemeModeIndex() async {
    return await _prefs.getInt('theme_mode') ?? 0; // 0: system, 1: light, 2: dark
  }

  // ── Hide weekends in calendar ─────────────────────────────────────────────

  Future<void> saveHideWeekends(bool val) async {
    await _prefs.setBool('hide_weekends', val);
  }

  Future<bool> getHideWeekends() async {
    return await _prefs.getBool('hide_weekends') ?? true;
  }

  // ── Last sync timestamp (cache TTL) ──────────────────────────────────────

  Future<void> saveLastSyncTime({bool forceReset = false}) async {
    if (forceReset) {
      await _prefs.remove('last_sync_time');
    } else {
      await _prefs.setInt(
        'last_sync_time',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<DateTime?> getLastSyncTime() async {
    final ms = await _prefs.getInt('last_sync_time');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  // ── New Customizations ───────────────────────────────────────────────────

  Future<void> saveVacations(List<Map<String, String>> vacations) async {
    await _prefs.setString('vacation_periods', jsonEncode(vacations));
  }

  Future<List<Map<String, String>>> getVacations() async {
    final jsonString = await _prefs.getString('vacation_periods');
    if (jsonString != null) {
      try {
        final Object? decoded = jsonDecode(jsonString);
        if (decoded is List<Object?>) {
          return decoded
              .whereType<Map<Object?, Object?>>()
              .map(
                (e) => e.map<String, String>(
                  (k, v) =>
                      MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
                ),
              )
              .toList();
        }
      } catch (_) {}
      return <Map<String, String>>[];
    } else {
      // Backward-compat: migrate old single-vacation keys
      final oldStart = await _prefs.getString('vacation_start');
      final oldEnd = await _prefs.getString('vacation_end');
      if (oldStart != null && oldEnd != null) {
        return <Map<String, String>>[
          <String, String>{'start': oldStart, 'end': oldEnd},
        ];
      }
      return <Map<String, String>>[];
    }
  }

  // Kept for background_task backward-compat
  Future<Map<String, String?>> getVacationDates() async {
    return <String, String?>{
      'start': await _prefs.getString('vacation_start'),
      'end': await _prefs.getString('vacation_end'),
    };
  }

  Future<void> saveCompactMode(bool val) async {
    await _prefs.setBool('compact_mode', val);
  }

  Future<bool> getCompactMode() async {
    return await _prefs.getBool('compact_mode') ?? false;
  }

  Future<void> saveFontFamilyIndex(int val) async {
    await _prefs.setInt('font_family_index', val);
  }

  Future<int> getFontFamilyIndex() async {
    return await _prefs.getInt('font_family_index') ?? 0;
  }

  Future<void> saveUiScale(double val) async {
    await _prefs.setDouble('ui_scale', val);
  }

  Future<double> getUiScale() async {
    return await _prefs.getDouble('ui_scale') ?? 1.0;
  }

  // ── Clear all (logout) ────────────────────────────────────────────────────

  Future<void> saveHasSeenOptimization(bool val) async {
    await _prefs.setBool('has_seen_optimization', val);
  }

  Future<bool> getHasSeenOptimization() async {
    return await _prefs.getBool('has_seen_optimization') ?? false;
  }

  Future<void> saveAutostartVerified(bool val) async {
    await _prefs.setBool('autostart_verified', val);
  }

  Future<void> saveBatteryVerified(bool val) async {
    await _prefs.setBool('battery_verified', val);
  }

  Future<bool> getBatteryVerified() async {
    return await _prefs.getBool('battery_verified') ?? false;
  }

  Future<bool> getAutostartVerified() async {
    return await _prefs.getBool('autostart_verified') ?? false;
  }

  Future<void> saveLastAutomationRun() async {
    await _prefs.setInt(
      'last_automation_run',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> getLastAutomationRun() async {
    final ms = await _prefs.getInt('last_automation_run');
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> clearAll() async {
    clearMemoryCache();
    _volatileRefreshToken = null;
    final remember = await getRememberEmail();
    final savedEmail = remember ? await getSavedEmail() : null;

    if (_useSecureStorage) {
      try {
        await _secureStorage.deleteAll();
      } catch (_) {}
    }

    await _prefs.clear();

    if (remember && savedEmail != null && savedEmail.isNotEmpty) {
      await _prefs.setBool(_rememberEmailKey, true);
      await _prefs.setString(_savedEmailKey, savedEmail);
    }
  }

  Future<void> clearAllData() async {
    clearMemoryCache();
    _volatileRefreshToken = null;
    await clearAll();
  }

  // 📊 Stats Tracking
  Future<void> recordFirstUse() async {
    if (!await _prefs.containsKey('stats_first_use')) {
      await _prefs.setString(
        'stats_first_use',
        DateTime.now().toIso8601String(),
      );
    }
  }

  Future<DateTime> getFirstUse() async {
    final d = await _prefs.getString('stats_first_use');
    if (d != null) {
      return DateTime.parse(d);
    } else {
      final now = DateTime.now();
      await _prefs.setString('stats_first_use', now.toIso8601String());
      return now;
    }
  }

  Future<void> recordBookingStat(bool isAuto) async {
    if (isAuto) {
      final count = await _prefs.getInt('stats_auto_count') ?? 0;
      await _prefs.setInt('stats_auto_count', count + 1);
    } else {
      final count = await _prefs.getInt('stats_manual_count') ?? 0;
      await _prefs.setInt('stats_manual_count', count + 1);
    }
  }

  Future<Map<String, int>> getBookingStats() async {
    await _prefs.reload();
    return <String, int>{
      'manual': await _prefs.getInt('stats_manual_count') ?? 0,
      'auto': await _prefs.getInt('stats_auto_count') ?? 0,
    };
  }

  // ── Favorite Colleagues (Milestone M2 - Requirement R2) ───────────────────

  Future<List<Colleague>> getFavoriteColleagues() async {
    final jsonStr = await _prefs.getString('favorite_colleagues');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(jsonStr);
        if (decoded is List<Object?>) {
          return decoded
              .whereType<Map<Object?, Object?>>()
              .map((item) => Colleague.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      } catch (_) {}
    }
    return <Colleague>[];
  }

  Future<void> saveFavoriteColleagues(List<Colleague> colleagues) async {
    final jsonStr = jsonEncode(colleagues.map((c) => c.toJson()).toList());
    await _prefs.setString('favorite_colleagues', jsonStr);
  }

  Future<void> mergeFavoriteColleagues(List<Colleague> apiFavorites) async {
    final current = await getFavoriteColleagues();
    final merged = <Colleague>[];
    final matchedApiIndices = <int>{};

    for (final local in current) {
      final apiIndex = apiFavorites.indexWhere(
        (api) =>
            (local.id.isNotEmpty && api.id.isNotEmpty && local.id == api.id) ||
            (local.favoriteId != null &&
                api.favoriteId != null &&
                local.favoriteId == api.favoriteId) ||
            (local.email.isNotEmpty &&
                api.email.isNotEmpty &&
                local.email.toLowerCase() == api.email.toLowerCase()),
      );

      if (apiIndex >= 0) {
        matchedApiIndices.add(apiIndex);
        final apiColleague = apiFavorites[apiIndex];
        merged.add(
          apiColleague.copyWith(
            isFavorite: true,
            favoriteId: apiColleague.favoriteId ?? local.favoriteId,
          ),
        );
      } else {
        merged.add(local.copyWith(isFavorite: true));
      }
    }

    for (int i = 0; i < apiFavorites.length; i++) {
      if (!matchedApiIndices.contains(i)) {
        final apiColleague = apiFavorites[i];
        final exists = merged.any(
          (c) =>
              (c.id.isNotEmpty &&
                  apiColleague.id.isNotEmpty &&
                  c.id == apiColleague.id) ||
              (c.email.isNotEmpty &&
                  apiColleague.email.isNotEmpty &&
                  c.email.toLowerCase() == apiColleague.email.toLowerCase()),
        );
        if (!exists) {
          merged.add(apiColleague.copyWith(isFavorite: true));
        }
      }
    }

    await saveFavoriteColleagues(merged);
  }

  Future<void> addFavoriteColleague(Colleague colleague) async {
    final current = await getFavoriteColleagues();
    final effectiveId = colleague.id.isNotEmpty
        ? colleague.id
        : 'ext_${DateTime.now().millisecondsSinceEpoch}';
    final updatedColleague =
        colleague.copyWith(id: effectiveId, isFavorite: true);
    final index = current.indexWhere(
      (c) =>
          (c.id.isNotEmpty && effectiveId.isNotEmpty && c.id == effectiveId) ||
          (c.email.isNotEmpty &&
              colleague.email.isNotEmpty &&
              c.email.toLowerCase() == colleague.email.toLowerCase()),
    );
    if (index >= 0) {
      current[index] = updatedColleague;
    } else {
      current.add(updatedColleague);
    }
    await saveFavoriteColleagues(current);
  }

  Future<void> removeFavoriteColleague(String colleagueId) async {
    final current = await getFavoriteColleagues();
    current.removeWhere(
      (c) =>
          c.id == colleagueId ||
          (colleagueId.isNotEmpty &&
              c.email.isNotEmpty &&
              c.email.toLowerCase() == colleagueId.toLowerCase()),
    );
    await saveFavoriteColleagues(current);
  }

  Future<bool> isFavoriteColleague(String colleagueId) async {
    final current = await getFavoriteColleagues();
    return current.any((c) => c.id == colleagueId);
  }

  // ── Floor Occupants Persistence ───────────────────────────────────────────
  Future<void> saveFloorOccupants(
    String floorId,
    String date,
    Map<String, DeskOccupant> occupants,
  ) async {
    _floorOccupantsCache.remove('${floorId}_$date');
    final jsonMap = occupants.map<String, Map<String, dynamic>>(
      (k, v) => MapEntry<String, Map<String, dynamic>>(k, v.toJson()),
    );
    await _prefs.setString(
      'floor_occupants_${floorId}_$date',
      jsonEncode(jsonMap),
    );
  }

  Future<Map<String, DeskOccupant>> getFloorOccupants(
    String floorId,
    String date,
  ) async {
    final cacheKey = '${floorId}_$date';
    final jsonStr = await _prefs.getString('floor_occupants_${floorId}_$date');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final cached = _floorOccupantsCache[cacheKey];
      if (cached != null && cached.rawJson == jsonStr) {
        return Map<String, DeskOccupant>.from(cached.value);
      }
      try {
        final Object? decoded = jsonDecode(jsonStr);
        if (decoded is Map<Object?, Object?>) {
          final parsed = <String, DeskOccupant>{};
          decoded.forEach((Object? k, Object? v) {
            if (v is Map<Object?, Object?>) {
              parsed[k.toString()] = DeskOccupant.fromJson(
                Map<String, dynamic>.from(v),
              );
            }
          });
          _putBoundedCache(
            _floorOccupantsCache,
            cacheKey,
            (
              rawJson: jsonStr,
              value: Map<String, DeskOccupant>.unmodifiable(parsed),
            ),
          );
          return parsed;
        }
      } catch (_) {}
    } else {
      _floorOccupantsCache.remove(cacheKey);
    }
    return <String, DeskOccupant>{};
  }

  // ── Floor Plan & Workspaces Persistence ───────────────────────────────────
  Future<void> saveFloorPlanData(String floorId, dynamic planData) async {
    _planCache.remove(floorId);
    await _prefs.setString('floor_plan_$floorId', jsonEncode(planData));
  }

  Future<dynamic> getFloorPlanData(String floorId) async {
    final jsonStr = await _prefs.getString('floor_plan_$floorId');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final cached = _planCache[floorId];
      if (cached != null && cached.rawJson == jsonStr) {
        return _clonePlanData(cached.value);
      }
      try {
        final Object? decoded = jsonDecode(jsonStr);
        _putBoundedCache(
          _planCache,
          floorId,
          (rawJson: jsonStr, value: _clonePlanData(decoded)),
        );
        return _clonePlanData(decoded);
      } catch (_) {}
    } else {
      _planCache.remove(floorId);
    }
    return null;
  }

  Future<void> saveFloorWorkspaces(
    String floorId,
    List<Map<String, dynamic>> workspaces,
  ) async {
    _floorWorkspacesCache.remove(floorId);
    await _prefs.setString('floor_workspaces_$floorId', jsonEncode(workspaces));
  }

  Future<List<Map<String, dynamic>>> getFloorWorkspaces(String floorId) async {
    final jsonStr = await _prefs.getString('floor_workspaces_$floorId');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      final cached = _floorWorkspacesCache[floorId];
      if (cached != null && cached.rawJson == jsonStr) {
        return _cloneWorkspaceList(cached.value);
      }
      try {
        final Object? decoded = jsonDecode(jsonStr);
        if (decoded is List<Object?>) {
          final parsed = decoded
              .whereType<Map<Object?, Object?>>()
              .map<Map<String, dynamic>>(_cloneStringMap)
              .toList();
          _putBoundedCache(
            _floorWorkspacesCache,
            floorId,
            (
              rawJson: jsonStr,
              value: _cloneWorkspaceList(parsed),
            ),
          );
          return parsed;
        }
      } catch (_) {}
    } else {
      _floorWorkspacesCache.remove(floorId);
    }
    return <Map<String, dynamic>>[];
  }

  // ── Cached Sites & Floors Persistence ─────────────────────────────────────
  Future<void> saveCachedSites(List<Map<String, dynamic>> sites) async {
    await _prefs.setString('cached_sites', jsonEncode(sites));
  }

  Future<List<Map<String, dynamic>>> getCachedSites() async {
    final jsonStr = await _prefs.getString('cached_sites');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(jsonStr);
        if (decoded is List<Object?>) {
          return decoded
              .whereType<Map<Object?, Object?>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> saveCachedFloors(
    String siteId,
    List<Map<String, dynamic>> floors,
  ) async {
    await _prefs.setString('cached_floors_$siteId', jsonEncode(floors));
  }

  Future<List<Map<String, dynamic>>> getCachedFloors(String siteId) async {
    final jsonStr = await _prefs.getString('cached_floors_$siteId');
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final Object? decoded = jsonDecode(jsonStr);
        if (decoded is List<Object?>) {
          return decoded
              .whereType<Map<Object?, Object?>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
    }
    return <Map<String, dynamic>>[];
  }
}
