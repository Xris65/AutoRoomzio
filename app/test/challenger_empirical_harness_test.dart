import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/widgets/offline_ribbon.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStateManager stateManager;
  late StorageService storage;

  setUp(() {
    stateManager = OfflineStateManager.instance;
    stateManager.reset();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  tearDown(() {
    stateManager.reset();
  });

  // =========================================================================
  // SCENARIO 1: Rapid Online / Offline Flapping
  // =========================================================================
  group('Scenario 1: Rapid Online / Offline Flapping', () {
    test('1A: 500 rapid alternating state flips maintain listener stability and no crash', () {
      int notifyCount = 0;
      void listener() => notifyCount++;
      stateManager.isOfflineNotifier.addListener(listener);

      for (int i = 0; i < 500; i++) {
        if (i % 2 == 0) {
          stateManager.markOffline();
          expect(stateManager.isOffline, isTrue);
        } else {
          stateManager.markOnline();
          expect(stateManager.isOffline, isFalse);
        }
      }

      stateManager.isOfflineNotifier.removeListener(listener);
      expect(notifyCount, equals(500));
      expect(stateManager.isOffline, isFalse);
    });

    testWidgets('1B: Rapid flapping in widget tree with OfflineRibbon causes no jitter, leaks, or overflow', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: stateManager.isOfflineNotifier,
              builder: (context, isOffline, _) {
                return Column(
                  children: [
                    Expanded(child: child ?? const SizedBox.shrink()),
                    if (isOffline) const OfflineRibbon(),
                  ],
                );
              },
            );
          },
          home: const Scaffold(
            body: Center(child: Text('Main Screen Content')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsNothing);

      // Flap 60 times across simulated animation frames
      for (int i = 0; i < 60; i++) {
        if (i % 2 == 0) {
          stateManager.markOffline();
        } else {
          stateManager.markOnline();
        }
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'No exception during frame $i of flapping');
      }

      // Final state offline
      stateManager.markOffline();
      await tester.pumpAndSettle();
      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(find.text(OfflineRibbon.ribbonText), findsOneWidget);

      // Final state online
      stateManager.markOnline();
      await tester.pumpAndSettle();
      expect(find.byType(OfflineRibbon), findsNothing);
    });

    test('1C: Concurrent flapping with 40 requests alternating failure and success', () async {
      int requestCounter = 0;
      final client = MockClient((req) async {
        final id = ++requestCounter;
        await Future.delayed(Duration(milliseconds: 2 + (id % 15)));
        if (id % 2 == 0) {
          throw const SocketException('Transient socket drop');
        } else {
          return http.Response(jsonEncode({'status': 'ok', 'id': id}), 200);
        }
      });

      final offlineClient = OfflineAwareHttpClient(client, stateManager);

      final futures = List.generate(40, (index) async {
        try {
          return await offlineClient.get(Uri.parse('https://api.my.roomz.io/flapping?req=$index'));
        } catch (e) {
          return null;
        }
      });

      final results = await Future.wait(futures);
      expect(results.length, equals(40));
      expect(results.where((r) => r != null).length, equals(20));
      expect(results.where((r) => r == null).length, equals(20));
    });
  });

  // =========================================================================
  // SCENARIO 2: Non-blocking Guarantees (Requirement R1)
  // =========================================================================
  group('Scenario 2: Non-blocking Guarantees (R1)', () {
    test('2A: Desk reservation while offline still sends real HTTP request', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final recordedRequests = <http.BaseRequest>[];
      final client = MockClient((req) async {
        recordedRequests.add(req);
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'test_token', 'refresh_token': 'ref_token'}), 200);
        }
        if (req.url.path.contains('/bookings')) {
          return http.Response(jsonEncode({'id': 'b-101', 'status': 'Confirmed'}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(storage: storage, client: client);

      // Call reserveWorkspaceForColleague while offline
      final result = await api.reserveWorkspaceForColleague(
        date: '2026-11-15',
        token: 'test_token',
        workspaceId: 'ws-42',
        colleagueId: 'ext_123',
        colleagueName: 'Bob Martin',
      );

      // Verify a real HTTP request was issued
      expect(recordedRequests.any((r) => r.url.path.contains('/bookings')), isTrue);
      expect(result.isSuccess, isTrue);
      // Because server responded with 200, offline mode is automatically restored
      expect(stateManager.isOffline, isFalse);
    });

    testWidgets('2B: HomeScreen pull-to-refresh while offline still issues real HTTP calls', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final recordedRequests = <String>[];
      final client = MockClient((req) async {
        recordedRequests.add(req.url.path);
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'test_token', 'refresh_token': 'ref_token'}), 200);
        }
        if (req.url.path.contains('/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        return http.Response('[]', 200);
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'valid_token',
        'workspace_id': 'ws-1',
        'workspace_name': 'My Desk',
        'floor_id': 'fl-1',
        'initial_tab': 0,
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Verify requests were made during initial load even though app started or was set offline
      expect(recordedRequests.isNotEmpty, isTrue,
          reason: 'HomeScreen must never short-circuit API requests when offline');
    });

    testWidgets('2C: TeamMapScreen floor navigation while offline issues real HTTP requests', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final recordedRequests = <String>[];
      final client = MockClient((req) async {
        recordedRequests.add(req.url.path);
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'test_token', 'refresh_token': 'ref_token'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Floor 1'},
            {'id': 'fl-2', 'name': 'Floor 2'},
          ]), 200);
        }
        // Throw connectivity error on floor detail / occupancy
        throw const SocketException('Connection refused');
      });

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: 'fl-1',
            initialDate: DateTime(2026, 11, 15),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Requests were attempted
      expect(recordedRequests.isNotEmpty, isTrue);
      final initialCount = recordedRequests.length;

      // Navigate to next day via arrow
      final nextDay = find.byIcon(Icons.chevron_right);
      if (nextDay.evaluate().isNotEmpty) {
        await tester.tap(nextDay);
        await tester.pumpAndSettle();

        // More requests should have been attempted
        expect(recordedRequests.length, greaterThan(initialCount),
            reason: 'Navigating to another date while offline must issue new network requests');
      }
    });
  });

  // =========================================================================
  // SCENARIO 3: Storage Corruption & Boundary Resilience (Requirement R3)
  // =========================================================================
  group('Scenario 3: Storage Corruption & Boundary Resilience (R3)', () {
    test('3A: Corrupted booked_elsewhere_map falls back gracefully', () async {
      final prefs = await SharedPreferences.getInstance();

      // Case 1: Malformed JSON syntax
      await prefs.setString('booked_elsewhere_map', '{{{corrupted_not_json:');
      var res = await storage.getBookedElsewhereMap();
      expect(res, isA<Map<String, String>>());
      expect(res.isEmpty, isTrue);

      // Case 2: JSON is a list instead of a map
      await prefs.setString('booked_elsewhere_map', '["2026-11-01", "2026-11-02"]');
      res = await storage.getBookedElsewhereMap();
      expect(res, isA<Map<String, String>>());

      // Case 3: JSON is a raw primitive string or number
      await prefs.setString('booked_elsewhere_map', '12345');
      res = await storage.getBookedElsewhereMap();
      expect(res, isA<Map<String, String>>());

      // Case 4: Fallback to legacy string list if present
      await prefs.remove('booked_elsewhere_map');
      await prefs.setStringList('booked_elsewhere_dates', ['2026-11-05']);
      res = await storage.getBookedElsewhereMap();
      expect(res['2026-11-05'], equals('Ailleurs'));
    });

    test('3B: Corrupted occupied_by_others_map falls back gracefully', () async {
      final prefs = await SharedPreferences.getInstance();

      // Case 1: Malformed JSON
      await prefs.setString('occupied_by_others_map', '{broken_json: missing_quotes}');
      var res = await storage.getOccupiedByOthers();
      expect(res, isA<Map<String, String>>());
      expect(res.isEmpty, isTrue);

      // Case 2: JSON is an array of objects
      await prefs.setString('occupied_by_others_map', '[{"date": "2026-11-01"}]');
      res = await storage.getOccupiedByOthers();
      expect(res, isA<Map<String, String>>());
      expect(res.isEmpty, isTrue);

      // Case 3: JSON boolean
      await prefs.setString('occupied_by_others_map', 'true');
      res = await storage.getOccupiedByOthers();
      expect(res, isA<Map<String, String>>());
      expect(res.isEmpty, isTrue);
    });

    test('3C: Corrupted floor_occupants falls back gracefully', () async {
      final prefs = await SharedPreferences.getInstance();
      const floorId = 'fl-corrupted';
      const date = '2026-11-10';
      final key = 'floor_occupants_${floorId}_$date';

      // Case 1: Malformed JSON
      await prefs.setString(key, '{"ws-1": "not_a_desk_occupant_map');
      var res = await storage.getFloorOccupants(floorId, date);
      expect(res, isA<Map<String, DeskOccupant>>());
      expect(res.isEmpty, isTrue);

      // Case 2: Value is not a map
      await prefs.setString(key, jsonEncode({'ws-1': 'invalid_string_value'}));
      res = await storage.getFloorOccupants(floorId, date);
      expect(res, isA<Map<String, DeskOccupant>>());
      expect(res.isEmpty, isTrue);

      // Case 3: Missing fields inside occupant map
      await prefs.setString(key, jsonEncode({
        'ws-1': {'unexpected': 'data'}
      }));
      res = await storage.getFloorOccupants(floorId, date);
      expect(res, isA<Map<String, DeskOccupant>>());
      expect(res.containsKey('ws-1'), isTrue);
      // DeskOccupant defaults missing name to 'Occupant'
      expect(res['ws-1']?.occupantName, equals('Occupant'));
    });

    testWidgets('3D: HomeScreen loads with corrupted SharedPreferences without crashing', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-1',
        'workspace_name': 'My Desk',
        'floor_id': 'fl-1',
        'booked_elsewhere_map': '{"corrupted": json}',
        'occupied_by_others_map': '[1, 2, 3]',
        'delegated_bookings_map': 'true',
        'initial_tab': 0,
      });

      final client = MockClient((req) async {
        throw const SocketException('Offline');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'HomeScreen must handle corrupted SharedPreferences without throwing red screen');
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('3E: TeamMapScreen loads with corrupted floor occupant cache without crashing', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const floorId = 'fl-crash-test';
      final testDate = DateTime(2026, 11, 10);
      const testDateStr = '2026-11-10';

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': floorId,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'floor_occupants_${floorId}_$testDateStr': '{{{malformed_json_###',
        'floor_plan_$floorId': 'invalid_plan_string',
        'floor_workspaces_$floorId': 'not_a_list',
      });

      final client = MockClient((req) async {
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': floorId, 'name': 'Corrupted Floor'}]), 200);
        }
        throw const SocketException('Offline');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: floorId,
            initialDate: testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'TeamMapScreen must handle corrupted floor plan and occupants without crashing');
      expect(find.byType(TeamMapScreen), findsOneWidget);
    });
  });
}
