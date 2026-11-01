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
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/screens/setup_screen.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';

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

  group('StorageService - Floor and Desk Cache Persistence', () {
    test('saveCachedFloors and getCachedFloors persist and retrieve floors by siteId', () async {
      const siteId = 'site-123';
      final floors = [
        {'id': 'floor-01', 'name': 'Étage 1'},
        {'id': 'floor-02', 'name': 'Étage 2'},
      ];

      await storage.saveCachedFloors(siteId, floors);
      final retrieved = await storage.getCachedFloors(siteId);

      expect(retrieved.length, equals(2));
      expect(retrieved[0]['id'], equals('floor-01'));
      expect(retrieved[0]['name'], equals('Étage 1'));
      expect(retrieved[1]['id'], equals('floor-02'));
    });

    test('getCachedFloors returns empty list for unknown siteId', () async {
      final retrieved = await storage.getCachedFloors('unknown-site');
      expect(retrieved, isEmpty);
    });

    test('saveCachedSites and getCachedSites persist and retrieve sites', () async {
      final sites = [
        {'id': 'site-A', 'name': 'Siège Paris'},
        {'id': 'site-B', 'name': 'Site Lyon'},
      ];

      await storage.saveCachedSites(sites);
      final retrieved = await storage.getCachedSites();

      expect(retrieved.length, equals(2));
      expect(retrieved[0]['id'], equals('site-A'));
      expect(retrieved[1]['name'], equals('Site Lyon'));
    });

    test('Floor ID and Workspace ID/Name persistence round-trip', () async {
      await storage.saveFloorId('floor-42');
      await storage.saveWorkspaceId('desk-777');
      await storage.saveWorkspaceName('Bureau Fenêtre 777');

      expect(await storage.getFloorId(), equals('floor-42'));
      expect(await storage.getWorkspaceId(), equals('desk-777'));
      expect(await storage.getWorkspaceName(), equals('Bureau Fenêtre 777'));
    });
  });

  group('TeamMapScreen - Offline & Floor Selection Cache', () {
    testWidgets('Offline startup loads floor and plan from cache without crash or blocking error', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const siteId = 'site-offline-01';
      const floorId = 'floor-offline-01';
      const dateStr = '2026-11-20';

      final samplePlan = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-1', 'name': 'Desk Alpha'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [40.0, 0.0], [40.0, 40.0], [0.0, 40.0], [0.0, 0.0]]
              ]
            }
          }
        ]
      };

      final sampleWorkspaces = [
        {'id': 'ws-1', 'name': 'Desk Alpha', 'isBookable': true}
      ];

      final sampleFloors = [
        {'id': 'floor-offline-01', 'name': 'Rez-de-chaussée'},
        {'id': 'floor-offline-02', 'name': '1er Étage'},
      ];

      // Pre-seed storage
      SharedPreferences.setMockInitialValues({
        'site_id': siteId,
        'floor_id': floorId,
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': true,
      });

      await storage.saveCachedSites([{'id': siteId, 'name': 'Bâtiment Principal'}]);
      await storage.saveCachedFloors(siteId, sampleFloors);
      await storage.saveFloorPlanData(floorId, samplePlan);
      await storage.saveFloorWorkspaces(floorId, sampleWorkspaces);
      await storage.saveFloorOccupants(floorId, dateStr, {
        'ws-1': const DeskOccupant(
          workspaceId: 'ws-1',
          occupantName: 'Jean Dupont',
          isMe: true,
          isDelegated: false,
        ),
      });

      // Network throws SocketException immediately
      final client = MockClient((req) async {
        throw const SocketException('No route to host: api.my.roomz.io');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            initialDate: DateTime.parse(dateStr),
            initialSiteId: siteId,
            initialFloorId: floorId,
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no blocking error message
      expect(find.text('Erreur de chargement du plan.'), findsNothing);
      expect(find.text('Aucun étage ou bâtiment configuré.'), findsNothing);

      // Verify WorkspaceMapViewer is rendered with cached floor data
      expect(find.byType(WorkspaceMapViewer), findsOneWidget);

      // Verify Dropdown shows the floor or floor name
      expect(find.text('Rez-de-chaussée'), findsWidgets);
    });

    testWidgets('Changing floor in TeamMapScreen updates and saves floor_id into cache', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const siteId = 'site-multi-floor';
      const floor1 = 'floor-01';
      const floor2 = 'floor-02';
      const dateStr = '2026-11-20';

      final samplePlanF2 = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-f2', 'name': 'Desk Floor 2'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]
              ]
            }
          }
        ]
      };

      final sampleFloors = [
        {'id': floor1, 'name': 'Étage 1'},
        {'id': floor2, 'name': 'Étage 2'},
      ];

      SharedPreferences.setMockInitialValues({
        'site_id': siteId,
        'floor_id': floor1,
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': true,
      });

      await storage.saveCachedFloors(siteId, sampleFloors);
      await storage.saveFloorPlanData(floor1, {'type': 'FeatureCollection', 'features': []});
      await storage.saveFloorWorkspaces(floor1, []);
      await storage.saveFloorPlanData(floor2, samplePlanF2);
      await storage.saveFloorWorkspaces(floor2, [{'id': 'ws-f2', 'name': 'Desk Floor 2', 'isBookable': true}]);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'access', 'refresh_token': 'refresh'}), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode(sampleFloors), 200);
        }
        // Network drops for floor 2 fetch, falling back to cache
        throw const SocketException('Network offline');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            initialDate: DateTime.parse(dateStr),
            initialSiteId: siteId,
            initialFloorId: floor1,
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial floor should be floor1
      expect(await storage.getFloorId(), equals(floor1));

      // Open floor dropdown and tap Étage 2
      final dropdown = find.byType(DropdownButton<String>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final itemFloor2 = find.text('Étage 2').last;
      await tester.tap(itemFloor2);
      await tester.pumpAndSettle();

      // Verify storage floor_id has been updated to floor2!
      final updatedFloorId = await storage.getFloorId();
      expect(updatedFloorId, equals(floor2), reason: 'Floor change in TeamMapScreen must be persisted');
    });
  });

  group('SetupScreen - Offline Resilience & Selection Cache', () {
    testWidgets('SetupScreen restores cached site, floor, and desk when network is completely offline', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const siteId = 'site-setup-offline';
      const floorId = 'floor-setup-offline';
      const workspaceId = 'ws-desk-101';
      const workspaceName = 'Bureau 101';

      final samplePlan = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': workspaceId, 'name': workspaceName},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]
              ]
            }
          }
        ]
      };

      final sampleWorkspaces = [
        {
          'id': workspaceId,
          'name': workspaceName,
          'isReservable': true,
          'isBookable': true,
          'bookable': true,
        }
      ];

      // Pre-seed storage with user configuration and cache
      SharedPreferences.setMockInitialValues({
        'site_id': siteId,
        'floor_id': floorId,
        'workspace_id': workspaceId,
        'workspace_name': workspaceName,
      });

      await storage.saveCachedSites([{'id': siteId, 'name': 'Campus Tech'}]);
      await storage.saveCachedFloors(siteId, [{'id': floorId, 'name': '3ème Étage'}]);
      await storage.saveFloorPlanData(floorId, samplePlan);
      await storage.saveFloorWorkspaces(floorId, sampleWorkspaces);

      // Network is offline
      final client = MockClient((req) async {
        throw const SocketException('No Internet access');
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: SetupScreen(
            accessToken: 'dummy-offline-token',
            storageService: storage,
            apiService: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify no crash or blocking network error
      expect(find.text('Campus Tech'), findsWidgets);
      expect(find.text('3ème Étage'), findsWidgets);
      expect(find.text(workspaceName), findsWidgets);
    });

    testWidgets('Confirming workspace in SetupScreen persists floor_id and workspace in cache', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const siteId = 'site-new';
      const floorId = 'floor-new-02';
      const workspaceId = 'ws-confirmed-42';
      const workspaceName = 'Salle B - Desk 42';

      final sampleSites = [{'id': siteId, 'name': 'Centre R&D'}];
      final sampleFloors = [{'id': floorId, 'name': 'Étage R&D 2'}];
      final sampleWorkspaces = [
        {
          'id': workspaceId,
          'name': workspaceName,
          'isReservable': true,
          'isBookable': true,
          'bookable': true,
        }
      ];

      final samplePlan = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': workspaceId, 'name': workspaceName},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [30.0, 0.0], [30.0, 30.0], [0.0, 30.0], [0.0, 0.0]]
              ]
            }
          }
        ]
      };

      final client = MockClient((req) async {
        if (req.url.path.endsWith('/buildings')) {
          return http.Response(jsonEncode(sampleSites), 200);
        }
        if (req.url.path.endsWith('/floors')) {
          return http.Response(jsonEncode(sampleFloors), 200);
        }
        if (req.url.path.contains('/workspaces/all')) {
          return http.Response(jsonEncode(sampleWorkspaces), 200);
        }
        if (req.url.path.endsWith('/data')) {
          return http.Response(jsonEncode(samplePlan), 200);
        }
        return http.Response('{}', 200);
      });

      final api = RoomzApiService(storage: storage, client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SetupScreen(
                        accessToken: 'token-valid',
                        storageService: storage,
                        apiService: api,
                      ),
                    ),
                  );
                },
                child: const Text('Open Setup'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Setup'));
      await tester.pumpAndSettle();

      // Select site
      final siteFinder = find.text('Centre R&D').last;
      await tester.tap(siteFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Select floor
      final floorFinder = find.text('Étage R&D 2').last;
      await tester.tap(floorFinder, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Verify floor_id was saved immediately on selection
      expect(await storage.getFloorId(), equals(floorId));

      // Select desk on 2D map via WorkspaceMapViewer
      final viewerFinder = find.byType(WorkspaceMapViewer);
      expect(viewerFinder, findsOneWidget);
      final viewerState = tester.state<WorkspaceMapViewerState>(viewerFinder);
      viewerState.widget.onSelected(sampleWorkspaces.first);
      await tester.pumpAndSettle();

      // Verify persisted floor, workspace, and site
      expect(await storage.getSiteId(), equals(siteId));
      expect(await storage.getFloorId(), equals(floorId));
      expect(await storage.getWorkspaceId(), equals(workspaceId));
      expect(await storage.getWorkspaceName(), equals(workspaceName));
    });
  });
}
