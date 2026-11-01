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
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;
  late OfflineStateManager stateManager;

  setUp(() {
    stateManager = OfflineStateManager.instance;
    stateManager.reset();
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  tearDown(() {
    stateManager.reset();
  });

  group('Offline Screen Resilience & Non-Destructive Cache (R3.1, R3.2, R3.3, R3.4)', () {
    // ── R3.1, R3.2, R3.3: HomeScreen Offline Resilience ───────────────────────
    testWidgets('HomeScreen retains cached personal, elsewhere, and delegated reservations during network failure', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      var targetDate = now.add(const Duration(days: 2));
      if (targetDate.weekday == DateTime.saturday) targetDate = targetDate.add(const Duration(days: 2));
      if (targetDate.weekday == DateTime.sunday) targetDate = targetDate.add(const Duration(days: 1));
      final dateStr = targetDate.toIso8601String().split('T').first;

      // 1. Seed storage with cached bookings, delegated bookings, and third-party occupancy
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'workspace_id': 'ws-home',
        'workspace_name': 'Bureau Principal 4A',
        'floor_id': 'fl-floor-1',
        'booked_dates': [dateStr],
        'booked_elsewhere_map': jsonEncode({dateStr: 'Site Nord - Desk 12'}),
        'booked_elsewhere_dates': [dateStr],
        'delegated_bookings_map': jsonEncode({dateStr: 'Alice Dupont|Desk 3'}),
        'occupied_by_others_map': jsonEncode({dateStr: 'DUPONT Jean'}),
        'selected_days': ['1', '2', '3', '4', '5'],
        'automation_enabled': false,
        'hide_weekends': true,
        'initial_tab': 0,
      });

      // 2. Simulate complete network failure (SocketException)
      final client = MockClient((req) async {
        throw const SocketException('OS Error: Network unreachable, errno = 101');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 3. Verify OfflineStateManager flipped to offline
      expect(stateManager.isOffline, isTrue);

      // 4. Verify cache in StorageService was NOT cleared to empty lists or maps
      final persistedBooked = await storage.getBookedDates();
      final persistedElsewhere = await storage.getBookedElsewhereMap();
      final persistedDelegated = await storage.getDelegatedBookingsMap();
      final persistedOccupied = await storage.getOccupiedByOthers();

      expect(persistedBooked, contains(dateStr), reason: 'Personal reservations must not be wiped');
      expect(persistedElsewhere.containsKey(dateStr), isTrue, reason: 'Elsewhere reservations must not be wiped');
      expect(persistedDelegated.containsKey(dateStr), isTrue, reason: 'Delegated reservations must not be wiped');
      expect(persistedOccupied.containsKey(dateStr), isTrue, reason: 'Occupancy must not be wiped');

      // 5. Verify UI does not show empty state and shows workspace title
      expect(find.text('Aucune réservation prévue.'), findsNothing);
      expect(find.text('Bureau Principal 4A'), findsOneWidget);
    });

    // ── R3.4: TeamMapScreen Offline Resilience ────────────────────────────────
    testWidgets('TeamMapScreen retains cached floor plan, workspaces, and occupants during network failure', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const floorId = 'floor-map-01';
      const dateStr = '2026-11-16';

      final samplePlan = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-desk-1', 'workspaceType': 'Desk', 'name': 'A-01'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
              ]
            }
          }
        ]
      };

      final sampleWorkspaces = [
        {'id': 'ws-desk-1', 'name': 'A-01', 'isBookable': true}
      ];

      const sampleOccupant = DeskOccupant(
        workspaceId: 'ws-desk-1',
        occupantName: 'Sophie Martin',
        occupantEmail: 'sophie@company.com',
        isMe: false,
        isDelegated: false,
      );

      // Seed SharedPreferences
      SharedPreferences.setMockInitialValues({
        'site_id': 'site-hq',
        'floor_id': floorId,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'hide_weekends': true,
      });

      // Save structured cache using StorageService methods
      await storage.saveFloorPlanData(floorId, samplePlan);
      await storage.saveFloorWorkspaces(floorId, sampleWorkspaces);
      await storage.saveFloorOccupants(floorId, dateStr, {'ws-desk-1': sampleOccupant});

      // Simulate token refresh and floor lookup success, but floor data/occupancy network drop
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': floorId, 'name': '1st Floor'}]), 200);
        }
        // Network drop during floor plan, workspaces, and occupants synchronization
        throw const SocketException('Connection refused: api.my.roomz.io');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: floorId,
            initialDate: DateTime.parse(dateStr),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify OfflineStateManager flipped to offline
      expect(stateManager.isOffline, isTrue);

      // Verify StorageService data remained intact
      final cachedPlan = await storage.getFloorPlanData(floorId);
      final cachedWs = await storage.getFloorWorkspaces(floorId);
      final cachedOccs = await storage.getFloorOccupants(floorId, dateStr);

      expect(cachedPlan, isNotNull);
      expect(cachedWs, hasLength(1));
      expect(cachedOccs.containsKey('ws-desk-1'), isTrue);
      expect(cachedOccs['ws-desk-1']?.occupantName, 'Sophie Martin');

      // Verify WorkspaceMapViewer is mounted with cached occupants and workspaces
      final viewerFinder = find.byType(WorkspaceMapViewer);
      expect(viewerFinder, findsOneWidget);
      final viewer = tester.widget<WorkspaceMapViewer>(viewerFinder);
      expect(viewer.occupants.containsKey('ws-desk-1'), isTrue);
      expect(viewer.occupants['ws-desk-1']?.occupantName, equals('Sophie Martin'));
      expect(viewer.features, hasLength(1));
      expect(viewer.workspaces, hasLength(1));
    });

    // ── Continuous Unblocked Retry & Reactivity ───────────────────────────────
    testWidgets('actions continue to trigger requests when offline and recover on server response', (tester) async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'stored-refresh-token',
      });

      int networkRequests = 0;
      final client = MockClient((req) async {
        networkRequests++;
        return http.Response(jsonEncode({'access_token': 'new-token', 'refresh_token': 'new-refresh'}), 200);
      });

      final api = RoomzApiService(storage: storage, client: client);

      // Trigger token refresh through api service (which uses OfflineAwareHttpClient)
      final token = await api.refreshMyToken();

      expect(networkRequests, greaterThan(0), reason: 'Request must not be blocked when offline');
      expect(token, equals('new-token'));
      expect(stateManager.isOffline, isFalse, reason: 'Successful HTTP response must restore online mode');
    });
    testWidgets('HomeScreen sync / refresh attempts API call and exits offline mode when server responds (Bug #1)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final now = DateTime.now();
      final dateStr = now.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'workspace_id': 'ws-home',
        'workspace_name': 'Bureau Test',
        'floor_id': 'fl-floor-1',
        'booked_dates': [dateStr],
        'selected_days': ['1', '2', '3', '4', '5'],
        'automation_enabled': false,
        'hide_weekends': true,
        'initial_tab': 1,
      });

      int networkRequests = 0;
      final client = MockClient((req) async {
        networkRequests++;
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({
            'bookings': [
              {
                'type': 'Reserved',
                'eventDate': dateStr,
                'workspaceId': 'ws-home',
                'creator': {'id': 'my-user-id', 'name': 'Me'},
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/workspaces/')) {
          return http.Response(jsonEncode({
            'timeSlots': []
          }), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'my-user-id'}), 200);
        }
        return http.Response(jsonEncode({}), 200);
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger the refresh button
      final syncButton = find.byTooltip('Synchroniser avec MyRoomz');
      expect(syncButton, findsOneWidget);
      await tester.tap(syncButton);
      await tester.pumpAndSettle();

      // Verify network requests were attempted despite being offline initially
      expect(networkRequests, greaterThan(0), reason: 'API call must be made during refresh even when offline');
      expect(stateManager.isOffline, isFalse, reason: 'Successful sync must immediately exit offline mode');
    });
    testWidgets('HomeScreen pull-to-refresh attempts API call and exits offline mode when server responds (Bug #1)', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final now = DateTime.now();
      final dateStr = now.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'workspace_id': 'ws-home',
        'workspace_name': 'Bureau Test',
        'floor_id': 'fl-floor-1',
        'booked_dates': [dateStr],
        'selected_days': ['1', '2', '3', '4', '5'],
        'automation_enabled': false,
        'hide_weekends': true,
        'initial_tab': 0,
        'pull_to_refresh_enabled': true,
      });

      int networkRequests = 0;
      final client = MockClient((req) async {
        networkRequests++;
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({
            'bookings': [
              {
                'type': 'Reserved',
                'eventDate': dateStr,
                'workspaceId': 'ws-home',
                'creator': {'id': 'my-user-id', 'name': 'Me'},
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/workspaces/')) {
          return http.Response(jsonEncode({
            'timeSlots': []
          }), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'my-user-id'}), 200);
        }
        return http.Response(jsonEncode({}), 200);
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure RefreshIndicator is present and trigger pull-down gesture
      final refreshIndicator = find.byType(RefreshIndicator);
      expect(refreshIndicator, findsWidgets);

      await tester.fling(find.byType(SingleChildScrollView).first, const Offset(0.0, 400.0), 1000.0);
      await tester.pumpAndSettle();

      // Verify network requests were attempted despite being offline initially
      expect(networkRequests, greaterThan(0), reason: 'API call must be made during pull-to-refresh even when offline');
      expect(stateManager.isOffline, isFalse, reason: 'Successful pull-to-refresh must immediately exit offline mode');
    });
  });
}
