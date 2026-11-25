import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/background_task.dart';
import 'package:auto_roomzio/holiday_service.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/services/automation_engine.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/utils/date_helpers.dart';
import 'package:auto_roomzio/utils/workspace_helpers.dart';

class _TrackingHttpClient extends http.BaseClient {
  int sendCount = 0;
  bool isClosed = false;
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  _TrackingHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (isClosed) {
      throw StateError('Client was already closed');
    }
    sendCount++;
    return handler(request);
  }

  @override
  void close() {
    isClosed = true;
    super.close();
  }
}

class _FlakyOnceSecureStorage extends FlutterSecureStorage {
  final Map<String, String> store = {};
  int writeAttempts = 0;
  int deleteCalls = 0;

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
    writeAttempts++;
    if (writeAttempts == 1) {
      throw PlatformException(code: 'KEYSTORE_ERROR', message: 'Corrupted key');
    }
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
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
  }) async =>
      store[key];

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
    deleteCalls++;
    store.remove(key);
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
    store.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineStateManager.instance.reset();
    StorageService().clearMemoryCache();
  });

  tearDown(() {
    OfflineStateManager.instance.reset();
    StorageService().clearMemoryCache();
  });

  group('1. HTTP Client Persistence, Timeouts & Occupancy Close Fix', () {
    test('OfflineAwareHttpClient reuses the same inner client and only closes it on close()', () async {
      final trackingClient = _TrackingHttpClient((req) async {
        final bytes = utf8.encode('{"ok":true}');
        return http.StreamedResponse(Stream.value(bytes), 200);
      });

      final client = OfflineAwareHttpClient(trackingClient);
      await client.get(Uri.parse('https://api.my.roomz.io/a'));
      await client.get(Uri.parse('https://api.my.roomz.io/b'));

      expect(trackingClient.sendCount, equals(2));
      expect(trackingClient.isClosed, isFalse);

      client.close();
      expect(trackingClient.isClosed, isTrue);
    });

    test('OfflineAwareHttpClient marks offline and rethrows TimeoutException when request times out', () async {
      final hangingClient = _TrackingHttpClient((req) {
        return Completer<http.StreamedResponse>().future;
      });
      final stateManager = OfflineStateManager.instance;
      final client = OfflineAwareHttpClient(
        hangingClient,
        stateManager,
        const Duration(milliseconds: 50),
      );

      expect(stateManager.isOffline, isFalse);
      await expectLater(
        client.get(Uri.parse('https://api.my.roomz.io/slow')),
        throwsA(isA<TimeoutException>()),
      );
      expect(stateManager.isOffline, isTrue);
      client.close();
    });

    test('getWorkspaceOccupancy does not close shared client on RoomzApiService', () async {
      final trackingClient = _TrackingHttpClient((req) async {
        final body = req.url.path.contains('/calendars')
            ? '{"data":[]}'
            : '[{"id":"site-1","name":"Site 1"}]';
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });
      final api = RoomzApiService(client: trackingClient);

      await api.getWorkspaceOccupancy(
        'tok',
        'ws-1',
        'fl-1',
        ['2026-11-25'],
        'user-1',
        const {},
      );
      expect(trackingClient.isClosed, isFalse);

      final sites = await api.getSites('tok');
      expect(sites.length, equals(1));
      expect(trackingClient.isClosed, isFalse);
    });
  });

  group('2. StorageService Security & JSON Cache Memoization', () {
    test('saveRefreshToken retries after delete on secure storage error and never writes plaintext', () async {
      final flakySecure = _FlakyOnceSecureStorage();
      final storage = StorageService(secureStorage: flakySecure);

      await storage.saveRefreshToken('super-secret-refresh-token');

      expect(flakySecure.writeAttempts, equals(2));
      expect(flakySecure.deleteCalls, equals(1));
      expect(flakySecure.store['refresh_token'], equals('super-secret-refresh-token'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('refresh_token'), isNull);
    });

    test('memoization returns defensive copies and invalidates on writes or mock store changes', () async {
      final storage = StorageService();
      await storage.saveFloorPlanData('fl-1', {
        'features': [
          {'type': 'Feature', 'properties': {'id': 'ws-1'}}
        ]
      });
      await storage.saveFloorWorkspaces('fl-1', [
        {'id': 'ws-1', 'name': 'Desk 1', 'isBookable': true}
      ]);
      await storage.saveFloorOccupants('fl-1', '2026-11-25', {
        'ws-1': const DeskOccupant(workspaceId: 'ws-1', occupantName: 'Alice'),
      });
      await storage.saveUserReservationsMap({
        '2026-11-25': {'workspaceId': 'ws-1', 'workspaceName': 'Desk 1'}
      });
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-1',
          siteId: 's-1',
          floorId: 'fl-1',
          workspaceId: 'ws-1',
          workspaceName: 'Desk 1',
          days: [2, 4],
        ),
      ]);

      // Populate cache and mutate returned copies
      final plan1 = await storage.getFloorPlanData('fl-1') as Map<String, dynamic>;
      (plan1['features'] as List).clear();
      final plan2 = await storage.getFloorPlanData('fl-1') as Map<String, dynamic>;
      expect((plan2['features'] as List).length, equals(1));

      final ws1 = await storage.getFloorWorkspaces('fl-1');
      ws1.clear();
      final ws2 = await storage.getFloorWorkspaces('fl-1');
      expect(ws2.length, equals(1));

      final occ1 = await storage.getFloorOccupants('fl-1', '2026-11-25');
      occ1.clear();
      final occ2 = await storage.getFloorOccupants('fl-1', '2026-11-25');
      expect(occ2.length, equals(1));

      final res1 = await storage.getUserReservationsMap();
      res1['2026-11-25']!['workspaceName'] = 'MUTATED';
      final res2 = await storage.getUserReservationsMap();
      expect(res2['2026-11-25']!['workspaceName'], equals('Desk 1'));

      final rules1 = await storage.getAutomationRules();
      rules1.clear();
      final rules2 = await storage.getAutomationRules();
      expect(rules2.length, equals(1));

      // Verify compatibility with SharedPreferences.setMockInitialValues changing raw JSON
      SharedPreferences.setMockInitialValues({
        'user_reservations_map': jsonEncode({
          '2026-12-01': {'workspaceId': 'ws-9', 'workspaceName': 'Desk 9'}
        }),
      });
      final res3 = await storage.getUserReservationsMap();
      expect(res3.containsKey('2026-12-01'), isTrue);
      expect(res3.containsKey('2026-11-25'), isFalse);

      await storage.reloadFromDisk();
      expect(await storage.getFloorWorkspaces('fl-1'), isEmpty);
    });
  });

  group('3. HolidayService Static Cache & Helpers', () {
    test('HolidayService caches holidays by (year, countryCode)', () {
      final first = HolidayService.getHolidaysForYear(2026, countryCode: 'fr');
      final second = HolidayService.getHolidaysForYear(2026, countryCode: 'FR');
      expect(identical(first, second), isTrue);
      expect(first['2026-07-14'], equals('Fête Nationale'));
    });

    test('DateHelpers and workspace_helpers behave consistently', () {
      final d = DateTime(2026, 5, 4);
      expect(DateHelpers.formatIsoDate(d), equals('2026-05-04'));
      expect(DateHelpers.formatFrenchDate(d, includeYear: true), equals('Lundi 4 mai 2026'));

      expect(isBookableWorkspace({'id': '1', 'isBookable': true}), isTrue);
      expect(isBookableWorkspace({'id': '2', 'isReservable': false}), isFalse);
      expect(isBookableWorkspace({'id': '3', 'type': 'Room'}), isFalse);
      expect(extractRoomName({'name': 'OpenSpace-04'}), equals('OpenSpace'));
      final synth = parseFloorFeaturesWithFallback(null, [
        {'id': 'ws-1', 'name': 'B01-01', 'type': 'Desk'}
      ]);
      expect(synth.length, equals(1));
    });
  });

  group('4. TeamMapScreen Isolation & Occupant Deduplication', () {
    testWidgets('Changing floor isolates map_selected_floor_id and deduplicates occupants panel', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-home',
        'refresh_token': 'mock-refresh',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'acc', 'refresh_token': 'ref'}), 200);
        }
        if (path.contains('/buildings/site-1/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-home', 'name': 'Étage Home'},
            {'id': 'fl-other', 'name': 'Étage Autre'},
          ]), 200);
        }
        if (path.contains('/floors/fl-home/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'WS-101', 'name': 'SalleA-01', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/floors/fl-other/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'WS-201', 'name': 'SalleB-01', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/data')) {
          return http.Response(jsonEncode({'features': <Object>[]}), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'WS-101',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'user': {'id': 'u-1', 'name': 'Alice Dupont'}
                }
              }
            ]
          }), 200);
        }
        return http.Response('[]', 200);
      });

      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: DateTime(2026, 11, 25),
          initialSiteId: 'site-1',
          initialFloorId: 'fl-home',
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Occupant WS-101 is stored under both 'WS-101' and 'ws-101' in occupants map,
      // yet panel must show count (1) and only 1 row without duplicate ValueKey.
      expect(find.text('Collègues présents (1)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle_occupants_panel_right')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('colleague_item_WS-101')), findsOneWidget);

      // Change floor to fl-other
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Étage Autre').last);
      await tester.pumpAndSettle();

      expect(await storage.getFloorId(), equals('fl-home'));
      expect(await storage.getMapSelectedFloorId(), equals('fl-other'));
    });
  });

  group('5. Unified AutomationEngine & State Drift Fix', () {
    test('AutomationEngine handles malformed vacation dates safely, preserves existing reservations, and records lastAutomationRun', () async {
      final storage = StorageService();
      await storage.saveRefreshToken('mock-token');
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-default');
      await storage.saveWorkspaceName('Bureau Défaut');
      await storage.saveHideWeekends(true);
      await storage.saveSkipPublicHolidays(false);

      // Pre-seed an existing reservation outside J+1..J+13 that must not be clobbered
      await storage.saveUserReservationsMap({
        '2026-12-30': {'workspaceId': 'ws-other', 'workspaceName': 'Autre Bureau'},
      });

      // Malformed vacation entry that previously threw FormatException on DateTime.parse
      await storage.saveVacations([
        {'start': 'invalid-date', 'end': '2026-10-15'},
      ]);

      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-default',
          siteId: 's-1',
          floorId: 'fl-1',
          workspaceId: 'ws-default',
          workspaceName: 'Bureau Défaut',
          days: [1], // Monday
        ),
      ]);

      final now = DateTime(2026, 10, 11); // Sun -> Mon Oct 12 & Mon Oct 19
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'acc', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': <Object>[]}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': <Object>[]}), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'me'}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          return http.Response(jsonEncode({'id': 'ok'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);
      final count = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
      );

      expect(count, equals(2));
      expect(await storage.getLastAutomationRun(), isNotNull);

      final allRes = await storage.getUserReservationsMap();
      expect(allRes.containsKey('2026-10-12'), isTrue);
      expect(allRes.containsKey('2026-10-19'), isTrue);
      expect(allRes['2026-12-30']?['workspaceName'], equals('Autre Bureau'));

      final elsewhere = await storage.getBookedElsewhereMap();
      expect(elsewhere['2026-12-30'], equals('Autre Bureau'));

      // Direct AutomationEngine.run returns detailed AutomationRunResult
      final result = await AutomationEngine.run(
        apiService: api,
        storageService: storage,
        enforceAutomationEnabled: true,
      );
      expect(result.abortedDueToDisabled, isTrue);
    });
  });
}
