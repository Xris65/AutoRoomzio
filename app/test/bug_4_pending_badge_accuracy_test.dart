import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bug #4: Pending Badge Accuracy & Real Reservation Precedence', () {
    const mockFeatures = [
      {
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [0.0, 0.0],
              [100.0, 0.0],
              [100.0, 100.0],
              [0.0, 100.0],
              [0.0, 0.0]
            ]
          ]
        },
        'properties': {
          'id': 'desk-1',
          'workspaceId': 'desk-1',
          'workspaceType': 'Desk',
          'roomName': 'Open Space'
        }
      },
      {
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [200.0, 0.0],
              [300.0, 0.0],
              [300.0, 100.0],
              [200.0, 100.0],
              [200.0, 0.0]
            ]
          ]
        },
        'properties': {
          'id': 'desk-2',
          'workspaceId': 'desk-2',
          'workspaceType': 'Desk',
          'roomName': 'Open Space'
        }
      }
    ];

    final mockWorkspaces = [
      {'id': 'desk-1', 'name': 'Desk 1', 'isReservable': true},
      {'id': 'desk-2', 'name': 'Desk 2', 'isReservable': true},
    ];

    testWidgets('Real confirmed reservation (isMe) NEVER renders "EN ATTENTE" even if desk in pendingWorkspaceIds', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final occupants = {
        'desk-1': const DeskOccupant(
          workspaceId: 'desk-1',
          occupantName: 'Jean Dupont',
          isMe: true,
        ),
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: occupants,
            pendingWorkspaceIds: const {'desk-1'}, // Erroneously passed pending
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Should NEVER show "EN ATTENTE"
      expect(find.text('EN ATTENTE'), findsNothing);

      // Should render the user's name on their desk
      expect(find.text('DUPONT J.'), findsOneWidget);

      // The container for desk-1 must NOT have blue color, must have bold green personal desk styling
      final container = tester.widget<Container>(
        find.ancestor(
          of: find.text('DUPONT J.'),
          matching: find.byType(Container),
        ).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(const Color(0xFF22C55E))); // Green 500 for isMe in light mode
    });

    testWidgets('When user has a confirmed reservation on floor, no desk shows EN ATTENTE', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final occupants = {
        'desk-1': const DeskOccupant(
          workspaceId: 'desk-1',
          occupantName: 'Jean Dupont',
          isMe: true,
        ),
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: occupants,
            pendingWorkspaceIds: const {'desk-2'}, // Free desk-2 erroneously marked pending
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // When the user has a confirmed reservation, no pending badges allowed
      expect(find.text('EN ATTENTE'), findsNothing);
    });

    testWidgets('Unconfirmed advance programming shows EN ATTENTE on pending desk when user has no booking', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: const {}, // No bookings
            pendingWorkspaceIds: const {'desk-2'},
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Desk 2 should display EN ATTENTE
      expect(find.text('EN ATTENTE'), findsOneWidget);
    });

    testWidgets('TeamMapScreen: Confirmed booking displays "Votre bureau" and NEVER "En attente" in date header', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final testDate = DateTime(2026, 10, 20);
      final dateStr = '2026-10-20';

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh',
        'requested_dates': [dateStr], // Date is in requested_dates
        'booked_dates': [dateStr],    // But also has confirmed booking!
      });

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
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-1',
                'status': 'Booked',
                'bookedTimeSlot': {
                  'timeSlot': 'FullDay',
                  'creator': {'id': 'user-me', 'name': 'Jean Dupont'},
                  'user': {'id': 'user-me', 'name': 'Jean Dupont'},
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/users/me')) {
          return http.Response(jsonEncode({'id': 'user-me', 'name': 'Jean Dupont'}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testDate,
          apiService: api,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      // Confirmed reservation MUST show "Votre bureau"
      expect(find.text('Votre bureau'), findsOneWidget);

      // Confirmed reservation MUST NEVER show "En attente"
      expect(find.text('En attente'), findsNothing);
    });

    testWidgets('TeamMapScreen: Future date without confirmed reservation displays "En attente" in date header', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final futureDate = DateTime.now().add(const Duration(days: 20));
      final dateStr = '${futureDate.year}-${futureDate.month.toString().padLeft(2, '0')}-${futureDate.day.toString().padLeft(2, '0')}';

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh',
        'requested_dates': [dateStr], // In requested dates, NO confirmed booking
        'booked_dates': <String>[],
      });

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
          return http.Response(jsonEncode({'data': []}), 200); // Empty: no confirmed booking
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/users/me')) {
          return http.Response(jsonEncode({'id': 'user-me', 'name': 'Jean Dupont'}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: futureDate,
          apiService: api,
          storageService: storage,
        ),
      ));
      await tester.pumpAndSettle();

      // Pending reservation MUST show "En attente"
      expect(find.text('En attente'), findsOneWidget);

      // Must NOT show "Votre bureau"
      expect(find.text('Votre bureau'), findsNothing);
    });
  });
}
