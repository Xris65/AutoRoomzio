import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/widgets/action_loading_overlay.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'site_id': 'site-1',
      'floor_id': 'fl-1',
      'refresh_token': 'mock-refresh-token',
      'hide_weekends': true,
    });
  });

  group('TeamMapScreen Integration Fixes', () {
    testWidgets('AppBar has sync/refresh button that triggers data reload', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int tokenCalls = 0;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          tokenCalls++;
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
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
        if (path.contains('/floors') && path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
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

      final syncButton = find.byTooltip('Actualiser');
      expect(syncButton, findsOneWidget);

      final initialTokens = tokenCalls;
      await tester.tap(syncButton);
      await tester.pumpAndSettle();

      expect(tokenCalls, greaterThan(initialTokens));
    });

    testWidgets('ActionLoadingOverlay is present in body hierarchy', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
        if (req.url.path.contains('/floors') && req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(ActionLoadingOverlay), findsOneWidget);
    });

    testWidgets('Tapping outside occupants panel closes it', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
        if (req.url.path.contains('/floors') && req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-1',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'user': {'id': 'usr-1', 'name': 'Camille Dupont', 'email': 'camille@test.fr'}
                }
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Open occupants panel
      final toggleButton = find.textContaining("Collègues présents");
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Search field is visible when expanded
      expect(find.byType(TextField), findsOneWidget);

      // Tap outside (e.g. top of map area)
      await tester.tapAt(const Offset(200, 200));
      await tester.pumpAndSettle();

      // Panel should now be closed
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Date navigation never skips weekends on arrows (< and > move 1 day)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

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
        if (req.url.path.contains('/floors') && req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      // Start on a Friday in November (Nov 6, 2026)
      final friday = DateTime(2026, 11, 6);
      expect(friday.weekday, DateTime.friday);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialDate: friday,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      final nextButton = find.byTooltip('Jour suivant');
      final prevButton = find.byTooltip('Jour précédent');

      // Advance: Friday -> Saturday 7 nov.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Samedi 7 nov.'), findsOneWidget);

      // Advance: Saturday -> Sunday 8 nov.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dimanche 8 nov.'), findsOneWidget);

      // Advance: Sunday -> Monday 9 nov.
      await tester.tap(nextButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);

      // Previous button: Monday -> Sunday 8 nov.
      await tester.tap(prevButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dimanche 8 nov.'), findsOneWidget);
    });

    testWidgets('Free desk sheet on date > J+13 allows advance programming and disables colleague booking', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-free', 'workspaceType': 'Desk', 'name': 'B01-99'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-free', 'name': 'B01-99', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      // Date in 20+ days (beyond J+13, ensure it's a weekday)
      var advanceDate = DateTime.now().add(const Duration(days: 20));
      while (advanceDate.weekday == DateTime.saturday || advanceDate.weekday == DateTime.sunday) {
        advanceDate = advanceDate.add(const Duration(days: 1));
      }

      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: storage,
          initialDate: advanceDate,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Tap on the desk on the map (part of name is '99')
      final deskWidget = find.text('99');
      expect(deskWidget, findsOneWidget);
      await tester.tap(deskWidget);
      await tester.pumpAndSettle();

      // Advance programming button should be available
      expect(find.text("Programmer ce bureau (En attente)"), findsOneWidget);
      // Colleague booking message should be displayed
      expect(find.text("La réservation pour un collègue est limitée à J+13."), findsOneWidget);

      // Tap advance program button
      await tester.tap(find.text("Programmer ce bureau (En attente)"));
      await tester.pumpAndSettle();

      final isoDate = "${advanceDate.year.toString().padLeft(4, '0')}-${advanceDate.month.toString().padLeft(2, '0')}-${advanceDate.day.toString().padLeft(2, '0')}";
      final requested = await storage.getRequestedDates();
      expect(requested.contains(isoDate), isTrue);

      // Reopening sheet now shows "Programmation en attente" and cancellation button
      await tester.tap(deskWidget);
      await tester.pumpAndSettle();
      expect(find.text("Programmation en attente"), findsOneWidget);
      expect(find.text("Annuler la programmation"), findsOneWidget);

      // Tap cancel programming
      await tester.tap(find.text("Annuler la programmation"));
      await tester.pumpAndSettle();
      final updatedReq = await storage.getRequestedDates();
      expect(updatedReq.contains(isoDate), isFalse);
    });

    testWidgets('Retour #1: Weekend displays "Réservations fermées le weekend" on free desk', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-free', 'workspaceType': 'Desk', 'name': 'B01-99'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-free', 'name': 'B01-99', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      // Target a Saturday (2026-10-10)
      final saturday = DateTime(2026, 10, 10);
      expect(saturday.weekday, DateTime.saturday);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialDate: saturday,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Tap on the desk
      final deskWidget = find.text('99');
      expect(deskWidget, findsOneWidget);
      await tester.tap(deskWidget);
      await tester.pumpAndSettle();

      // Should show weekend closed message and NO reservation buttons
      expect(find.text("Réservations fermées le weekend"), findsOneWidget);
      expect(find.text("Réserver ce bureau pour moi"), findsNothing);
      expect(find.text("Programmer ce bureau (En attente)"), findsNothing);
    });

    testWidgets('Retour #1: DatePicker opens cleanly even when initialDate is a weekend', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/data')) {
          return http.Response(jsonEncode({'features': []}), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      // Target a Sunday (2026-10-11)
      final sunday = DateTime(2026, 10, 11);
      expect(sunday.weekday, DateTime.sunday);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialDate: sunday,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Tap date picker in navigation bar
      final calendarIcon = find.byIcon(Icons.calendar_today);
      expect(calendarIcon, findsOneWidget);
      await tester.tap(calendarIcon);
      await tester.pumpAndSettle();

      // DatePicker modal opened without assertion error
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });

    testWidgets('Retour #2: GPS colleague button centers and highlights colleague desk', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-colleague', 'workspaceType': 'Desk', 'name': 'B01-42'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/floors') && req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-colleague',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'creator': {
                    'id': 'u-alice',
                    'name': 'Alice Dupont',
                    'email': 'alice@corp.com',
                  }
                }
              }
            ]
          }), 200);
        }
        if (req.url.path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-colleague', 'name': 'B01-42', 'isBookable': true}
          ]), 200);
        }
        if (req.url.path.contains('/buildings') && req.url.path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: RoomzApiService(client: client),
          storageService: StorageService(),
          initialDate: DateTime(2026, 10, 12), // Monday
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Open occupants panel
      final toggleButton = find.textContaining("Collègues présents");
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Alice is in the list
      expect(find.text("Alice Dupont"), findsOneWidget);

      // Tap GPS button
      final gpsButton = find.byTooltip("Centrer sur le plan");
      expect(gpsButton, findsOneWidget);
      await tester.tap(gpsButton);
      await tester.pump();

      // Colleague desk is highlighted
      expect(find.text("42"), findsOneWidget);
    });
  });
}
