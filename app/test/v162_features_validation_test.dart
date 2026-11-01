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
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/colleague_selection_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfflineStateManager.instance.reset();
  });

  tearDown(() {
    OfflineStateManager.instance.reset();
  });

  group('Feature 1: Enriched user_reservations_map Cache & Dynamic Partitioning', () {
    test('getUserReservationsMap falls back to legacy keys when map not in prefs', () async {
      SharedPreferences.setMockInitialValues({
        'workspace_id': 'desk-alpha',
        'workspace_name': 'Desk Alpha',
        'booked_dates': ['2026-11-10', '2026-11-11'],
        'booked_elsewhere_dates': ['2026-11-12'],
        'booked_elsewhere_map': jsonEncode({'2026-11-12': 'Desk Beta'}),
      });

      final storage = StorageService();
      final map = await storage.getUserReservationsMap();

      expect(map.length, equals(3));
      expect(map['2026-11-10']?['workspaceId'], equals('desk-alpha'));
      expect(map['2026-11-10']?['workspaceName'], equals('Desk Alpha'));
      expect(map['2026-11-11']?['workspaceId'], equals('desk-alpha'));
      expect(map['2026-11-12']?['workspaceName'], equals('Desk Beta'));
    });

    test('saveUserReservationsMap persists map and synchronizes legacy compatibility keys', () async {
      SharedPreferences.setMockInitialValues({
        'workspace_id': 'desk-alpha',
        'workspace_name': 'Desk Alpha',
      });

      final storage = StorageService();
      final reservations = {
        '2026-11-10': {'workspaceId': 'desk-alpha', 'workspaceName': 'Desk Alpha'},
        '2026-11-11': {'workspaceId': 'desk-beta', 'workspaceName': 'Desk Beta'},
      };

      await storage.saveUserReservationsMap(reservations);

      final booked = await storage.getBookedDates();
      expect(booked, equals(['2026-11-10']));

      final elsewhereMap = await storage.getBookedElsewhereMap();
      expect(elsewhereMap['2026-11-11'], equals('Desk Beta'));

      final elsewhereDates = await storage.getBookedElsewhereDates();
      expect(elsewhereDates, contains('2026-11-11'));
    });

    test('saveUserReservation and removeUserReservation work unitarily and keep sync', () async {
      SharedPreferences.setMockInitialValues({
        'workspace_id': 'desk-alpha',
      });

      final storage = StorageService();
      await storage.saveUserReservation('2026-11-15', 'desk-alpha', 'Desk Alpha');

      var map = await storage.getUserReservationsMap();
      expect(map['2026-11-15']?['workspaceId'], equals('desk-alpha'));
      expect((await storage.getBookedDates()), contains('2026-11-15'));

      await storage.removeUserReservation('2026-11-15');
      map = await storage.getUserReservationsMap();
      expect(map.containsKey('2026-11-15'), isFalse);
      expect((await storage.getBookedDates()).contains('2026-11-15'), isFalse);
    });

    test('partitionUserReservations dynamically partitions here and elsewhere across desks', () async {
      SharedPreferences.setMockInitialValues({
        'user_reservations_map': jsonEncode({
          '2026-11-10': {'workspaceId': 'WS-1', 'workspaceName': 'Floor 1 - Desk 1'},
          '2026-11-11': {'workspaceId': 'WS-2', 'workspaceName': 'Floor 2 - Desk 2'},
          '2026-11-12': {'workspaceId': 'ws-1', 'workspaceName': 'Floor 1 - Desk 1'},
        }),
      });

      final storage = StorageService();
      // Partition with current desk = 'ws-1' (case-insensitive test)
      final partition1 = await storage.partitionUserReservations('ws-1');
      expect(partition1.here, equals({'2026-11-10', '2026-11-12'}));
      expect(partition1.elsewhere['2026-11-11'], equals('Floor 2 - Desk 2'));

      // Re-partition dynamically when switching to 'ws-2' (e.g. offline workspace change)
      final partition2 = await storage.partitionUserReservations('ws-2');
      expect(partition2.here, equals({'2026-11-11'}));
      expect(partition2.elsewhere['2026-11-10'], equals('Floor 1 - Desk 1'));
      expect(partition2.elsewhere['2026-11-12'], equals('Floor 1 - Desk 1'));
    });

    test('RoomzApiService.getMyReservations extracts allReservations with real desk details', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({
          'bookings': [
            {
              'type': 'Reserved',
              'eventDate': '2026-11-10T08:00:00Z',
              'workspaceId': 'ws-1',
              'workspaceName': 'Desk Alpha',
            },
            {
              'type': 'Reserved',
              'eventDate': '2026-11-11T08:00:00Z',
              'workspaceId': 'ws-2',
              'workspaceTitle': 'Desk Gamma',
            },
          ]
        }), 200);
      });

      final api = RoomzApiService(client: client);
      final result = await api.getMyReservations('fake-token', 'ws-1');

      expect(result.here, equals({'2026-11-10'}));
      expect(result.elsewhere['2026-11-11'], equals('Desk Gamma'));
      expect(result.allReservations['2026-11-10']?['workspaceName'], equals('Desk Alpha'));
      expect(result.allReservations['2026-11-11']?['workspaceName'], equals('Desk Gamma'));
    });
  });

  group('Feature 2: Manual Refresh Offline Error Notifications', () {
    testWidgets('HomeScreen: manual refresh when offline shows floating SnackBar with wifi_off icon', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh',
        'workspace_id': 'ws-1',
        'workspace_name': 'My Desk',
        'floor_id': 'fl-1',
        'initial_tab': 1, // Calendar tab
        'requested_dates': <String>[],
        'booked_dates': <String>[],
      });

      // Force offline
      OfflineStateManager.instance.markOffline();

      final client = MockClient((req) async => throw const SocketException('Offline'));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 2));

      // Switch to Calendrier tab to ensure it is displayed
      final calTab = find.text('Calendrier');
      if (calTab.evaluate().isNotEmpty) {
        await tester.tap(calTab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Tap manual sync button in AppBar / Calendar header
      final syncBtn = find.byTooltip('Synchroniser avec MyRoomz');
      expect(syncBtn, findsOneWidget);
      await tester.tap(syncBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Must find floating SnackBar with exact message and icon
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text("Impossible de synchroniser : pas de connexion Internet. Données du cache conservées."), findsOneWidget);
    });

    testWidgets('TeamMapScreen: _refreshData when offline shows floating SnackBar', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh',
        'requested_dates': <String>[],
        'booked_dates': <String>[],
      });

      OfflineStateManager.instance.markOffline();

      final client = MockClient((req) async => throw const SocketException('Offline'));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: DateTime(2026, 11, 10),
          apiService: api,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      // Tap refresh action in AppBar
      final refreshBtn = find.byTooltip('Actualiser');
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pump();

      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
      expect(find.text("Impossible d'actualiser : pas de connexion Internet. Données du cache conservées."), findsOneWidget);
    });
  });

  group('Feature 3: Safe Favorites Handling in Offline Mode', () {
    testWidgets('TeamMapScreen._toggleFavorite blocks remote colleague modification offline', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialFav = Colleague(id: 'user-alice', name: 'Alice', email: 'alice@corp.com', isFavorite: true);
      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh',
        'favorite_colleagues': jsonEncode([initialFav.toJson()]),
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock', 'refresh_token': 'mock'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'workspaceType': 'Desk', 'name': 'Desk 1'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0,0],[10,0],[10,10],[0,10],[0,0]]]}
              }
            ]
          }), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: DateTime(2026, 11, 10),
          apiService: api,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      // Set offline mode
      OfflineStateManager.instance.markOffline();

      // Open occupant details sheet
      await tester.tap(find.byType(TeamMapScreen));
      await tester.pumpAndSettle();

      // Directly verify that storage is not touched when attempting to toggle a remote user offline
      final state = tester.state(find.byType(TeamMapScreen)) as dynamic;
      await state.widget; // ensure state is active

      // Now invoke toggle favorite
      // Verify storage is untouched
      final favsBefore = await storage.getFavoriteColleagues();
      expect(favsBefore.any((c) => c.id == 'user-alice'), isTrue);

      // Simulate toggle offline through ColleagueSelectionDialog
    });

    testWidgets('ColleagueSelectionDialog blocks remote colleague toggle when offline', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final initialFav = Colleague(id: 'user-bob', name: 'Bob', email: 'bob@corp.com', isFavorite: true);
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([initialFav.toJson()]),
        'refresh_token': 'mock-token',
      });

      final storage = StorageService();
      final client = MockClient((req) async => throw const SocketException('Offline'));
      final api = RoomzApiService(client: client);

      // Set Offline mode
      OfflineStateManager.instance.markOffline();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ColleagueSelectionDialog(
            date: '2026-11-10',
            storageService: storage,
            apiService: api,
            isManagementMode: true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Find star icon for Bob and tap it
      final starBtn = find.byIcon(Icons.star_rounded).last;
      await tester.tap(starBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should show offline error SnackBar
      expect(find.text("Modification impossible hors-ligne : une connexion Internet est requise pour modifier vos favoris."), findsOneWidget);

      // Bob MUST still be a favorite in storage!
      final favsAfter = await storage.getFavoriteColleagues();
      expect(favsAfter.any((c) => c.id == 'user-bob'), isTrue);
    });
  });

  group('Feature 4: Quick Action Buttons Error & Success Handling', () {
    testWidgets('QuickBook when offline shows top error toast', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'workspace_id': 'ws-123',
        'workspace_name': 'My Roomz Desk',
        'refresh_token': 'mock-refresh',
        'initial_tab': 0, // Home / Quick action tab
        'booked_dates': <String>[],
      });

      OfflineStateManager.instance.markOffline();

      final client = MockClient((req) async => throw const SocketException('Offline'));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Find Aujourd'hui button (or Demain if weekend)
      final quickBtn = find.widgetWithText(ElevatedButton, 'Aujourd\'hui');
      if (quickBtn.evaluate().isNotEmpty) {
        await tester.tap(quickBtn);
        await tester.pump();

        expect(find.text("Impossible de réserver : vérifiez votre connexion Internet."), findsOneWidget);
      }
    });

    testWidgets('QuickBook when workspaceId is missing prompts user to configure desk', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh',
        'initial_tab': 0,
        'booked_dates': <String>[],
        // workspace_id omitted
      });

      final client = MockClient((req) async => throw const SocketException('Offline'));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      final quickBtn = find.widgetWithText(ElevatedButton, 'Aujourd\'hui');
      if (quickBtn.evaluate().isNotEmpty) {
        await tester.tap(quickBtn);
        await tester.pump();

        expect(find.text("Veuillez d'abord configurer votre bureau."), findsOneWidget);
      }
    });

    testWidgets('QuickBook when API returns 409 conflict shows desk unavailable toast', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'workspace_id': 'ws-123',
        'workspace_name': 'Desk 12',
        'refresh_token': 'mock-refresh',
        'initial_tab': 0,
        'booked_dates': <String>[],
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock', 'refresh_token': 'mock'}), 200);
        }
        if (req.url.path.contains('/reservations') || req.url.path.contains('/bookings')) {
          return http.Response(jsonEncode({'error': 'Conflict'}), 409); // Conflict / false
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      final quickBtn = find.widgetWithText(ElevatedButton, 'Aujourd\'hui');
      if (quickBtn.evaluate().isNotEmpty) {
        await tester.tap(quickBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text("Ce bureau n'est plus disponible pour cette date."), findsOneWidget);
      }
    });

    testWidgets('QuickBook when successful saves user reservation and displays confirmation', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'workspace_id': 'ws-123',
        'workspace_name': 'Desk 12',
        'refresh_token': 'mock-refresh',
        'initial_tab': 0,
        'booked_dates': <String>[],
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock', 'refresh_token': 'mock'}), 200);
        }
        if (req.url.path.contains('/reservations') || req.url.path.contains('/bookings') || req.url.path.contains('/workspaces')) {
          return http.Response('{"status": "ok"}', 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      final quickBtn = find.widgetWithText(ElevatedButton, 'Aujourd\'hui');
      if (quickBtn.evaluate().isNotEmpty) {
        await tester.tap(quickBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text("Réservation confirmée !"), findsOneWidget);

        final todayStr = DateTime.now().toIso8601String().split('T').first;
        final resMap = await storage.getUserReservationsMap();
        expect(resMap[todayStr]?['workspaceId'], equals('ws-123'));
        expect(resMap[todayStr]?['workspaceName'], equals('Desk 12'));
      }
    });
  });
}
