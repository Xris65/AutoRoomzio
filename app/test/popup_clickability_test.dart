import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/occupant_details_sheet.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'site_id': 'site-1',
      'floor_id': 'fl-1',
      'refresh_token': 'mock-refresh-token',
      'hide_weekends': false,
    });
  });

  group('Popup & Panel Clickability Tests', () {
    testWidgets('Expanded occupants panel buttons (GPS, details, search clear, close) are 100% clickable', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-101', 'workspaceType': 'Desk', 'name': 'B01-01'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              },
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-102', 'workspaceType': 'Desk', 'name': 'B01-02'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[60.0, 10.0], [100.0, 10.0], [100.0, 50.0], [60.0, 50.0], [60.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/floors') && path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-101',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'creator': {
                    'id': 'u-bob',
                    'name': 'Bob Martin',
                    'email': 'bob@company.com',
                  }
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-101', 'name': 'B01-01', 'isBookable': true},
            {'id': 'ws-102', 'name': 'B01-02', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: DateTime(2026, 10, 12),
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Expand occupants panel
      final toggleButton = find.byKey(const ValueKey('toggle_occupants_panel_right'));
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      // Verify Bob Martin appears
      expect(find.text('Bob Martin'), findsOneWidget);

      // 2. Click GPS button on colleague item: triggers centering WITHOUT closing panel or opening bottom sheet
      final gpsButton = find.byKey(const ValueKey('colleague_gps_ws-101'));
      expect(gpsButton, findsOneWidget);
      await tester.tap(gpsButton);
      await tester.pump();

      // Desk label 01 is highlighted on the map
      expect(find.text('01'), findsWidgets);

      // 3. Search field typing and clear button click
      final searchField = find.byKey(const ValueKey('colleague_search_field'));
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, 'Bob');
      await tester.pumpAndSettle();
      expect(find.text('Bob Martin'), findsOneWidget);

      final clearSearchBtn = find.byKey(const ValueKey('clear_colleague_search_button'));
      expect(clearSearchBtn, findsOneWidget);
      await tester.tap(clearSearchBtn);
      await tester.pumpAndSettle();

      // 4. Click colleague row: opens OccupantDetailsSheet
      final colleagueRow = find.byKey(const ValueKey('colleague_item_ws-101'));
      expect(colleagueRow, findsOneWidget);
      await tester.tap(colleagueRow);
      await tester.pumpAndSettle();

      // Verify OccupantDetailsSheet is open
      expect(find.byType(OccupantDetailsSheet), findsOneWidget);

      // Click close button on OccupantDetailsSheet
      final closeDetailsBtn = find.byKey(const ValueKey('close_occupant_details_button'));
      expect(closeDetailsBtn, findsOneWidget);
      await tester.tap(closeDetailsBtn);
      await tester.pumpAndSettle();

      // Details sheet is closed
      expect(find.byType(OccupantDetailsSheet), findsNothing);

      // 5. Expand panel again and test close button
      await tester.tap(toggleButton);
      await tester.pumpAndSettle();

      final closePanelBtn = find.byKey(const ValueKey('close_occupants_panel_button'));
      expect(closePanelBtn, findsOneWidget);
      await tester.tap(closePanelBtn);
      await tester.pumpAndSettle();

      // Panel is collapsed (Bob Martin no longer visible)
      expect(find.text('Bob Martin'), findsNothing);
    });

    testWidgets('Free desk popup bottom sheet buttons are 100% clickable', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool reserveCalled = false;
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
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
        if (path.contains('/floors') && path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-free', 'name': 'B01-99', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        if (req.method == 'POST' && path.contains('/bookings')) {
          reserveCalled = true;
          return http.Response(jsonEncode({'id': 'res-1'}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: DateTime.now(),
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      // Tap free desk B01-99 on map
      final deskFinder = find.text('99');
      expect(deskFinder, findsOneWidget);
      await tester.tap(deskFinder);
      await tester.pumpAndSettle();

      // Bottom sheet is open
      expect(find.byKey(const ValueKey('reserve_for_me_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('reserve_for_colleague_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('close_free_desk_sheet_button')), findsOneWidget);

      // Tap "Réserver ce bureau pour moi"
      await tester.tap(find.byKey(const ValueKey('reserve_for_me_button')));
      await tester.pumpAndSettle();

      expect(reserveCalled, isTrue);
    });

    testWidgets('OccupantDetailsSheet buttons trigger callbacks on first tap', (tester) async {
      bool cancelMyBookingTriggered = false;
      bool cancelDelegatedTriggered = false;
      bool toggleFavTriggered = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                OccupantDetailsSheet.show(
                  context: ctx,
                  workspace: {'name': 'B01-15', 'roomName': 'OpenSpace'},
                  occupant: const DeskOccupant(
                    workspaceId: 'ws-15',
                    occupantName: 'John Doe',
                    isMe: false,
                    isDelegatedByMe: true,
                    isDelegated: true,
                  ),
                  isFavorite: false,
                  onToggleFavorite: () => toggleFavTriggered = true,
                  onCancelMyBooking: () => cancelMyBookingTriggered = true,
                  onCancelDelegatedBooking: () => cancelDelegatedTriggered = true,
                );
              },
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('John Doe'), findsOneWidget);

      // Click "Libérer la place du collègue"
      final cancelDelegatedBtn = find.byKey(const ValueKey('cancel_delegated_booking_button'));
      expect(cancelDelegatedBtn, findsOneWidget);
      await tester.tap(cancelDelegatedBtn);
      await tester.pumpAndSettle();

      expect(cancelDelegatedTriggered, isTrue);
      expect(cancelMyBookingTriggered, isFalse);
      expect(toggleFavTriggered, isFalse);
    });
  });
}
