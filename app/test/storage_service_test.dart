import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/models/colleague.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> map;
  final bool throwOnOperations;

  FakeSecureStorage({
    Map<String, String>? initialData,
    this.throwOnOperations = false,
  }) : map = initialData != null ? Map.from(initialData) : {};

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
    if (throwOnOperations) throw MissingPluginException();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
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
    if (throwOnOperations) throw MissingPluginException();
    return map[key];
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
    if (throwOnOperations) throw MissingPluginException();
    map.remove(key);
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
    if (throwOnOperations) throw MissingPluginException();
    map.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('StorageService Secure Storage & Migration Tests', () {
    test('saveRefreshToken and getRefreshToken use secure storage when available', () async {
      final fakeSecure = FakeSecureStorage();
      final storage = StorageService(secureStorage: fakeSecure);

      await storage.saveRefreshToken('secure_token_123');
      expect(fakeSecure.map['refresh_token'], equals('secure_token_123'));

      final token = await storage.getRefreshToken();
      expect(token, equals('secure_token_123'));

      // Ensure SharedPreferences does not hold plaintext
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('auto-migrates legacy token from SharedPreferences to secure storage', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'legacy_refresh_token_xyz',
      });

      final fakeSecure = FakeSecureStorage();
      final storage = StorageService(secureStorage: fakeSecure);

      // Before getRefreshToken, secure storage is empty
      expect(fakeSecure.map.containsKey('refresh_token'), isFalse);

      final token = await storage.getRefreshToken();
      expect(token, equals('legacy_refresh_token_xyz'));

      // Migrated to secure storage
      expect(fakeSecure.map['refresh_token'], equals('legacy_refresh_token_xyz'));

      // Removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('clearAuthToken wipes token from secure storage and auth keys from prefs', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'legacy_token',
        'access_token': 'temp_access',
        'token_expiry': 1234567890,
      });

      final fakeSecure = FakeSecureStorage(initialData: {
        'refresh_token': 'secure_token',
      });
      final storage = StorageService(secureStorage: fakeSecure);

      await storage.clearAuthToken();

      expect(fakeSecure.map.containsKey('refresh_token'), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), isNull);
      expect(prefs.getString('access_token'), isNull);
      expect(prefs.getInt('token_expiry'), isNull);
    });

    test('clearAll and clearAllData wipes both secure storage and SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'site_id': '10',
        'workspace_name': 'Desk A',
        'automation_enabled': true,
      });

      final fakeSecure = FakeSecureStorage(initialData: {
        'refresh_token': 'secure_secret',
      });
      final storage = StorageService(secureStorage: fakeSecure);

      await storage.clearAll();

      expect(fakeSecure.map.isEmpty, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().isEmpty, isTrue);

      // Verify clearAllData behaves identically
      await storage.saveSiteId('99');
      await storage.saveRefreshToken('new_token');
      await storage.clearAllData();
      expect(fakeSecure.map.isEmpty, isTrue);
      expect(prefs.getKeys().isEmpty, isTrue);
    });

    test('gracefully falls back to SharedPreferences on MissingPluginException', () async {
      final throwingSecure = FakeSecureStorage(throwOnOperations: true);
      final storage = StorageService(secureStorage: throwingSecure);

      // Should not throw
      await storage.saveRefreshToken('fallback_token');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), equals('fallback_token'));

      final retrieved = await storage.getRefreshToken();
      expect(retrieved, equals('fallback_token'));

      await storage.clearAuthToken();
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('default parameterless constructor functions properly in mock test environments', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token_headless',
        'site_id': 'building_101',
      });

      final defaultStorage = StorageService();
      final token = await defaultStorage.getRefreshToken();
      expect(token, equals('mock_token_headless'));

      final siteId = await defaultStorage.getSiteId();
      expect(siteId, equals('building_101'));
    });

    test('building and room aliases properly mirror site and workspace methods', () async {
      final storage = StorageService();

      await storage.saveBuildingId('site_building_42');
      expect(await storage.getSiteId(), equals('site_building_42'));
      expect(await storage.getBuildingId(), equals('site_building_42'));

      await storage.saveRoomId('ws_room_7');
      expect(await storage.getWorkspaceId(), equals('ws_room_7'));
      expect(await storage.getRoomId(), equals('ws_room_7'));
    });

    test('rememberEmail and savedEmail getters/setters operate as expected', () async {
      final storage = StorageService();

      expect(await storage.getRememberEmail(), isTrue); // default is true
      await storage.saveRememberEmail(false);
      expect(await storage.getRememberEmail(), isFalse);

      await storage.saveSavedEmail('test.user@company.com');
      expect(await storage.getSavedEmail(), equals('test.user@company.com'));
    });

    test('clearAllData preserves email if rememberEmail is true, clears if false', () async {
      final storage = StorageService();

      // Case A: remember = true
      await storage.saveRememberEmail(true);
      await storage.saveSavedEmail('user@company.com');
      await storage.saveRefreshToken('token-to-be-cleared');
      await storage.saveWorkspaceName('Desk 42');

      await storage.clearAllData();

      expect(await storage.getRememberEmail(), isTrue);
      expect(await storage.getSavedEmail(), equals('user@company.com'));
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getWorkspaceName(), isNull);

      // Case B: remember = false
      await storage.saveRememberEmail(false);
      await storage.saveSavedEmail('user2@company.com');
      await storage.saveRefreshToken('another-token');

      await storage.clearAllData();

      expect(await storage.getSavedEmail(), isNull);
      expect(await storage.getRefreshToken(), isNull);
    });

    test('bookedElsewhere and delegatedBookingsMap persist correctly', () async {
      final storage = StorageService();

      expect(await storage.getBookedElsewhereDates(), isEmpty);
      await storage.saveBookedElsewhereDates(['2026-10-15', '2026-10-16']);
      final dates = await storage.getBookedElsewhereDates();
      expect(dates, contains('2026-10-15'));
      expect(dates, contains('2026-10-16'));

      final delMap = {'2026-10-15': 'ws-1|Jean|Desk 1|evt-1|u-1'};
      await storage.saveDelegatedBookingsMap(delMap);
      final retrievedDel = await storage.getDelegatedBookingsMap();
      expect(retrievedDel['2026-10-15'], equals('ws-1|Jean|Desk 1|evt-1|u-1'));
    });

    test('mergeFavoriteColleagues preserves local external/manual favorites while updating from API', () async {
      final storage = StorageService();

      // Add a manual external colleague
      const manualColleague = Colleague(
        id: 'ext_12345',
        name: 'Jean Externe',
        email: 'jean.ext@partner.com',
      );
      await storage.addFavoriteColleague(manualColleague);

      // Add another colleague with custom prefix
      const customColleague = Colleague(
        id: 'custom_99',
        name: 'Marie Consultant',
        email: 'marie@consulting.com',
      );
      await storage.addFavoriteColleague(customColleague);

      // API returns a new colleague and an update
      const apiColleague = Colleague(
        id: 'usr_internal_1',
        name: 'Pierre Interne',
        email: 'pierre@company.com',
      );

      await storage.mergeFavoriteColleagues([apiColleague]);

      final favorites = await storage.getFavoriteColleagues();
      expect(favorites.length, equals(3));
      expect(favorites.any((c) => c.id == 'ext_12345' && c.name == 'Jean Externe'), isTrue);
      expect(favorites.any((c) => c.id == 'custom_99' && c.name == 'Marie Consultant'), isTrue);
      expect(favorites.any((c) => c.id == 'usr_internal_1' && c.name == 'Pierre Interne'), isTrue);
    });

    test('delegated bookings on the same date can coexist and be canceled independently', () async {
      final storage = StorageService();
      const date = '2026-10-20';

      // Save two bookings on different desks for the same day
      await storage.saveDelegatedBooking(date, 'ws-desk-1', 'ws-desk-1|Alice|Desk 1|evt-1|usr-1');
      await storage.saveDelegatedBooking(date, 'ws-desk-2', 'ws-desk-2|Bob|Desk 2|evt-2|usr-2');

      // Both should coexist and be retrievable individually
      final booking1 = await storage.getDelegatedBooking(date, 'ws-desk-1');
      final booking2 = await storage.getDelegatedBooking(date, 'ws-desk-2');
      expect(booking1, equals('ws-desk-1|Alice|Desk 1|evt-1|usr-1'));
      expect(booking2, equals('ws-desk-2|Bob|Desk 2|evt-2|usr-2'));

      final allBookings = await storage.getDelegatedBookingsMap();
      expect(allBookings.containsKey('$date#ws-desk-1'), isTrue);
      expect(allBookings.containsKey('$date#ws-desk-2'), isTrue);

      // Cancel desk 1 only
      await storage.removeDelegatedBooking(date, 'ws-desk-1');

      // Desk 1 removed, Desk 2 still intact
      expect(await storage.getDelegatedBooking(date, 'ws-desk-1'), isNull);
      expect(await storage.getDelegatedBooking(date, 'ws-desk-2'), equals('ws-desk-2|Bob|Desk 2|evt-2|usr-2'));
      expect(await storage.getDelegatedBooking(date), equals('ws-desk-2|Bob|Desk 2|evt-2|usr-2'));

      // Cancel desk 2
      await storage.removeDelegatedBooking(date, 'ws-desk-2');
      expect(await storage.getDelegatedBooking(date, 'ws-desk-2'), isNull);
      expect(await storage.getDelegatedBooking(date), isNull);
    });
  });
}
