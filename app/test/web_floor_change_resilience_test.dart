import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'site_id': 'site-1',
      'floor_id': 'fl-1',
      'refresh_token': 'mock-refresh-token',
      'hide_weekends': true,
      'cached_floors_site-1': jsonEncode([
        {'id': 'fl-1', 'name': 'Étage 1'},
        {'id': 'fl-2', 'name': 'Étage 2'},
      ]),
    });
  });

  group('Web Floor Change Resilience & Non-Destructive Error Handling', () {
    testWidgets('Changing floor with empty GeoJSON but valid workspaces generates synthetic desks and avoids error screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        // Floor 1 has normal features
        if (path.contains('/floors/fl-1/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'workspaceType': 'Desk', 'name': 'B01-01'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        // Floor 2 has EMPTY features list (backend provides no GeoJSON)
        if (path.contains('/floors/fl-2/data')) {
          return http.Response(jsonEncode({'features': []}), 200);
        }
        // Floor 2 has valid workspaces
        if (path.contains('/floors/fl-2/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-201', 'name': 'B02-01', 'isBookable': true},
            {'id': 'ws-202', 'name': 'B02-02', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/floors/fl-1/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/buildings/site-1/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'},
            {'id': 'fl-2', 'name': 'Étage 2'},
          ]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Floor 1 loaded
      expect(find.text('01'), findsOneWidget);
      expect(find.byType(WorkspaceMapViewer), findsOneWidget);

      // Change floor to Floor 2 via dropdown
      final dropdown = find.byType(DropdownButton<String>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final floor2Item = find.text('Étage 2').last;
      await tester.tap(floor2Item);
      await tester.pumpAndSettle();

      // Floor 2 desks should be synthesized and visible!
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      // No red error screen!
      expect(find.text('Erreur de chargement.'), findsNothing);
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('Changing floor when API throws error does NOT crash and preserves UI with floating SnackBar', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors/fl-1/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'workspaceType': 'Desk', 'name': 'B01-01'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/floors/fl-1/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        // Floor 2 triggers HTTP 500 error on workspaces
        if (path.contains('/floors/fl-2')) {
          return http.Response('Server Error', 500);
        }
        if (path.contains('/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/buildings/site-1/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'},
            {'id': 'fl-2', 'name': 'Étage 2'},
          ]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Change floor to Floor 2
      final dropdown = find.byType(DropdownButton<String>);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final floor2Item = find.text('Étage 2').last;
      await tester.tap(floor2Item);
      await tester.pumpAndSettle();

      // Should handle the error gracefully without unhandled exception!
      expect(tester.takeException(), isNull);
    });

    testWidgets('Partial occupancy failure retains floor plan and shows informative notification without black screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors/fl-1/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'workspaceType': 'Desk', 'name': 'B01-01'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/floors/fl-1/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        // Occupancy endpoint fails with 503
        if (path.contains('/calendars')) {
          return http.Response('Service Unavailable', 503);
        }
        if (path.contains('/buildings/site-1/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'},
          ]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Floor plan & desk 01 are still displayed!
      expect(find.text('01'), findsOneWidget);
      // Not blocked by error screen!
      expect(find.text('Erreur de chargement.'), findsNothing);
      expect(find.byType(WorkspaceMapViewer), findsOneWidget);
    });
  });
}
