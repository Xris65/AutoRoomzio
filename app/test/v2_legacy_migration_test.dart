import 'dart:convert';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/services/reservation_store.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

final class _InMemorySharedPreferencesAsyncPlatform
    extends SharedPreferencesAsyncPlatform {
  final Map<String, Object> data = <String, Object>{};
  final Set<String> throwOnSetKeys;
  int getKeysCallCount = 0;

  _InMemorySharedPreferencesAsyncPlatform({
    Map<String, Object>? initialData,
    Set<String>? throwOnSetKeys,
  }) : throwOnSetKeys = throwOnSetKeys ?? <String>{} {
    if (initialData != null) {
      data.addAll(initialData);
    }
  }

  void _checkSetAllowed(String key) {
    if (throwOnSetKeys.contains(key)) {
      throw PlatformException(
        code: 'INVALID_VALUE',
        message: 'Simulated DataStore rejection for key: $key',
      );
    }
  }

  @override
  Future<void> setString(
    String key,
    String value,
    SharedPreferencesOptions options,
  ) async {
    _checkSetAllowed(key);
    data[key] = value;
  }

  @override
  Future<void> setBool(
    String key,
    bool value,
    SharedPreferencesOptions options,
  ) async {
    _checkSetAllowed(key);
    data[key] = value;
  }

  @override
  Future<void> setDouble(
    String key,
    double value,
    SharedPreferencesOptions options,
  ) async {
    _checkSetAllowed(key);
    data[key] = value;
  }

  @override
  Future<void> setInt(
    String key,
    int value,
    SharedPreferencesOptions options,
  ) async {
    _checkSetAllowed(key);
    data[key] = value;
  }

  @override
  Future<void> setStringList(
    String key,
    List<String> value,
    SharedPreferencesOptions options,
  ) async {
    _checkSetAllowed(key);
    data[key] = List<String>.from(value);
  }

  @override
  Future<String?> getString(
    String key,
    SharedPreferencesOptions options,
  ) async {
    return data[key] as String?;
  }

  @override
  Future<bool?> getBool(
    String key,
    SharedPreferencesOptions options,
  ) async {
    return data[key] as bool?;
  }

  @override
  Future<double?> getDouble(
    String key,
    SharedPreferencesOptions options,
  ) async {
    return data[key] as double?;
  }

  @override
  Future<int?> getInt(
    String key,
    SharedPreferencesOptions options,
  ) async {
    return data[key] as int?;
  }

  @override
  Future<List<String>?> getStringList(
    String key,
    SharedPreferencesOptions options,
  ) async {
    final Object? raw = data[key];
    if (raw == null) return null;
    return List<String>.from(raw as List<String>);
  }

  @override
  Future<void> clear(
    ClearPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) {
      data.clear();
    } else {
      data.removeWhere((String key, _) => allowList.contains(key));
    }
  }

  @override
  Future<Map<String, Object>> getPreferences(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) {
      return Map<String, Object>.from(data);
    }
    return <String, Object>{
      for (final MapEntry<String, Object> entry in data.entries)
        if (allowList.contains(entry.key)) entry.key: entry.value,
    };
  }

  @override
  Future<Set<String>> getKeys(
    GetPreferencesParameters parameters,
    SharedPreferencesOptions options,
  ) async {
    getKeysCallCount++;
    final Set<String>? allowList = parameters.filter.allowList;
    if (allowList == null) {
      return data.keys.toSet();
    }
    return data.keys.where(allowList.contains).toSet();
  }
}

class _FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return values[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SharedPreferencesAsyncPlatform? previousAsyncPlatform;

  setUp(() {
    previousAsyncPlatform = SharedPreferencesAsyncPlatform.instance;
    StorageService.forceAsyncPrefsForTesting = false;
    StorageService.resetLegacyMigrationForTesting();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageService(secureStorage: _FakeSecureStorage()).clearMemoryCache();
  });

  tearDown(() {
    StorageService.forceAsyncPrefsForTesting = false;
    StorageService.resetLegacyMigrationForTesting();
    SharedPreferencesAsyncPlatform.instance = previousAsyncPlatform;
  });

  group('Zero-loss v1.7.0 -> v2.0.0 SharedPreferences migration', () {
    test(
      'migrates all v1.7.0 settings, rules, colleagues, vacations, theme and reservations into SharedPreferencesAsync and ReservationStore',
      () async {
        final String rulesJson = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'rule-1',
            'siteId': 'site-42',
            'floorId': 'floor-7',
            'workspaceId': 'ws-v1-main',
            'workspaceName': 'Desk V1 Main',
            'days': <int>[1, 3, 5],
          },
        ]);
        final String colleaguesJson = jsonEncode(<Map<String, Object?>>[
          const Colleague(
            id: 'col-1',
            name: 'Alice Martin',
            email: 'alice@example.com',
            isFavorite: true,
          ).toJson(),
        ]);
        final String vacationsJson = jsonEncode(<Map<String, String>>[
          <String, String>{'start': '2026-12-20', 'end': '2026-12-31'},
        ]);
        final String elsewhereJson = jsonEncode(<String, String>{
          '2026-11-28': 'Salle Annexe',
        });

        SharedPreferences.setMockInitialValues(<String, Object>{
          'site_id': 'site-42',
          'floor_id': 'floor-7',
          'workspace_id': 'ws-v1-main',
          'workspace_name': 'Desk V1 Main',
          'automation_rules_v1': rulesJson,
          'selected_days': <String>['1', '3', '5'],
          'automation_enabled': true,
          'favorite_colleagues': colleaguesJson,
          'vacation_periods': vacationsJson,
          'booked_dates': <String>['2026-11-26', '2026-11-27'],
          'all_time_booked_dates': <String>['2026-11-20'],
          'booked_elsewhere_map': elsewhereJson,
          'requested_dates': <String>['2026-12-01', '2026-12-02'],
          'theme_mode': 2,
          'theme_color_index': 3,
          'font_family_index': 1,
          'ui_scale': 1.15,
        });

        final _InMemorySharedPreferencesAsyncPlatform fakeAsync =
            _InMemorySharedPreferencesAsyncPlatform();
        SharedPreferencesAsyncPlatform.instance = fakeAsync;
        StorageService.forceAsyncPrefsForTesting = true;

        final _FakeSecureStorage fakeSecure = _FakeSecureStorage();
        final ReservationStore reservationStore = ReservationStore(
          nowProvider: () => DateTime(2026, 11, 25),
        );
        final StorageService storage = StorageService(
          secureStorage: fakeSecure,
          reservationStore: reservationStore,
        );

        // First read automatically triggers migration via _PrefsStore.
        expect(await storage.getSiteId(), equals('site-42'));
        expect(await storage.getFloorId(), equals('floor-7'));
        expect(await storage.getWorkspaceId(), equals('ws-v1-main'));
        expect(await storage.getWorkspaceName(), equals('Desk V1 Main'));

        final List<AutomationRule> rules = await storage.getAutomationRules();
        expect(rules, hasLength(1));
        expect(rules.first.workspaceId, equals('ws-v1-main'));
        expect(rules.first.days, equals(<int>[1, 3, 5]));

        expect(await storage.getDays(), equals(<int>[1, 3, 5]));
        expect(await storage.getAutomationEnabled(), isTrue);

        final List<Colleague> colleagues =
            await storage.getFavoriteColleagues();
        expect(colleagues, hasLength(1));
        expect(colleagues.first.name, equals('Alice Martin'));

        final List<Map<String, String>> vacations = await storage.getVacations();
        expect(vacations, hasLength(1));
        expect(vacations.first['start'], equals('2026-12-20'));
        expect(vacations.first['end'], equals('2026-12-31'));

        expect(
          await storage.getRequestedDates(),
          equals(<String>['2026-12-01', '2026-12-02']),
        );
        expect(await storage.getThemeModeIndex(), equals(2));
        expect(await storage.getThemeColorIndex(), equals(3));
        expect(await storage.getFontFamilyIndex(), equals(1));
        expect(await storage.getUiScale(), equals(1.15));

        // Reservations are reconciled into reservations_v2 via ReservationStore.
        final List<String> booked = await storage.getBookedDates();
        expect(
          booked,
          unorderedEquals(<String>['2026-11-20', '2026-11-26', '2026-11-27']),
        );
        final Map<String, String> elsewhere =
            await storage.getBookedElsewhereMap();
        expect(elsewhere, equals(<String, String>{'2026-11-28': 'Salle Annexe'}));
        expect(fakeAsync.data[ReservationStore.storageKey], isNotNull);
        expect(fakeAsync.data[StorageService.legacyMigrationDoneKey], isTrue);

        // Safety net: legacy SharedPreferences keys remain intact after migration.
        final SharedPreferences legacyPrefs =
            await SharedPreferences.getInstance();
        expect(legacyPrefs.getString('site_id'), equals('site-42'));
        expect(legacyPrefs.getString('workspace_id'), equals('ws-v1-main'));
        expect(
          legacyPrefs.getStringList('booked_dates'),
          equals(<String>['2026-11-26', '2026-11-27']),
        );
      },
    );

    test(
      'preserves newer v2.0.0 settings while recovering unconfigured v1.7.0 keys and reconciling reservations',
      () async {
        final String v1RulesJson = jsonEncode(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'rule-v1',
            'siteId': 'site-1',
            'floorId': 'floor-1',
            'workspaceId': 'old-v1',
            'workspaceName': 'Old Desk',
            'days': <int>[2, 4],
          },
        ]);
        final String v1FavoritesJson = jsonEncode(<Map<String, Object?>>[
          const Colleague(
            id: 'fav-1',
            name: 'Bob Dupont',
            email: 'bob@example.com',
            isFavorite: true,
          ).toJson(),
        ]);

        SharedPreferences.setMockInitialValues(<String, Object>{
          'site_id': 'site-1',
          'workspace_id': 'old-v1',
          'workspace_name': 'Old Desk',
          'automation_rules_v1': v1RulesJson,
          'theme_mode': 2,
          'favorite_colleagues': v1FavoritesJson,
          'booked_dates': <String>['2026-11-26'],
          'all_time_booked_dates': <String>['2026-11-18'],
        });

        // Simulate a user who opened v2.0.0 once before this fix and picked a
        // new workspace + synced a future booking, before the migration flag existed.
        final String preExistingV2Reservations = jsonEncode(<String, Object?>{
          '2026-11-29': <String, Object?>{
            'workspaceId': 'new-v2',
            'workspaceName': 'New Desk V2',
          },
        });
        final _InMemorySharedPreferencesAsyncPlatform fakeAsync =
            _InMemorySharedPreferencesAsyncPlatform(
          initialData: <String, Object>{
            'workspace_id': 'new-v2',
            'workspace_name': 'New Desk V2',
            ReservationStore.storageKey: preExistingV2Reservations,
          },
        );
        SharedPreferencesAsyncPlatform.instance = fakeAsync;
        StorageService.forceAsyncPrefsForTesting = true;

        final SharedPreferences legacyPrefs =
            await SharedPreferences.getInstance();
        final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();

        await StorageService.ensureLegacyPrefsMigrated(
          legacyPrefsOverride: legacyPrefs,
          asyncPrefsOverride: asyncPrefs,
        );

        // New v2.0.0 workspace must NOT be overwritten by old-v1.
        expect(await asyncPrefs.getString('workspace_id'), equals('new-v2'));
        expect(
          await asyncPrefs.getString('workspace_name'),
          equals('New Desk V2'),
        );

        // Missing v1.7.0 preferences must be recovered.
        expect(await asyncPrefs.getString('site_id'), equals('site-1'));
        expect(
          await asyncPrefs.getString('automation_rules_v1'),
          equals(v1RulesJson),
        );
        expect(await asyncPrefs.getInt('theme_mode'), equals(2));
        expect(
          await asyncPrefs.getString('favorite_colleagues'),
          equals(v1FavoritesJson),
        );
        expect(
          await asyncPrefs.getBool(StorageService.legacyMigrationDoneKey),
          isTrue,
        );

        // ReservationStore reconciles pre-existing v2 bookings + legacy keys.
        final ReservationStore store = ReservationStore(
          nowProvider: () => DateTime(2026, 11, 25),
        );
        final Map<String, ReservationEntry> merged = await store.loadAll();
        expect(
          merged.keys,
          unorderedEquals(<String>['2026-11-18', '2026-11-26', '2026-11-29']),
        );
        expect(merged['2026-11-29']?.workspaceId, equals('new-v2'));
        expect(merged['2026-11-26']?.workspaceId, equals('new-v2'));
        expect(merged['2026-11-18']?.workspaceId, equals('new-v2'));
      },
    );

    test(
      'is idempotent across repeated and concurrent invocations once legacy_prefs_migrated_v2 is true',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'site_id': 'initial-site',
          'ui_scale': 1.25,
        });

        final _InMemorySharedPreferencesAsyncPlatform fakeAsync =
            _InMemorySharedPreferencesAsyncPlatform();
        SharedPreferencesAsyncPlatform.instance = fakeAsync;
        StorageService.forceAsyncPrefsForTesting = true;

        final SharedPreferences legacyPrefs =
            await SharedPreferences.getInstance();
        final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();

        // Concurrent calls share the memoized in-flight future.
        await Future.wait<void>(<Future<void>>[
          StorageService.ensureLegacyPrefsMigrated(
            legacyPrefsOverride: legacyPrefs,
            asyncPrefsOverride: asyncPrefs,
          ),
          StorageService.ensureLegacyPrefsMigrated(
            legacyPrefsOverride: legacyPrefs,
            asyncPrefsOverride: asyncPrefs,
          ),
          StorageService.ensureLegacyPrefsMigrated(
            legacyPrefsOverride: legacyPrefs,
            asyncPrefsOverride: asyncPrefs,
          ),
        ]);

        expect(fakeAsync.getKeysCallCount, equals(1));
        expect(await asyncPrefs.getString('site_id'), equals('initial-site'));
        expect(
          await asyncPrefs.getBool(StorageService.legacyMigrationDoneKey),
          isTrue,
        );

        // Mutate legacy store and reset in-memory memoization to verify the
        // persisted legacy_prefs_migrated_v2 flag also short-circuits migration.
        await legacyPrefs.setString('site_id', 'mutated-legacy-site');
        await legacyPrefs.setString('late_key', 'should-not-migrate');
        StorageService.resetLegacyMigrationForTesting();

        await StorageService.ensureLegacyPrefsMigrated(
          legacyPrefsOverride: legacyPrefs,
          asyncPrefsOverride: asyncPrefs,
        );

        expect(fakeAsync.getKeysCallCount, equals(1));
        expect(await asyncPrefs.getString('site_id'), equals('initial-site'));
        expect(await asyncPrefs.getString('late_key'), isNull);
      },
    );

    test(
      'isolates individual DataStore key rejections and prevents resurrection after clearAll()',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'bad_datastore_key':
              'VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu_poison',
          'site_id': 'site-safe',
          'ui_scale': 1.1,
        });

        final _InMemorySharedPreferencesAsyncPlatform fakeAsync =
            _InMemorySharedPreferencesAsyncPlatform(
          throwOnSetKeys: <String>{'bad_datastore_key'},
        );
        SharedPreferencesAsyncPlatform.instance = fakeAsync;
        StorageService.forceAsyncPrefsForTesting = true;

        final _FakeSecureStorage fakeSecure = _FakeSecureStorage();
        final StorageService storage = StorageService(secureStorage: fakeSecure);

        expect(await storage.getSiteId(), equals('site-safe'));
        expect(await storage.getUiScale(), equals(1.1));
        expect(
          fakeAsync.data[StorageService.legacyMigrationDoneKey],
          isTrue,
        );
        expect(fakeAsync.data.containsKey('bad_datastore_key'), isFalse);

        // Voluntary logout/reset must clear both async and legacy stores and keep
        // legacy_prefs_migrated_v2 == true so v1.7.0 data never resurrects.
        await storage.clearAll();
        expect(await storage.getSiteId(), isNull);
        expect(
          fakeAsync.data[StorageService.legacyMigrationDoneKey],
          isTrue,
        );
        final SharedPreferences legacyPrefs =
            await SharedPreferences.getInstance();
        expect(legacyPrefs.getKeys(), isEmpty);

        StorageService.resetLegacyMigrationForTesting();
        await storage.reloadFromDisk();
        expect(await storage.getSiteId(), isNull);
      },
    );
  });
}
