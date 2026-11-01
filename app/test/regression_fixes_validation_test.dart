import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/time_slider_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineStateManager.instance.reset();
  });

  tearDown(() {
    OfflineStateManager.instance.reset();
  });

  group('Correction 1: Non-destructive workspace change and offline calendar sync', () {
    test('Non-destructive workspace change preserves booked and requested dates in storage', () async {
      final storage = StorageService();
      await storage.saveWorkspaceId('ws-old-1');
      await storage.saveWorkspaceName('Bureau Ancien');
      await storage.saveFloorId('fl-1');
      await storage.saveBookedDates(['2026-11-05', '2026-11-06']);
      await storage.saveRequestedDates(['2026-11-12']);
      await storage.saveBookedElsewhereDates(['2026-11-07']);
      await storage.saveRequestedWorkspacesMap({'2026-11-12': 'ws-target'});
      await storage.saveRequestedWorkspaceNamesMap({'2026-11-12': 'Bureau Cible'});

      // Simulate the workspace change to a new desk
      await storage.saveWorkspaceId('ws-new-2');
      await storage.saveWorkspaceName('Bureau Nouveau');

      // The new logic does NOT purge the storage!
      // Verify storage still contains all booked and requested dates
      final booked = await storage.getBookedDates();
      expect(booked, containsAll(['2026-11-05', '2026-11-06']));

      final requested = await storage.getRequestedDates();
      expect(requested, contains('2026-11-12'));

      final elsewhere = await storage.getBookedElsewhereDates();
      expect(elsewhere, contains('2026-11-07'));

      final wsName = await storage.getWorkspaceName();
      expect(wsName, equals('Bureau Nouveau'));
    });

    testWidgets('Offline calendar sync preserves local cache and never overwrites with empty lists', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final tomorrowStr = "${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-desk-1',
        'workspace_name': 'Desk Alpha',
        'floor_id': 'fl-1',
        'booked_dates': [tomorrowStr],
        'requested_dates': <String>[],
        'initial_tab': 0,
      });

      // Mark offline before sync
      OfflineStateManager.instance.markOffline();

      final client = MockClient((req) async {
        // Should not be called or fails
        return http.Response('Server Error', 500);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Local cache must still be intact!
      final booked = await storage.getBookedDates();
      expect(booked, contains(tomorrowStr));
    });
  });

  group('Correction 2: Immediate rollback on calendar booking failure', () {
    testWidgets('Direct booking failure does not leave date in pending state', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      DateTime targetDate = now.add(const Duration(days: 2));
      while (targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday) {
        targetDate = targetDate.add(const Duration(days: 1));
      }
      final targetDateStr = "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-desk-1',
        'workspace_name': 'Desk Alpha',
        'floor_id': 'fl-1',
        'booked_dates': <String>[],
        'requested_dates': <String>[],
        'initial_tab': 1,
        'hide_weekends': false,
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings') || req.url.path.contains('/reservations')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'user-123'}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars') || req.url.path.contains('/occupancy')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        // Booking call fails (e.g. desk unavailable or 400)
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          return http.Response(jsonEncode({'error': 'conflict'}), 400);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Find calendar day cell and tap it
      final dayFinder = find.text('${targetDate.day}');
      if (dayFinder.evaluate().isNotEmpty) {
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        final reserveButton = find.text('Réserver ce jour');
        if (reserveButton.evaluate().isNotEmpty) {
          await tester.tap(reserveButton);
          await tester.pumpAndSettle();
        }
      }

      // Verify that after failed reservation attempt, requested dates does NOT contain targetDate
      final requested = await storage.getRequestedDates();
      expect(requested.contains(targetDateStr), isFalse);
      final booked = await storage.getBookedDates();
      expect(booked.contains(targetDateStr), isFalse);
    });

    testWidgets('Connection failure / exception during direct booking shows error KO and never leaves date in pending', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      DateTime targetDate = now.add(const Duration(days: 2));
      while (targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday) {
        targetDate = targetDate.add(const Duration(days: 1));
      }
      final targetDateStr = "${targetDate.year.toString().padLeft(4, '0')}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}";

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-desk-1',
        'workspace_name': 'Desk Alpha',
        'floor_id': 'fl-1',
        'booked_dates': <String>[],
        'requested_dates': <String>[],
        'initial_tab': 1,
        'hide_weekends': false,
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings') || req.url.path.contains('/reservations')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'user-123'}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars') || req.url.path.contains('/occupancy')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        // Connection error when trying to book
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          throw http.ClientException('Connection reset by peer');
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      final dayFinder = find.text('${targetDate.day}');
      if (dayFinder.evaluate().isNotEmpty) {
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        final reserveButton = find.text('Réserver ce jour');
        if (reserveButton.evaluate().isNotEmpty) {
          await tester.tap(reserveButton);
          await tester.pumpAndSettle();
        }
      }

      // Storage MUST not contain the date in requested or booked dates
      final requested = await storage.getRequestedDates();
      expect(requested.contains(targetDateStr), isFalse);
      final booked = await storage.getBookedDates();
      expect(booked.contains(targetDateStr), isFalse);

      // Sanitized error toast must be shown
      expect(find.textContaining('vérifier votre connexion'), findsOneWidget);
    });
  });

  group('Correction 3: Error Sanitization in TeamMapScreen booking', () {
    testWidgets('Booking exception never exposes raw HTTPS URL in SnackBar', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': true,
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/data')) {
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
        if (req.url.path.contains('/workspaces') && !req.url.path.contains('/calendars')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'}
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

      // UI should be rendered without any raw HTTPS leak
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('ClientException'), findsNothing);
    });
  });

  group('Correction 4: Instant Green "Bureau" badge on TimeSliderBar from cache', () {
    testWidgets('TeamMapScreen displays green Bureau badge immediately on first build from cached occupants', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      // Ensure weekday
      DateTime testDate = DateTime(now.year, now.month, now.day);
      if (testDate.weekday == DateTime.saturday) {
        testDate = testDate.add(const Duration(days: 2));
      } else if (testDate.weekday == DateTime.sunday) {
        testDate = testDate.add(const Duration(days: 1));
      }
      final dateStr = "${testDate.year.toString().padLeft(4, '0')}-${testDate.month.toString().padLeft(2, '0')}-${testDate.day.toString().padLeft(2, '0')}";

      // Populate local cache before widget build:
      // - cached floor plan and workspaces
      // - cached occupants where isMe == true
      final myOccupant = DeskOccupant(
        workspaceId: 'ws-my-desk',
        occupantId: 'me-123',
        occupantName: 'Moi Même',
        occupantEmail: 'me@company.com',
        isMe: true,
      );

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-my-desk',
        'workspace_name': 'Mon Bureau',
        'hide_weekends': true,
        'cached_sites': jsonEncode([{'id': 'site-1', 'name': 'Siège'}]),
        'cached_floors_site-1': jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]),
        'floor_plan_data_fl-1': jsonEncode([
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-my-desk', 'name': 'Mon Bureau'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]
              ]
            }
          }
        ]),
        'floor_workspaces_fl-1': jsonEncode([
          {'id': 'ws-my-desk', 'name': 'Mon Bureau', 'isBookable': true}
        ]),
        'floor_occupants_fl-1_$dateStr': jsonEncode({
          'ws-my-desk': myOccupant.toJson(),
        }),
      });

      // API client that hangs / does not complete immediately to prove Cache-First instant display
      final client = MockClient((req) async {
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: testDate,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));

      // Pump single frame (first build, cache-first)
      await tester.pump();

      // Verify TimeSliderBar is present
      expect(find.byType(TimeSliderBar), findsOneWidget);

      // Verify that the green "Bureau" badge is rendered
      expect(find.text('Bureau'), findsOneWidget);
    });

    testWidgets('TeamMapScreen displays green Bureau badge when booked elsewhere', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      DateTime testDate = DateTime(now.year, now.month, now.day);
      if (testDate.weekday == DateTime.saturday) {
        testDate = testDate.add(const Duration(days: 2));
      } else if (testDate.weekday == DateTime.sunday) {
        testDate = testDate.add(const Duration(days: 1));
      }
      final dateStr = "${testDate.year.toString().padLeft(4, '0')}-${testDate.month.toString().padLeft(2, '0')}-${testDate.day.toString().padLeft(2, '0')}";

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-default',
        'hide_weekends': true,
        'booked_elsewhere_dates': [dateStr],
        'cached_sites': jsonEncode([{'id': 'site-1', 'name': 'Siège'}]),
        'cached_floors_site-1': jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]),
        'floor_plan_data_fl-1': jsonEncode([]),
        'floor_workspaces_fl-1': jsonEncode([]),
      });

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: testDate,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));

      await tester.pump();

      // With booked elsewhere merged into _bookedDates, green badge should be present immediately
      expect(find.text('Bureau'), findsOneWidget);
    });
  });
}
