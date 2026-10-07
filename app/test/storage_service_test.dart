import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/storage_service.dart';

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
  });
}
