import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage_service.dart';

/// Minimal async key-value backend used by [ReservationStore].
abstract interface class ReservationPrefsBackend {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<List<String>?> getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
}

class _DefaultReservationPrefsBackend implements ReservationPrefsBackend {
  const _DefaultReservationPrefsBackend();

  Future<SharedPreferencesAsync> _readyAsync() async {
    await StorageService.ensureLegacyPrefsMigrated();
    return SharedPreferencesAsync();
  }

  @override
  Future<String?> getString(String key) async {
    if (StorageService.isFlutterTestEnvironment()) {
      return (await SharedPreferences.getInstance()).getString(key);
    }
    return (await _readyAsync()).getString(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    if (StorageService.isFlutterTestEnvironment()) {
      await (await SharedPreferences.getInstance()).setString(key, value);
      return;
    }
    await (await _readyAsync()).setString(key, value);
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    if (StorageService.isFlutterTestEnvironment()) {
      return (await SharedPreferences.getInstance()).getStringList(key);
    }
    return (await _readyAsync()).getStringList(key);
  }

  @override
  Future<void> setStringList(String key, List<String> value) async {
    if (StorageService.isFlutterTestEnvironment()) {
      await (await SharedPreferences.getInstance()).setStringList(key, value);
      return;
    }
    await (await _readyAsync()).setStringList(key, value);
  }

  @override
  Future<void> remove(String key) async {
    if (StorageService.isFlutterTestEnvironment()) {
      await (await SharedPreferences.getInstance()).remove(key);
      return;
    }
    await (await _readyAsync()).remove(key);
  }
}

/// Unified canonical store for user reservations backed by a single JSON key
/// (`reservations_v2`), replacing the 6 redundant legacy keys while performing
/// automatic idempotent migration and reconciliation.
class ReservationStore {
  static const String storageKey = 'reservations_v2';
  static const int historyRetentionDays = 400;

  static const String _legacyUserReservationsMapKey = 'user_reservations_map';
  static const String _legacyBookedDatesKey = 'booked_dates';
  static const String _legacyBookedElsewhereDatesKey =
      'booked_elsewhere_dates';
  static const String _legacyBookedElsewhereMapKey = 'booked_elsewhere_map';
  static const String _legacyAllTimeBookedDatesKey = 'all_time_booked_dates';
  static const String _legacyAllTimeElsewhereDatesKey =
      'all_time_elsewhere_dates';

  static const List<String> _legacyKeys = <String>[
    _legacyUserReservationsMapKey,
    _legacyBookedDatesKey,
    _legacyBookedElsewhereDatesKey,
    _legacyBookedElsewhereMapKey,
    _legacyAllTimeBookedDatesKey,
    _legacyAllTimeElsewhereDatesKey,
  ];

  final ReservationPrefsBackend _backend;
  final DateTime Function() _nowProvider;

  ({String rawJson, Map<String, ReservationEntry> entries})? _cache;

  ReservationStore({
    ReservationPrefsBackend? backend,
    DateTime Function()? nowProvider,
  })  : _backend = backend ?? const _DefaultReservationPrefsBackend(),
        _nowProvider = nowProvider ?? DateTime.now;

  /// Clears the in-memory decoded JSON cache.
  void clearCache() {
    _cache = null;
  }

  static String _formatIsoDate(DateTime dt) {
    final String y = dt.year.toString().padLeft(4, '0');
    final String m = dt.month.toString().padLeft(2, '0');
    final String d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime _cutoffDate() {
    final DateTime now = _nowProvider();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return today.subtract(const Duration(days: historyRetentionDays));
  }

  static bool _isWithinRetention(String dateIso, DateTime cutoffDate) {
    final DateTime? parsed = DateTime.tryParse(dateIso);
    if (parsed == null) {
      // Preserve non-ISO strings (e.g. resilience tests) rather than dropping.
      return true;
    }
    final DateTime normalized = DateTime(parsed.year, parsed.month, parsed.day);
    return !normalized.isBefore(cutoffDate);
  }

  static Map<String, ReservationEntry> _decodeV2(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return <String, ReservationEntry>{};
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is Map<Object?, Object?>) {
        final Map<String, ReservationEntry> result =
            <String, ReservationEntry>{};
        decoded.forEach((Object? key, Object? value) {
          if (value is Map<Object?, Object?>) {
            final String dateIso = key.toString();
            result[dateIso] = ReservationEntry.fromJson(
              dateIso,
              value.map<String, dynamic>(
                (Object? k, Object? v) =>
                    MapEntry<String, dynamic>(k.toString(), v),
              ),
            );
          }
        });
        return result;
      }
    } catch (_) {}
    return <String, ReservationEntry>{};
  }

  static Map<String, Map<String, String>> _decodeLegacyUserMap(
    String? rawJson,
  ) {
    if (rawJson == null || rawJson.isEmpty) {
      return <String, Map<String, String>>{};
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is Map<Object?, Object?>) {
        final Map<String, Map<String, String>> result =
            <String, Map<String, String>>{};
        decoded.forEach((Object? key, Object? value) {
          if (value is Map<Object?, Object?>) {
            result[key.toString()] = value.map<String, String>(
              (Object? k, Object? v) =>
                  MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
            );
          }
        });
        return result;
      }
    } catch (_) {}
    return <String, Map<String, String>>{};
  }

  static Map<String, String> _decodeStringMap(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return <String, String>{};
    }
    try {
      final Object? decoded = jsonDecode(rawJson);
      if (decoded is Map<Object?, Object?>) {
        return decoded.map<String, String>(
          (Object? k, Object? v) =>
              MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
        );
      }
    } catch (_) {}
    return <String, String>{};
  }

  static bool _isHereEntry(
    ReservationEntry entry,
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) {
    final String normalizedDefaultId = (defaultWorkspaceId ?? '').trim();
    final String normalizedEntryId = entry.workspaceId.trim();

    if (normalizedDefaultId.isNotEmpty && normalizedEntryId.isNotEmpty) {
      return normalizedEntryId.toLowerCase() ==
          normalizedDefaultId.toLowerCase();
    }

    if (normalizedEntryId.isEmpty) {
      final String normalizedEntryName = entry.workspaceName.trim();
      final String normalizedDefaultName = (defaultWorkspaceName ?? '').trim();
      if (normalizedEntryName == 'Mon bureau') {
        return true;
      }
      if (normalizedDefaultId.isEmpty &&
          normalizedDefaultName.isNotEmpty &&
          normalizedEntryName.isNotEmpty &&
          normalizedEntryName.toLowerCase() ==
              normalizedDefaultName.toLowerCase()) {
        return true;
      }
      return false;
    }

    // Entry has a specific workspaceId while no defaultWorkspaceId is configured:
    // check name fallback only when defaultWorkspaceName matches explicitly.
    final String normalizedDefaultName = (defaultWorkspaceName ?? '').trim();
    if (normalizedDefaultId.isEmpty &&
        normalizedDefaultName.isNotEmpty &&
        entry.workspaceName.trim().isNotEmpty &&
        entry.workspaceName.trim().toLowerCase() ==
            normalizedDefaultName.toLowerCase()) {
      return true;
    }
    return false;
  }

  /// Loads all canonical reservations from `reservations_v2`, automatically
  /// migrating and reconciling any legacy keys present in storage.
  Future<Map<String, ReservationEntry>> loadAll({
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  }) async {
    final String? rawV2 = await _backend.getString(storageKey);
    final String? rawUserMap =
        await _backend.getString(_legacyUserReservationsMapKey);
    final List<String>? rawBookedDates =
        await _backend.getStringList(_legacyBookedDatesKey);
    final String? rawElsewhereMap =
        await _backend.getString(_legacyBookedElsewhereMapKey);
    final List<String>? rawElsewhereDates =
        await _backend.getStringList(_legacyBookedElsewhereDatesKey);
    final List<String>? rawAllTimeBooked =
        await _backend.getStringList(_legacyAllTimeBookedDatesKey);
    final List<String>? rawAllTimeElsewhere =
        await _backend.getStringList(_legacyAllTimeElsewhereDatesKey);

    final bool hasLegacyKeys = rawUserMap != null ||
        rawBookedDates != null ||
        rawElsewhereMap != null ||
        rawElsewhereDates != null ||
        rawAllTimeBooked != null ||
        rawAllTimeElsewhere != null;

    if (!hasLegacyKeys) {
      if (rawV2 == null || rawV2.isEmpty) {
        _cache = null;
        return <String, ReservationEntry>{};
      }
      final cached = _cache;
      if (cached != null && cached.rawJson == rawV2) {
        return Map<String, ReservationEntry>.from(cached.entries);
      }
      final Map<String, ReservationEntry> decoded = _decodeV2(rawV2);
      _cache = (
        rawJson: rawV2,
        entries: Map<String, ReservationEntry>.unmodifiable(decoded),
      );
      return decoded;
    }

    // Reconcile canonical v2 entries with any legacy keys present.
    final Map<String, ReservationEntry> merged = _decodeV2(rawV2);
    final String effectiveWsId =
        defaultWorkspaceId ?? await _backend.getString('workspace_id') ?? '';
    final String? storedWsName =
        defaultWorkspaceName ?? await _backend.getString('workspace_name');
    final String effectiveWsName =
        (storedWsName != null && storedWsName.isNotEmpty)
            ? storedWsName
            : 'Mon bureau';

    // Priority 1: user_reservations_map
    final Map<String, Map<String, String>> legacyUserMap =
        _decodeLegacyUserMap(rawUserMap);
    for (final MapEntry<String, Map<String, String>> e
        in legacyUserMap.entries) {
      merged.putIfAbsent(
        e.key,
        () => ReservationEntry.fromJson(
          e.key,
          Map<String, dynamic>.from(e.value),
        ),
      );
    }

    // Priority 2: booked_dates
    if (rawBookedDates != null) {
      for (final String dateIso in rawBookedDates) {
        merged.putIfAbsent(
          dateIso,
          () => ReservationEntry(
            dateIso: dateIso,
            workspaceId: effectiveWsId,
            workspaceName: effectiveWsName,
          ),
        );
      }
    }

    // Priority 3: booked_elsewhere_map
    final Map<String, String> legacyElsewhereMap =
        _decodeStringMap(rawElsewhereMap);
    for (final MapEntry<String, String> e in legacyElsewhereMap.entries) {
      merged.putIfAbsent(
        e.key,
        () => ReservationEntry(
          dateIso: e.key,
          workspaceId: '',
          workspaceName: e.value.isNotEmpty ? e.value : 'Ailleurs',
        ),
      );
    }

    // Priority 4: booked_elsewhere_dates
    if (rawElsewhereDates != null) {
      for (final String dateIso in rawElsewhereDates) {
        merged.putIfAbsent(
          dateIso,
          () => ReservationEntry(
            dateIso: dateIso,
            workspaceId: '',
            workspaceName: 'Ailleurs',
          ),
        );
      }
    }

    // Priority 5: all_time_booked_dates
    if (rawAllTimeBooked != null) {
      for (final String dateIso in rawAllTimeBooked) {
        merged.putIfAbsent(
          dateIso,
          () => ReservationEntry(
            dateIso: dateIso,
            workspaceId: effectiveWsId,
            workspaceName: effectiveWsName,
          ),
        );
      }
    }

    // Priority 6: all_time_elsewhere_dates
    if (rawAllTimeElsewhere != null) {
      for (final String dateIso in rawAllTimeElsewhere) {
        merged.putIfAbsent(
          dateIso,
          () => ReservationEntry(
            dateIso: dateIso,
            workspaceId: '',
            workspaceName: 'Ailleurs',
          ),
        );
      }
    }

    if (merged.isNotEmpty) {
      await _persist(merged);
    }
    return merged;
  }

  Future<void> _persist(Map<String, ReservationEntry> entries) async {
    final DateTime cutoff = _cutoffDate();
    final Map<String, ReservationEntry> pruned = <String, ReservationEntry>{};
    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      if (_isWithinRetention(e.key, cutoff)) {
        pruned[e.key] = e.value;
      }
    }

    final Map<String, dynamic> encodedMap = <String, dynamic>{
      for (final MapEntry<String, ReservationEntry> e in pruned.entries)
        e.key: e.value.toJson(),
    };
    final String rawJson = jsonEncode(encodedMap);
    await _backend.setString(storageKey, rawJson);
    _cache = (
      rawJson: rawJson,
      entries: Map<String, ReservationEntry>.unmodifiable(pruned),
    );

    for (final String legacyKey in _legacyKeys) {
      await _backend.remove(legacyKey);
    }
  }

  /// Derives the set of dates booked at [defaultWorkspaceId].
  Set<String> hereDatesFrom(
    Map<String, ReservationEntry> entries,
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) {
    final Set<String> result = <String>{};
    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      if (_isHereEntry(
        e.value,
        defaultWorkspaceId,
        defaultWorkspaceName: defaultWorkspaceName,
      )) {
        result.add(e.key);
      }
    }
    return result;
  }

  /// Derives the `dateIso -> workspaceName` map for reservations at other desks.
  Map<String, String> elsewhereMapFrom(
    Map<String, ReservationEntry> entries,
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) {
    final Map<String, String> result = <String, String>{};
    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      if (!_isHereEntry(
        e.value,
        defaultWorkspaceId,
        defaultWorkspaceName: defaultWorkspaceName,
      )) {
        final String name = e.value.workspaceName;
        result[e.key] = name.isNotEmpty ? name : 'Ailleurs';
      }
    }
    return result;
  }

  Future<({String? wsId, String? wsName})> _resolveDefaults(
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  ) async {
    final String? wsId =
        defaultWorkspaceId ?? await _backend.getString('workspace_id');
    final String? wsName =
        defaultWorkspaceName ?? await _backend.getString('workspace_name');
    return (wsId: wsId, wsName: wsName);
  }

  Future<Set<String>> hereDates(
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final entries = await loadAll(
      defaultWorkspaceId: defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
    return hereDatesFrom(
      entries,
      defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
  }

  Future<Map<String, String>> elsewhereMap(
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final entries = await loadAll(
      defaultWorkspaceId: defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
    return elsewhereMapFrom(
      entries,
      defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
  }

  Future<List<String>> allTimeBookedDates(
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) async {
    final Set<String> here = await hereDates(
      defaultWorkspaceId,
      defaultWorkspaceName: defaultWorkspaceName,
    );
    return here.toList();
  }

  Future<List<String>> allTimeElsewhereDates(
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) async {
    final Map<String, String> elsewhere = await elsewhereMap(
      defaultWorkspaceId,
      defaultWorkspaceName: defaultWorkspaceName,
    );
    return elsewhere.keys.toList();
  }

  Future<({Set<String> here, Map<String, String> elsewhere})> partition(
    String? defaultWorkspaceId, {
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final entries = await loadAll(
      defaultWorkspaceId: defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
    return (
      here: hereDatesFrom(
        entries,
        defaults.wsId,
        defaultWorkspaceName: defaults.wsName,
      ),
      elsewhere: elsewhereMapFrom(
        entries,
        defaults.wsId,
        defaultWorkspaceName: defaults.wsName,
      ),
    );
  }

  /// Upserts a single reservation entry into `reservations_v2`.
  Future<void> upsert(ReservationEntry entry) async {
    final Map<String, ReservationEntry> entries = await loadAll();
    entries[entry.dateIso] = entry;
    await _persist(entries);
  }

  /// Removes a single reservation entry by [dateIso] from `reservations_v2`.
  Future<void> remove(String dateIso) async {
    final Map<String, ReservationEntry> entries = await loadAll();
    entries.remove(dateIso);
    await _persist(entries);
  }

  /// Returns the legacy `{dateIso: {workspaceId, workspaceName}}` map view.
  Future<Map<String, Map<String, String>>> toLegacyUserReservationsMap() async {
    final Map<String, ReservationEntry> entries = await loadAll();
    return <String, Map<String, String>>{
      for (final MapEntry<String, ReservationEntry> e in entries.entries)
        e.key: e.value.toLegacyMap(),
    };
  }

  /// Updates `reservations_v2` from a `{dateIso: {workspaceId, workspaceName}}` map,
  /// preserving past historical entries within [historyRetentionDays] so a
  /// future-only API sync never blindly erases past stats history.
  Future<void> replaceFromLegacyUserReservationsMap(
    Map<String, Map<String, String>> map,
  ) async {
    final DateTime now = _nowProvider();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String todayIso = _formatIsoDate(today);
    final DateTime cutoff = _cutoffDate();

    final Map<String, ReservationEntry> existing = await loadAll();
    final Map<String, ReservationEntry> updated = <String, ReservationEntry>{};

    for (final MapEntry<String, ReservationEntry> e in existing.entries) {
      if (!_isWithinRetention(e.key, cutoff)) {
        continue;
      }
      final DateTime? parsed = DateTime.tryParse(e.key);
      final bool isPast = parsed != null
          ? DateTime(parsed.year, parsed.month, parsed.day).isBefore(today)
          : e.key.compareTo(todayIso) < 0;
      if (isPast) {
        updated[e.key] = e.value;
      }
    }

    final String updatedAtIso = now.toIso8601String();
    for (final MapEntry<String, Map<String, String>> e in map.entries) {
      if (_isWithinRetention(e.key, cutoff)) {
        updated[e.key] = ReservationEntry(
          dateIso: e.key,
          workspaceId: e.value['workspaceId'] ?? '',
          workspaceName: e.value['workspaceName'] ?? '',
          updatedAt: updatedAtIso,
        );
      }
    }

    await _persist(updated);
  }

  /// Replaces only the `here` partition in `reservations_v2` while preserving
  /// `elsewhere` entries untouched.
  Future<void> replaceHereDates(
    List<String> dates, {
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final String effectiveWsId = defaults.wsId ?? '';
    final String effectiveWsName =
        (defaults.wsName != null && defaults.wsName!.isNotEmpty)
            ? defaults.wsName!
            : 'Mon bureau';

    final DateTime now = _nowProvider();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String todayIso = _formatIsoDate(today);
    final DateTime cutoff = _cutoffDate();

    final Map<String, ReservationEntry> entries = await loadAll(
      defaultWorkspaceId: effectiveWsId,
      defaultWorkspaceName: effectiveWsName,
    );
    final Set<String> newDates = dates.toSet();
    final Map<String, ReservationEntry> updated = <String, ReservationEntry>{};

    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      if (!_isWithinRetention(e.key, cutoff)) {
        continue;
      }
      final bool isHere = _isHereEntry(
        e.value,
        effectiveWsId,
        defaultWorkspaceName: effectiveWsName,
      );
      final DateTime? parsed = DateTime.tryParse(e.key);
      final bool isPast = parsed != null
          ? DateTime(parsed.year, parsed.month, parsed.day).isBefore(today)
          : e.key.compareTo(todayIso) < 0;
      if (!isHere || isPast || newDates.contains(e.key)) {
        updated[e.key] = e.value;
      }
    }

    final String updatedAtIso = now.toIso8601String();
    for (final String d in dates) {
      if (_isWithinRetention(d, cutoff)) {
        updated.putIfAbsent(
          d,
          () => ReservationEntry(
            dateIso: d,
            workspaceId: effectiveWsId,
            workspaceName: effectiveWsName,
            updatedAt: updatedAtIso,
          ),
        );
      }
    }

    await _persist(updated);
  }

  /// Replaces only the `elsewhere` partition in `reservations_v2` with [map],
  /// preserving `here` entries untouched.
  Future<void> replaceElsewhereMap(
    Map<String, String> map, {
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final Map<String, ReservationEntry> entries = await loadAll(
      defaultWorkspaceId: defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
    final Map<String, ReservationEntry> updated = <String, ReservationEntry>{};

    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      final bool isHere = _isHereEntry(
        e.value,
        defaults.wsId,
        defaultWorkspaceName: defaults.wsName,
      );
      if (isHere) {
        updated[e.key] = e.value;
      }
    }

    final String updatedAtIso = _nowProvider().toIso8601String();
    for (final MapEntry<String, String> e in map.entries) {
      final ReservationEntry? prev = entries[e.key];
      final String prevWsId = (prev != null &&
              !_isHereEntry(
                prev,
                defaults.wsId,
                defaultWorkspaceName: defaults.wsName,
              ))
          ? prev.workspaceId
          : '';
      updated[e.key] = ReservationEntry(
        dateIso: e.key,
        workspaceId: prevWsId,
        workspaceName: e.value.isNotEmpty ? e.value : 'Ailleurs',
        updatedAt: updatedAtIso,
      );
    }

    await _persist(updated);
  }

  /// Replaces only the `elsewhere` partition in `reservations_v2` with [dates],
  /// preserving existing metadata for kept dates and preserving `here` entries.
  Future<void> replaceElsewhereDates(
    List<String> dates, {
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  }) async {
    final DateTime now = _nowProvider();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final String todayIso = _formatIsoDate(today);
    final DateTime cutoff = _cutoffDate();

    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final Map<String, ReservationEntry> entries = await loadAll(
      defaultWorkspaceId: defaults.wsId,
      defaultWorkspaceName: defaults.wsName,
    );
    final Set<String> newDates = dates.toSet();
    final Map<String, ReservationEntry> updated = <String, ReservationEntry>{};

    for (final MapEntry<String, ReservationEntry> e in entries.entries) {
      if (!_isWithinRetention(e.key, cutoff)) {
        continue;
      }
      final bool isHere = _isHereEntry(
        e.value,
        defaults.wsId,
        defaultWorkspaceName: defaults.wsName,
      );
      final DateTime? parsed = DateTime.tryParse(e.key);
      final bool isPast = parsed != null
          ? DateTime(parsed.year, parsed.month, parsed.day).isBefore(today)
          : e.key.compareTo(todayIso) < 0;
      if (isHere || isPast || newDates.contains(e.key)) {
        updated[e.key] = e.value;
      }
    }

    final String updatedAtIso = now.toIso8601String();
    for (final String d in dates) {
      if (_isWithinRetention(d, cutoff)) {
        updated.putIfAbsent(
          d,
          () => ReservationEntry(
            dateIso: d,
            workspaceId: '',
            workspaceName: 'Ailleurs',
            updatedAt: updatedAtIso,
          ),
        );
      }
    }

    await _persist(updated);
  }

  /// Merges historical `here` dates into `reservations_v2` without erasing
  /// existing entries.
  Future<void> mergeAllTimeBookedDates(
    List<String> dates, {
    String? defaultWorkspaceId,
    String? defaultWorkspaceName,
  }) async {
    final defaults =
        await _resolveDefaults(defaultWorkspaceId, defaultWorkspaceName);
    final String effectiveWsId = defaults.wsId ?? '';
    final String effectiveWsName =
        (defaults.wsName != null && defaults.wsName!.isNotEmpty)
            ? defaults.wsName!
            : 'Mon bureau';

    final Map<String, ReservationEntry> entries = await loadAll(
      defaultWorkspaceId: effectiveWsId,
      defaultWorkspaceName: effectiveWsName,
    );
    bool changed = false;
    final String updatedAtIso = _nowProvider().toIso8601String();

    for (final String d in dates) {
      if (!entries.containsKey(d)) {
        entries[d] = ReservationEntry(
          dateIso: d,
          workspaceId: effectiveWsId,
          workspaceName: effectiveWsName,
          updatedAt: updatedAtIso,
        );
        changed = true;
      }
    }

    if (changed || dates.isNotEmpty) {
      await _persist(entries);
    }
  }

  /// Merges historical `elsewhere` dates into `reservations_v2` without erasing
  /// existing entries.
  Future<void> mergeAllTimeElsewhereDates(List<String> dates) async {
    final Map<String, ReservationEntry> entries = await loadAll();
    bool changed = false;
    final String updatedAtIso = _nowProvider().toIso8601String();

    for (final String d in dates) {
      if (!entries.containsKey(d)) {
        entries[d] = ReservationEntry(
          dateIso: d,
          workspaceId: '',
          workspaceName: 'Ailleurs',
          updatedAt: updatedAtIso,
        );
        changed = true;
      }
    }

    if (changed || dates.isNotEmpty) {
      await _persist(entries);
    }
  }
}
