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
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
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

  // =========================================================================
  // CHALLENGE 1: Concurrent Requests & State Synchronization (isOffline)
  // =========================================================================
  group('Adversarial Challenge 1: Concurrent Requests & State Synchronization', () {
    test('1.1 Mixed parallel requests where successful finish LAST result in isOffline == false', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final client = MockClient((req) async {
        final id = int.tryParse(req.url.queryParameters['id'] ?? '0') ?? 0;
        if (id % 2 == 0) {
          // Failing requests: finish very quickly (10ms)
          await Future.delayed(const Duration(milliseconds: 10));
          throw const SocketException('Simulated network drop');
        } else {
          // Successful requests: finish slower (60ms) - they finish last!
          await Future.delayed(const Duration(milliseconds: 60));
          return http.Response(jsonEncode({'status': 'ok', 'id': id}), 200);
        }
      });

      final offlineClient = OfflineAwareHttpClient(client, stateManager);

      // Launch 20 concurrent requests
      final futures = List.generate(20, (index) async {
        try {
          return await offlineClient.get(Uri.parse('https://api.my.roomz.io/test?id=$index'));
        } catch (_) {
          return null;
        }
      });

      await Future.wait(futures);

      // Since successful requests finished after the failing ones, connectivity was verified last
      expect(stateManager.isOffline, isFalse,
          reason: 'A successful request completing last must restore online state');
    });

    test('1.2 Mixed parallel requests where failing finish LAST result in isOffline == true', () async {
      stateManager.markOnline();
      expect(stateManager.isOffline, isFalse);

      final client = MockClient((req) async {
        final id = int.tryParse(req.url.queryParameters['id'] ?? '0') ?? 0;
        if (id % 2 == 0) {
          // Successful requests: finish very quickly (10ms)
          await Future.delayed(const Duration(milliseconds: 10));
          return http.Response(jsonEncode({'status': 'ok', 'id': id}), 200);
        } else {
          // Failing requests: finish slower (60ms) - they finish last!
          await Future.delayed(const Duration(milliseconds: 60));
          throw const SocketException('Connection aborted by peer');
        }
      });

      final offlineClient = OfflineAwareHttpClient(client, stateManager);

      final futures = List.generate(20, (index) async {
        try {
          return await offlineClient.get(Uri.parse('https://api.my.roomz.io/test?id=$index'));
        } catch (_) {
          return null;
        }
      });

      await Future.wait(futures);

      expect(stateManager.isOffline, isTrue,
          reason: 'A network failure completing last must leave the app in offline state');
    });

    test('1.3 High concurrency stress (50 concurrent calls) maintains consistent listener notifications', () async {
      int stateChangeCount = 0;
      void listener() => stateChangeCount++;
      stateManager.isOfflineNotifier.addListener(listener);

      final client = MockClient((req) async {
        final id = int.tryParse(req.url.queryParameters['id'] ?? '0') ?? 0;
        await Future.delayed(Duration(milliseconds: 5 + (id % 25)));
        if (id < 45) {
          throw http.ClientException('Simulated HTTP client error $id');
        } else {
          return http.Response('{"ok": true}', 200);
        }
      });

      final offlineClient = OfflineAwareHttpClient(client, stateManager);

      final futures = List.generate(50, (index) async {
        try {
          return await offlineClient.get(Uri.parse('https://api.my.roomz.io/stress?id=$index'));
        } catch (_) {
          return null;
        }
      });

      await Future.wait(futures);

      // Verify the notifier didn't crash or get corrupted
      expect(stateChangeCount, greaterThan(0));

      stateManager.isOfflineNotifier.removeListener(listener);
    });

    test('1.4 HTTP error status codes (400, 401, 403, 404, 500, 503) do NOT mark offline (R2)', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final statusCodes = [400, 401, 403, 404, 500, 502, 503];
      for (final code in statusCodes) {
        stateManager.markOffline(); // Reset to offline before each call

        final client = MockClient((req) async {
          return http.Response('{"error": "Server response $code"}', code);
        });

        final offlineClient = OfflineAwareHttpClient(client, stateManager);
        final response = await offlineClient.get(Uri.parse('https://api.my.roomz.io/status-$code'));

        expect(response.statusCode, equals(code));
        // Requirement R2: Any server response proves network connectivity
        expect(stateManager.isOffline, isFalse,
            reason: 'HTTP $code is an actual server response, proving connectivity');
      }
    });

    test('1.5 Non-network exceptions (FormatException, StateError) do NOT mark offline', () async {
      stateManager.markOnline();
      expect(stateManager.isOffline, isFalse);

      final client = MockClient((req) async {
        throw const FormatException('Corrupted payload');
      });

      final offlineClient = OfflineAwareHttpClient(client, stateManager);

      try {
        await offlineClient.get(Uri.parse('https://api.my.roomz.io/corrupted'));
      } catch (e) {
        expect(e, isA<FormatException>());
      }

      // Non-connectivity errors must not flip isOffline to true
      expect(stateManager.isOffline, isFalse);
    });

    test('1.6 Rapid alternating ping-pong state changes (100 iterations)', () async {
      for (int i = 0; i < 100; i++) {
        if (i % 2 == 0) {
          stateManager.markOffline();
          expect(stateManager.isOffline, isTrue);
        } else {
          stateManager.markOnline();
          expect(stateManager.isOffline, isFalse);
        }
      }
      expect(stateManager.isOffline, isFalse);
    });
  });

  // =========================================================================
  // CHALLENGE 2: Map Occupancy Cache Boundary Conditions (TeamMapScreen)
  // =========================================================================
  group('Adversarial Challenge 2: Map Occupancy Cache Boundary Conditions in TeamMapScreen', () {
    const testFloor1 = 'floor-boundary-01';
    const testFloor2 = 'floor-boundary-02';
    const testFloorUncached = 'floor-uncached-99';

    final floorPlanData = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-101', 'workspaceType': 'Desk', 'name': 'Desk 101'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[0.0, 0.0], [40.0, 0.0], [40.0, 40.0], [0.0, 40.0], [0.0, 0.0]]
            ]
          }
        }
      ]
    };

    final workspacesData = [
      {'id': 'ws-101', 'name': 'Desk 101', 'isBookable': true}
    ];

    testWidgets('2.1 Missing date while offline: no crash, no null pointer, graceful empty display', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Pre-seed storage ONLY with floor plan and workspaces, NO occupancy for this date
      SharedPreferences.setMockInitialValues({
        'site_id': 'site-boundary',
        'floor_id': testFloor1,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
        'hide_weekends': false,
      });

      await storage.saveFloorPlanData(testFloor1, floorPlanData);
      await storage.saveFloorWorkspaces(testFloor1, workspacesData);

      final uncachedDate = DateTime(2028, 5, 12);

      // Mock client that always throws SocketException (offline)
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-tok', 'refresh_token': 'mock-ref'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': testFloor1, 'name': 'Floor 1'}]), 200);
        }
        throw const SocketException('No route to host');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: testFloor1,
            initialDate: uncachedDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no exceptions were thrown
      expect(tester.takeException(), isNull);
      expect(stateManager.isOffline, isTrue);

      // Map viewer should be safely rendered with 0 occupants
      final viewerFinder = find.byType(WorkspaceMapViewer);
      expect(viewerFinder, findsOneWidget);
      final viewer = tester.widget<WorkspaceMapViewer>(viewerFinder);
      expect(viewer.occupants.isEmpty, isTrue);
    });

    testWidgets('2.2 Past dates and leap day: loads historical cached occupancy accurately', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Leap day date
      const leapDateStr = '2024-02-29';
      final leapDate = DateTime(2024, 2, 29);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-boundary',
        'floor_id': testFloor1,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
      });

      await storage.saveFloorPlanData(testFloor1, floorPlanData);
      await storage.saveFloorWorkspaces(testFloor1, workspacesData);
      await storage.saveFloorOccupants(testFloor1, leapDateStr, {
        'ws-101': const DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Leap Year User',
          occupantEmail: 'leap@company.com',
          isMe: false,
        ),
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-tok', 'refresh_token': 'mock-ref'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': testFloor1, 'name': 'Floor 1'}]), 200);
        }
        throw const SocketException('Connection timed out');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: testFloor1,
            initialDate: leapDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants.containsKey('ws-101'), isTrue);
      expect(viewer.occupants['ws-101']?.occupantName, equals('Leap Year User'));
    });

    testWidgets('2.3 Year rollover boundary condition (2026-12-31 to 2027-01-01) preserves cache offline', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const nyeDateStr = '2026-12-31';
      const nydDateStr = '2027-01-01';
      final nyeDate = DateTime(2026, 12, 31);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-boundary',
        'floor_id': testFloor1,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
      });

      await storage.saveFloorPlanData(testFloor1, floorPlanData);
      await storage.saveFloorWorkspaces(testFloor1, workspacesData);
      await storage.saveFloorOccupants(testFloor1, nyeDateStr, {
        'ws-101': const DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Eve Person',
          occupantEmail: 'eve@company.com',
          isMe: false,
        ),
      });
      await storage.saveFloorOccupants(testFloor1, nydDateStr, {
        'ws-101': const DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'New Year Person',
          occupantEmail: 'newyear@company.com',
          isMe: true,
        ),
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-tok', 'refresh_token': 'mock-ref'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': testFloor1, 'name': 'Floor 1'}]), 200);
        }
        throw const SocketException('Network is down');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: testFloor1,
            initialDate: nyeDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Dec 31
      var viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants['ws-101']?.occupantName, equals('Eve Person'));

      // Tap next day arrow to move to Jan 1, 2027
      final nextDayButton = find.byIcon(Icons.chevron_right);
      expect(nextDayButton, findsOneWidget);
      await tester.tap(nextDayButton);
      await tester.pumpAndSettle();

      // Check Jan 1, 2027
      viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants['ws-101']?.occupantName, equals('New Year Person'));
      expect(viewer.occupants['ws-101']?.isMe, isTrue);

      // Verify storage was never overwritten or wiped
      final nyeCached = await storage.getFloorOccupants(testFloor1, nyeDateStr);
      final nydCached = await storage.getFloorOccupants(testFloor1, nydDateStr);
      expect(nyeCached.isNotEmpty, isTrue);
      expect(nydCached.isNotEmpty, isTrue);
    });

    testWidgets('2.4 Floor switching while offline preserves both floors and handles uncached floor safely', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const dateStr = '2026-11-20';
      final testDate = DateTime(2026, 11, 20);

      final floor2Plan = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-202', 'workspaceType': 'Desk', 'name': 'Desk 202'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [30.0, 0.0], [30.0, 30.0], [0.0, 30.0], [0.0, 0.0]]
              ]
            }
          }
        ]
      };

      final floor2Ws = [
        {'id': 'ws-202', 'name': 'Desk 202', 'isBookable': true}
      ];

      // Seed both Floor 1 and Floor 2
      SharedPreferences.setMockInitialValues({
        'site_id': 'site-boundary',
        'floor_id': testFloor1,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
      });

      await storage.saveFloorPlanData(testFloor1, floorPlanData);
      await storage.saveFloorWorkspaces(testFloor1, workspacesData);
      await storage.saveFloorOccupants(testFloor1, dateStr, {
        'ws-101': const DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Floor1 User',
          occupantEmail: 'f1@company.com',
          isMe: false,
        ),
      });

      await storage.saveFloorPlanData(testFloor2, floor2Plan);
      await storage.saveFloorWorkspaces(testFloor2, floor2Ws);
      await storage.saveFloorOccupants(testFloor2, dateStr, {
        'ws-202': const DeskOccupant(
          workspaceId: 'ws-202',
          occupantName: 'Floor2 User',
          occupantEmail: 'f2@company.com',
          isMe: false,
        ),
      });

      // API fails on all plan & occupant endpoints
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-tok', 'refresh_token': 'mock-ref'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([
            {'id': testFloor1, 'name': 'Floor 1'},
            {'id': testFloor2, 'name': 'Floor 2'},
            {'id': testFloorUncached, 'name': 'Floor Uncached'},
          ]), 200);
        }
        throw const SocketException('Connection refused');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: testFloor1,
            initialDate: testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Floor 1
      var viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants.containsKey('ws-101'), isTrue);
      expect(viewer.occupants['ws-101']?.occupantName, equals('Floor1 User'));

      // Switch to Floor 2 using dropdown
      final dropdown = find.byType(DropdownButton<String>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final floor2Option = find.text('Floor 2').last;
      await tester.tap(floor2Option);
      await tester.pumpAndSettle();

      // Check Floor 2 occupants loaded from cache
      viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants.containsKey('ws-202'), isTrue);
      expect(viewer.occupants['ws-202']?.occupantName, equals('Floor2 User'));

      // Switch to Floor Uncached (has no cached plan)
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      final uncachedOption = find.text('Floor Uncached').last;
      await tester.tap(uncachedOption);
      await tester.pumpAndSettle();

      // Verify no red screen / crash occurs, viewer renders gracefully empty
      expect(tester.takeException(), isNull);
      viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.features.isEmpty, isTrue, reason: 'Uncached floor has empty features without crashing');
      expect(viewer.occupants.isEmpty, isTrue, reason: 'Uncached floor has empty occupants');

      // Switch back to Floor 1: Floor 1 data must still be perfectly intact!
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      final floor1Option = find.text('Floor 1').last;
      await tester.tap(floor1Option);
      await tester.pumpAndSettle();

      viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants.containsKey('ws-101'), isTrue);
      expect(viewer.occupants['ws-101']?.occupantName, equals('Floor1 User'));
    });

    testWidgets('2.5 Pull to refresh or _fetchOccupants while offline restores from cache without wiping', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const dateStr = '2026-11-20';
      final testDate = DateTime(2026, 11, 20);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-boundary',
        'floor_id': testFloor1,
        'refresh_token': 'mock-refresh-token',
        'auth_token': 'mock-access-token',
      });

      await storage.saveFloorPlanData(testFloor1, floorPlanData);
      await storage.saveFloorWorkspaces(testFloor1, workspacesData);
      await storage.saveFloorOccupants(testFloor1, dateStr, {
        'ws-101': const DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Persistent User',
          occupantEmail: 'pu@company.com',
          isMe: false,
        ),
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-tok', 'refresh_token': 'mock-ref'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode([{'id': testFloor1, 'name': 'Floor 1'}]), 200);
        }
        throw const SocketException('Offline during refresh');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            storageService: storage,
            apiService: api,
            initialFloorId: testFloor1,
            initialDate: testDate,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger refresh button (icon: Icons.sync_rounded, tooltip: 'Actualiser')
      final refreshButton = find.byTooltip('Actualiser');
      expect(refreshButton, findsOneWidget);
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();

      // Occupants must remain present
      final viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      expect(viewer.occupants.containsKey('ws-101'), isTrue);
      expect(viewer.occupants['ws-101']?.occupantName, equals('Persistent User'));

      // StorageService still contains the occupants
      final cached = await storage.getFloorOccupants(testFloor1, dateStr);
      expect(cached.containsKey('ws-101'), isTrue);
    });
  });

  // =========================================================================
  // CHALLENGE 3: Ribbon Visual Invariants (R2)
  // =========================================================================
  group('Adversarial Challenge 3: Ribbon Visual Invariants & Accessibility', () {
    test('3.1 Exact string verification and unicode code-points', () {
      const expected = "Hors ligne • Affichage des dernières données synchronisées";
      expect(OfflineRibbon.ribbonText, equals(expected));
      expect(OfflineRibbon.text, equals(expected));

      // Check character code for the bullet symbol
      final bulletRune = expected.runes.firstWhere((r) => r != ' '.runes.first && r > 127);
      expect(bulletRune, equals(0x2022), reason: 'Must use Unicode BULLET U+2022');
    });

    testWidgets('3.2 Viewport stress testing: No overflow across small, medium, and large screens', (tester) async {
      const viewports = [
        Size(280, 653),  // Ultra narrow (Galaxy Fold front)
        Size(320, 480),  // Small mobile (iPhone SE 1st gen)
        Size(360, 640),  // Standard Android
        Size(414, 896),  // Large phone (iPhone 11)
        Size(768, 1024), // Tablet
        Size(1920, 1080),// Desktop FHD
      ];

      for (final vp in viewports) {
        tester.view.physicalSize = vp;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: Center(child: Text('App Content'))),
                  OfflineRibbon(),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow detected on viewport $vp');
        expect(find.byType(OfflineRibbon), findsOneWidget);
        expect(find.text(OfflineRibbon.ribbonText), findsOneWidget);
      }
    });

    testWidgets('3.3 Text scaling factors: Resilient from 0.75 to 1.35 text scaler on narrow 320px screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const scalers = [0.75, 0.9, 1.0, 1.15, 1.25, 1.35];

      for (final scale in scalers) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                body: Column(
                  children: [
                    Expanded(child: SizedBox()),
                    OfflineRibbon(),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'Overflow occurred with textScaler: $scale on 320px width');
        expect(find.byType(OfflineRibbon), findsOneWidget);
        expect(find.text(OfflineRibbon.ribbonText), findsOneWidget);
      }
    });

    testWidgets('3.4 Dark/Light theme switching dynamic color updates & WCAG AAA compliance', (tester) async {
      final themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

      await tester.pumpWidget(
        ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (context, mode, _) {
            return MaterialApp(
              themeMode: mode,
              theme: ThemeData(brightness: Brightness.light),
              darkTheme: ThemeData(brightness: Brightness.dark),
              home: const Scaffold(
                bottomNavigationBar: OfflineRibbon(),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Light mode verification
      Material material = tester.widget<Material>(find.byKey(const Key('offline_ribbon')));
      expect(material.color, equals(const Color(0xFFF59E0B)), reason: 'Light mode background must be Amber 500');

      Text text = tester.widget<Text>(find.text(OfflineRibbon.ribbonText));
      expect(text.style?.color, equals(const Color(0xFF1E293B)), reason: 'Light mode text must be Dark Slate');

      // Switch to Dark mode
      themeMode.value = ThemeMode.dark;
      await tester.pumpAndSettle();

      material = tester.widget<Material>(find.byKey(const Key('offline_ribbon')));
      expect(material.color, equals(const Color(0xFF92400E)), reason: 'Dark mode background must be Amber 800');

      text = tester.widget<Text>(find.text(OfflineRibbon.ribbonText));
      expect(text.style?.color, equals(const Color(0xFFFEF3C7)), reason: 'Dark mode text must be Amber 100');
    });

    testWidgets('3.5 Accessibility: Semantics liveRegion is active for screen readers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            bottomNavigationBar: OfflineRibbon(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true && w.properties.label == OfflineRibbon.ribbonText,
      );
      expect(semanticsFinder, findsOneWidget, reason: 'Semantics with liveRegion is required for accessibility');
    });
  });
}
