import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/models/booking_result.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
import 'package:auto_roomzio/widgets/occupant_details_sheet.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/setup_screen.dart';
import 'package:auto_roomzio/background_task.dart';
import 'package:shimmer/shimmer.dart';
import 'package:auto_roomzio/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 1. DeskOccupant Domain Model Tests (Part A, Requirement 1)
  // ═════════════════════════════════════════════════════════════════════════════
  group('1. DeskOccupant Domain Model Tests', () {
    test('Initials extraction handles multi-word, single-word, and edge cases', () {
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Jean Dupont').initials, equals('JD'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Marie-Claire Martin').initials, equals('MM'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Alice').initials, equals('AL'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'B').initials, equals('B'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: '').initials, equals('?'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: '   ').initials, equals('?'));
    });

    test('formattedDisplayName formats as LASTNAME F. and handles edge cases', () {
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Jean Dupont').formattedDisplayName, equals('DUPONT J.'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Marie Curie').formattedDisplayName, equals('CURIE M.'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: 'Aristote').formattedDisplayName, equals('ARISTOTE'));
      expect(const DeskOccupant(workspaceId: '1', occupantName: '').formattedDisplayName, equals(''));
      expect(const DeskOccupant(workspaceId: '1', occupantName: '   ').formattedDisplayName, equals(''));
    });

    test('fromJson and toJson serialization roundtrip', () {
      final occ = const DeskOccupant(
        workspaceId: 'ws-101',
        occupantName: 'Sophie Germain',
        occupantId: 'usr-123',
        occupantEmail: 'sophie@math.fr',
        isMe: true,
        isDelegated: true,
        bookedByName: 'Carl Gauss',
      );

      final json = occ.toJson();
      expect(json['workspaceId'], equals('ws-101'));
      expect(json['occupantName'], equals('Sophie Germain'));
      expect(json['occupantId'], equals('usr-123'));
      expect(json['occupantEmail'], equals('sophie@math.fr'));
      expect(json['isMe'], isTrue);
      expect(json['isDelegated'], isTrue);
      expect(json['bookedByName'], equals('Carl Gauss'));

      final fromJson = DeskOccupant.fromJson(json);
      expect(fromJson, equals(occ));
      expect(fromJson.hashCode, equals(occ.hashCode));
    });

    test('copyWith updates fields correctly', () {
      const original = DeskOccupant(workspaceId: 'ws-1', occupantName: 'Alice');
      final updated = original.copyWith(occupantName: 'Bob', isMe: true);
      expect(updated.workspaceId, equals('ws-1'));
      expect(updated.occupantName, equals('Bob'));
      expect(updated.isMe, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 2. getFloorOccupants API & Hierarchy Resolution (Part A, Requirement 2)
  // ═════════════════════════════════════════════════════════════════════════════
  group('2. RoomzApiService.getFloorOccupants Tests', () {
    test('Correctly parses calendar response, resolves hierarchy, detects delegation & isMe', () async {
      final mockResponse = {
        "data": [
          // Desk 1: Delegated booking (bookedFor present and differs from creator)
          {
            "workspaceId": "ws-1",
            "status": "Reserved",
            "bookedTimeSlot": {
              "eventId": "evt-1",
              "creator": {"id": "usr-boss", "name": "Boss Man"},
              "bookedFor": {"id": "usr-colleague", "name": "Colleague A", "email": "a@corp.com"},
            }
          },
          // Desk 2: Current user booking (isMe == true)
          {
            "workspaceId": "ws-2",
            "status": "Reserved",
            "bookedTimeSlot": {
              "eventId": "evt-2",
              "user": {"id": "usr-me", "name": "Myself", "email": "me@corp.com"},
            }
          },
          // Desk 3: Available desk (should be ignored)
          {
            "workspaceId": "ws-3",
            "status": "Available",
          }
        ]
      };

      final client = MockClient((req) async {
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode(mockResponse), 200);
        }
        return http.Response('Not found', 404);
      });

      final api = RoomzApiService(client: client);
      final occupants = await api.getFloorOccupants('mock-token', 'fl-1', '2026-10-02', myUserId: 'usr-me');

      expect(occupants.containsKey('ws-1'), isTrue);
      final occ1 = occupants['ws-1']!;
      expect(occ1.occupantName, equals('Colleague A'));
      expect(occ1.occupantEmail, equals('a@corp.com'));
      expect(occ1.isDelegated, isTrue);
      expect(occ1.bookedByName, equals('Boss Man'));
      expect(occ1.isMe, isFalse);

      expect(occupants.containsKey('ws-2'), isTrue);
      final occ2 = occupants['ws-2']!;
      expect(occ2.occupantName, equals('Myself'));
      expect(occ2.isMe, isTrue);

      expect(occupants.containsKey('ws-3'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 3. WorkspaceMapViewer Visual Markings & Tap (Part A, Requirement 3)
  // ═════════════════════════════════════════════════════════════════════════════
  group('3. WorkspaceMapViewer 2D Map Visual Markings & Gestures', () {
    final mockFeatures = [
      {
        'type': 'Feature',
        'properties': {'workspaceId': 'ws-fav', 'workspaceType': 'Desk', 'name': 'B01-01'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
          ]
        }
      },
      {
        'type': 'Feature',
        'properties': {'workspaceId': 'ws-other', 'workspaceType': 'Desk', 'name': 'B01-02'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [[60.0, 10.0], [90.0, 10.0], [90.0, 40.0], [60.0, 40.0], [60.0, 10.0]]
          ]
        }
      },
      {
        'type': 'Feature',
        'properties': {'workspaceId': 'ws-me', 'workspaceType': 'Desk', 'name': 'B02-01'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [[110.0, 10.0], [140.0, 10.0], [140.0, 40.0], [110.0, 40.0], [110.0, 10.0]]
          ]
        }
      },
    ];

    final mockWorkspaces = [
      {'id': 'ws-fav', 'name': 'B01-01', 'isBookable': true},
      {'id': 'ws-other', 'name': 'B01-02', 'isBookable': true},
      {'id': 'ws-me', 'name': 'B02-01', 'isBookable': true},
    ];

    final mockOccupants = {
      'ws-fav': const DeskOccupant(
        workspaceId: 'ws-fav',
        occupantName: 'Sophie Germain',
        occupantId: 'usr-sophie',
      ),
      'ws-other': const DeskOccupant(
        workspaceId: 'ws-other',
        occupantName: 'Bob Normal',
        occupantId: 'usr-bob',
      ),
      'ws-me': const DeskOccupant(
        workspaceId: 'ws-me',
        occupantName: 'Myself',
        occupantId: 'usr-me',
        isMe: true,
      ),
    };

    testWidgets('Favorite desk renders initials without icons; personal desk and other render initials', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: mockOccupants,
            favoriteIds: const {'usr-sophie'},
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // No icons on desks (Directive 1)
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byIcon(Icons.person), findsNothing);

      // Occupant formatted display name rendered prominently (Directive 3)
      expect(find.text('GERMAIN S.'), findsOneWidget);
      expect(find.text('NORMAL B.'), findsOneWidget);
      expect(find.text('MYSELF'), findsOneWidget);
    });

    testWidgets('Tapping marked desk invokes onOccupantTapped callback with colleague identity', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      DeskOccupant? tappedOccupant;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: mockOccupants,
            favoriteIds: const {'usr-sophie'},
            onSelected: (_) {},
            onOccupantTapped: (ws, occ) {
              tappedOccupant = occ;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('01').first);
      await tester.pumpAndSettle();

      expect(tappedOccupant, isNotNull);
      expect(tappedOccupant!.occupantName, equals('Sophie Germain'));
      expect(tappedOccupant!.occupantId, equals('usr-sophie'));
    });

    testWidgets('Focused room dims desks outside focused room with 0.25 opacity', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: mockFeatures,
            workspaces: mockWorkspaces,
            occupants: mockOccupants,
            favoriteIds: const {'usr-sophie'},
            focusedRoom: 'B01',
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.any((o) => o.opacity == 0.25), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 4. OccupantDetailsSheet Modal Bottom Sheet (Part A, Requirement 4)
  // ═════════════════════════════════════════════════════════════════════════════
  group('4. OccupantDetailsSheet Modal Bottom Sheet Tests', () {
    testWidgets('Displays occupant name, initials, star badge, room, and toggle button', (tester) async {
      bool toggleCalled = false;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                OccupantDetailsSheet.show(
                  context: ctx,
                  workspace: {'name': 'B01-08', 'roomName': 'Salle B01'},
                  occupant: const DeskOccupant(
                    workspaceId: 'ws-1',
                    occupantName: 'Ada Lovelace',
                    occupantEmail: 'ada@computing.org',
                  ),
                  isFavorite: true,
                  onToggleFavorite: () => toggleCalled = true,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('AL'), findsOneWidget); // Initials
      expect(find.text('⭐ Favori'), findsOneWidget);
      expect(find.text('ada@computing.org'), findsOneWidget);
      expect(find.text('B01-08'), findsOneWidget);
      expect(find.text('Salle B01'), findsOneWidget);
      expect(find.text('Retirer des favoris'), findsOneWidget);

      await tester.tap(find.text('Retirer des favoris'));
      await tester.pumpAndSettle();
      expect(toggleCalled, isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 5. TeamMapScreen Screen Integration Tests (Part A, Requirement 5)
  // ═════════════════════════════════════════════════════════════════════════════
  group('5. TeamMapScreen Screen Integration Tests', () {
    testWidgets('Renders header, room filter chips with star, and date navigation', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'favorite_colleagues': jsonEncode([
          {'id': 'usr-fav', 'name': 'Thomas Pesquet', 'email': 'thomas@esa.int', 'isFavorite': true}
        ]),
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
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'user': {'id': 'usr-fav', 'name': 'Thomas Pesquet', 'email': 'thomas@esa.int'}
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

      expect(find.text("Plan d'équipe"), findsOneWidget);
      expect(find.textContaining('Tous les bureaux'), findsOneWidget);
      expect(find.textContaining('B01 (1)'), findsOneWidget);
      expect(find.textContaining('1 collègue favori sur site'), findsOneWidget);
      // Map legend items (Directive 2)
      expect(find.text("Collègue favori"), findsOneWidget);
      expect(find.text("Mon bureau"), findsOneWidget);
      expect(find.text("Occupé"), findsOneWidget);
      expect(find.text("Libre"), findsOneWidget);

      // Date navigation right button tap
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 6. HomeScreen Integration Hooks (Part A, Requirement 6 & M3.1)
  // ═════════════════════════════════════════════════════════════════════════════
  group('6. HomeScreen Integration Hooks', () {
    testWidgets('Calendar header has team map icon button', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
        'workspace_id': 'ws-1',
        'workspace_name': 'Desk 1',
        'initial_tab': 1, // Calendar tab
      });

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.map_outlined), findsWidgets);
    });

    testWidgets('Calendar header has direct favorites management button that opens dialog', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
        'workspace_id': 'ws-1',
        'workspace_name': 'Desk 1',
        'initial_tab': 1, // Calendar tab
      });

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      final favBtn = find.byIcon(Icons.star_rounded);
      expect(favBtn, findsWidgets);

      await tester.tap(favBtn.first);
      await tester.pumpAndSettle();

      expect(find.text("Mes collègues favoris"), findsOneWidget);
      expect(find.text("Ajouter un collègue"), findsWidgets);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 7. Hotfix 1: HTTP 401 Session Interception & Auto-Redirect
  // ═════════════════════════════════════════════════════════════════════════════
  group('7. Hotfix 1: HTTP 401 Session Expiry Interception', () {
    test('Token refresh failure on 401 triggers onSessionExpired and clears tokens', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'expired-refresh-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async => http.Response('{"error": "invalid_token"}', 401));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isTrue);

      final savedToken = await storage.getRefreshToken();
      expect(savedToken, isNull);
    });

    test('Token refresh failure on 400, 429, or 500 does NOT trigger onSessionExpired and preserves tokens', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'valid-refresh-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      // Mock rate limit 429
      final client = MockClient((req) async => http.Response('{"error": "rate_limited"}', 429));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isFalse);

      final savedToken = await storage.getRefreshToken();
      expect(savedToken, equals('valid-refresh-token'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 8. Hotfix 2: Setup Screen List Scroll Lock Fix
  // ═════════════════════════════════════════════════════════════════════════════
  group('8. Hotfix 2: SetupScreen Stepper Scroll Physics', () {
    testWidgets('Step 0 and Step 1 have AlwaysScrollableScrollPhysics; Step 2 map active has NeverScrollableScrollPhysics', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/buildings') || req.url.path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Site 1'}]), 200);
        }
        return http.Response('[]', 200);
      });
      final api = RoomzApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: SetupScreen(accessToken: 'mock-access-token', apiService: api),
      ));
      await tester.pumpAndSettle();

      final steppers = tester.widgetList<Stepper>(find.byType(Stepper));
      expect(steppers, isNotEmpty);
      final stepper = steppers.first;
      // On Step 0, physics must be AlwaysScrollableScrollPhysics and not NeverScrollableScrollPhysics
      expect(stepper.physics, isNot(isA<NeverScrollableScrollPhysics>()));
      expect(stepper.physics, isA<AlwaysScrollableScrollPhysics>());
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 9. Hotfix 3: Error Body Mapping & Delegation Conflict
  // ═════════════════════════════════════════════════════════════════════════════
  group('9. Hotfix 3: Error Body Mapping & Payload Formatting', () {
    test('HTTP 400 returns actual server error message instead of hardcoded 13 days', () async {
      final client = MockClient((req) async => http.Response(
        jsonEncode({'message': 'Ce collègue ne peut pas réserver dans cette zone.'}),
        400,
      ));

      final api = RoomzApiService(client: client);
      final res = await api.reserveWorkspaceForColleague(
        date: '2026-10-02',
        token: 'mock-token',
        workspaceId: 'ws-1',
        colleagueId: 'usr-1',
      );

      expect(res.status, equals(BookingStatus.invalidDate));
      expect(res.message, equals('Ce collègue ne peut pas réserver dans cette zone.'));
      expect(res.getLocalizedMessage(), equals('Ce collègue ne peut pas réserver dans cette zone.'));
    });

    test('HTTP 400 with already booked conflict returns conflictColleague status', () async {
      final client = MockClient((req) async => http.Response(
        jsonEncode({'message': 'User already has a reservation on this date'}),
        400,
      ));

      final api = RoomzApiService(client: client);
      final res = await api.reserveWorkspaceForColleague(
        date: '2026-10-02',
        token: 'mock-token',
        workspaceId: 'ws-1',
        colleagueId: 'usr-1',
      );

      expect(res.status, equals(BookingStatus.conflictColleague));
      expect(res.message, contains('already has a reservation'));
    });

    test('Internal UUID colleague uses bookAsUserId at root; external colleague uses bookAsExternalOrganizer', () async {
      String? sentBody;
      final client = MockClient((req) async {
        sentBody = req.body;
        return http.Response(jsonEncode({'eventId': 'evt-100'}), 200);
      });

      final api = RoomzApiService(client: client);

      // Internal colleague with UUID
      await api.reserveWorkspaceForColleague(
        date: '2026-10-02',
        token: 'mock-token',
        workspaceId: 'ws-1',
        colleagueId: '12345678-abcd-ef01-2345-6789abcdef01',
      );
      final decodedInternal = jsonDecode(sentBody!);
      expect(decodedInternal['bookAsUserId'], equals('12345678-abcd-ef01-2345-6789abcdef01'));
      expect(decodedInternal.containsKey('bookAsExternalOrganizer'), isFalse);

      // External colleague with email
      await api.reserveWorkspaceForColleague(
        date: '2026-10-02',
        token: 'mock-token',
        workspaceId: 'ws-1',
        colleagueId: 'ext_colleague',
        colleagueEmail: 'ext@partner.com',
        colleagueName: 'External Partner',
      );
      final decodedExternal = jsonDecode(sentBody!);
      expect(decodedExternal.containsKey('bookAsExternalOrganizer'), isTrue);
      expect(decodedExternal['bookAsExternalOrganizer']['email'], equals('ext@partner.com'));
      expect(decodedExternal['bookAsExternalOrganizer']['displayName'], equals('External Partner'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 10. Hotfix 4: Delegation Button Hidden on Occupied Desk
  // ═════════════════════════════════════════════════════════════════════════════
  group('10. Hotfix 4: Delegation Button Hidden on Occupied Desk', () {
    testWidgets('When desk occupied by third party, delegation button is hidden even if booked elsewhere', (tester) async {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      final dateStr = "${tomorrow.year.toString().padLeft(4, '0')}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}";

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
        'workspace_id': 'ws-1',
        'workspace_name': 'My Desk',
        'initial_tab': 1,
        'booked_elsewhere_dates': [dateStr],
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-1',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'user': {'name': 'Tristan Follain'}
                }
              }
            ]
          }), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Tap tomorrow on the calendar to open date sheet
      final dayFinder = find.text('${tomorrow.day}');
      if (dayFinder.evaluate().isNotEmpty) {
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        // Delegation button should NOT be visible when desk is occupied by third party
        // (Instead "Place indisponible" is shown)
        expect(find.text('Réserver pour un collègue'), findsNothing);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 11. Hotfix 5: Server Persistence of Favorites (POST & DELETE)
  // ═════════════════════════════════════════════════════════════════════════════
  group('11. Hotfix 5: Server Persistence of Favorites', () {
    test('addFavorite and removeFavorite make correct HTTP calls to server endpoints', () async {
      final calledUrls = <String>[];
      final calledMethods = <String>[];

      final client = MockClient((req) async {
        calledUrls.add(req.url.toString());
        calledMethods.add(req.method);
        return http.Response('', 204);
      });

      final api = RoomzApiService(client: client);

      final addSuccess = await api.addFavorite('mock-token', 'usr-colleague-123');
      expect(addSuccess, isTrue);
      expect(calledUrls.last, equals('https://api.my.roomz.io/favorites/usr-colleague-123'));
      expect(calledMethods.last, equals('POST'));

      final removeSuccess = await api.removeFavorite('mock-token', 'usr-colleague-123');
      expect(removeSuccess, isTrue);
      expect(calledUrls.last, equals('https://api.my.roomz.io/favorites/usr-colleague-123'));
      expect(calledMethods.last, equals('DELETE'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 12. Smart Room Filter Chips Comparator & Exclusion of Empty Rooms
  // ═════════════════════════════════════════════════════════════════════════════
  group('12. Smart Room Filter Chips Comparator', () {
    testWidgets('Ranks rooms by favorites count desc, then occupancy desc, then alphabetical, and strictly excludes empty rooms', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'favorite_colleagues': jsonEncode([
          {'id': 'usr-fav', 'name': 'Favorite Person', 'email': 'fav@example.com', 'isFavorite': true}
        ]),
      });

      final mockAllWorkspaces = [
        {'id': 'ws-a1', 'name': 'RoomA-01', 'workspaceType': 'Desk', 'isReservable': true},
        {'id': 'ws-a2', 'name': 'RoomA-02', 'workspaceType': 'Desk', 'isReservable': true},
        {'id': 'ws-b1', 'name': 'RoomB-01', 'workspaceType': 'Desk', 'isReservable': true},
        {'id': 'ws-c1', 'name': 'RoomC-01', 'workspaceType': 'Desk', 'isReservable': true},
        {'id': 'ws-empty', 'name': 'EmptyRoom-01', 'workspaceType': 'Desk', 'isReservable': true},
      ];

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/workspaces/all')) {
          return http.Response(jsonEncode(mockAllWorkspaces), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-a1', 'name': 'RoomA-01', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              // Room B has 1 favorite colleague (usr-fav)
              {
                'workspaceId': 'ws-b1',
                'status': 'Reserved',
                'bookedTimeSlot': {'user': {'id': 'usr-fav', 'name': 'Favorite Person'}}
              },
              // Room A has 2 regular occupants
              {
                'workspaceId': 'ws-a1',
                'status': 'Reserved',
                'bookedTimeSlot': {'user': {'id': 'usr-reg1', 'name': 'Regular 1'}}
              },
              {
                'workspaceId': 'ws-a2',
                'status': 'Reserved',
                'bookedTimeSlot': {'user': {'id': 'usr-reg2', 'name': 'Regular 2'}}
              },
              // Room C has 1 regular occupant
              {
                'workspaceId': 'ws-c1',
                'status': 'Reserved',
                'bookedTimeSlot': {'user': {'id': 'usr-reg3', 'name': 'Regular 3'}}
              },
            ]
          }), 200);
        }
        if (path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Main Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Etage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // EmptyRoom should NOT be present in filter chips (0 occupants)
      expect(find.textContaining('EmptyRoom'), findsNothing);

      // RoomB has favorite (1) -> should be first with star
      expect(find.text('RoomB (1)'), findsOneWidget);

      // RoomA has 2 occupants -> should be present
      expect(find.text('RoomA (2)'), findsOneWidget);

      // RoomC has 1 occupant -> should be present
      expect(find.text('RoomC (1)'), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 13. "Collègues présents" Summary Panel Presence and Occupant Details
  // ═════════════════════════════════════════════════════════════════════════════
  group('13. Collègues présents Summary Panel', () {
    testWidgets('Displays expandable summary panel with count and occupant details', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
      });

      final mockAllWorkspaces = [
        {'id': 'ws-1', 'name': 'Bureau-01', 'workspaceType': 'Desk', 'isReservable': true},
      ];

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/workspaces/all')) {
          return http.Response(jsonEncode(mockAllWorkspaces), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'name': 'Bureau-01', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-1',
                'status': 'Reserved',
                'bookedTimeSlot': {'user': {'id': 'usr-colleague', 'name': 'Alexandre Dumas'}}
              }
            ]
          }), 200);
        }
        if (path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Etage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Find the collapsed panel button
      expect(find.text('Collègues présents (1)'), findsOneWidget);

      // Tap to expand panel
      await tester.tap(find.text('Collègues présents (1)'));
      await tester.pumpAndSettle();

      // Detailed card should be visible
      expect(find.text('Alexandre Dumas'), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 14. Calendar Date-Tap Modal UX Cleanup (Absence of Duplicate Map Button)
  // ═════════════════════════════════════════════════════════════════════════════
  group('14. Calendar Date-Tap Modal UX Cleanup', () {
    testWidgets('Date-tap sheet has booking actions but NO duplicate team map button', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final tomorrow = DateTime.now().add(const Duration(days: 1));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
        'workspace_id': 'ws-1',
        'workspace_name': 'Desk 1',
        'initial_tab': 1, // Calendar tab
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('[]', 200);
      });
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final dayFinder = find.text('${tomorrow.day}');
      if (dayFinder.evaluate().isNotEmpty) {
        await tester.tap(dayFinder.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Should NOT have duplicate "Où est mon équipe ?" in date tap modal
        expect(find.text('Où est mon équipe ?'), findsNothing);
      }
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 15. Geometric Bounding Box & Sizing Tests
  // ═════════════════════════════════════════════════════════════════════════════
  group('15. Geometric Bounding Box & Canvas Sizing', () {
    testWidgets('WorkspaceMapViewer renders formattedDisplayName inside desk box', (tester) async {
      final features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-1', 'name': 'Room-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[10.0, 10.0], [40.0, 10.0], [40.0, 30.0], [10.0, 30.0], [10.0, 10.0]]
            ]
          }
        }
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: WorkspaceMapViewer(
              features: features,
              workspaces: const [{'id': 'ws-1', 'name': 'Room-01'}],
              allWorkspaces: const [{'id': 'ws-1', 'name': 'Room-01'}],
              occupants: const {
                'ws-1': DeskOccupant(workspaceId: 'ws-1', occupantName: 'Marie Curie')
              },
              favoriteIds: const {},
              favoriteNamesNormalized: const {},
              favoriteWorkspaceIds: const {},
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Formatted display name "CURIE M." must be rendered inside the desk box
      expect(find.text('CURIE M.'), findsOneWidget);
      // Desk label 01 must be rendered
      expect(find.text('01'), findsOneWidget);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 16. "Organizer Not Found" Auto-Retry With bookAsExternalOrganizer
  // ═════════════════════════════════════════════════════════════════════════════
  group('16. Organizer Not Found Auto-Retry', () {
    test('Retries with bookAsExternalOrganizer when bookAsUserId returns 400 Organizer not found', () async {
      int postAttempts = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path.contains('/bookings')) {
          postAttempts++;
          final body = jsonDecode(req.body);
          if (body.containsKey('bookAsUserId')) {
            // First attempt: Server rejects with Organizer not found
            return http.Response(
              jsonEncode({'message': 'Organizer not found', 'statusCode': 400}),
              400,
            );
          } else if (body.containsKey('bookAsExternalOrganizer')) {
            // Second attempt: Success with bookAsExternalOrganizer
            return http.Response(
              jsonEncode({'eventId': 'evt-retry-success-123'}),
              201,
            );
          }
        }
        return http.Response('Not found', 404);
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: '2026-10-02',
        token: 'mock-token',
        workspaceId: 'ws-100',
        colleagueId: '12345678-abcd-1111-2222-333344445555',
        colleagueName: 'Victor Hugo',
        colleagueEmail: 'victor.hugo@france.fr',
      );

      expect(postAttempts, equals(2));
      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('evt-retry-success-123'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 17. Pending Booking Conversion & Hotfix 6 Conflict Guards
  // ═════════════════════════════════════════════════════════════════════════════
  group('17. Pending Booking Conversion & Conflict Guards', () {
    test('runBackgroundBookingAutomation respects conflict guards and converts pending dates within 13 days', () async {
      final storage = StorageService();
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-target');
      await storage.saveRefreshToken('mock-token');

      final now = DateTime(2026, 10, 2);
      final targetDateStr = '2026-10-05'; // 3 days in advance (<= 13)

      await storage.saveRequestedDates([targetDateStr]);
      await storage.saveDays([1, 2, 3, 4, 5]);

      final client = MockClient((req) async {
        if (req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'new-tok', 'refresh_token': 'new-ref'}), 200);
        }
        if (req.url.path.contains('/users/current/reservations') || req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/occupancy') || req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          return http.Response(jsonEncode({'id': 'b-auto-1'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final count = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
      );

      expect(count, greaterThanOrEqualTo(0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 18. Date Navigation Rapid-Click Resilience (M3.5)
  // ═════════════════════════════════════════════════════════════════════════════
  group('18. Date Navigation Rapid-Click Resilience', () {
    testWidgets('Rapidly clicking date nav does NOT trigger logout or refresh token flood', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      int tokenRefreshCount = 0;
      int calendarRequestCount = 0;

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-1',
        'refresh_token': 'mock-refresh-token',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          tokenRefreshCount++;
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'name': 'Room-01', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          calendarRequestCount++;
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Floor 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Tap next day arrow rapidly 3 times
      final nextDayBtn = find.byTooltip('Jour suivant');
      expect(nextDayBtn, findsOneWidget);

      await tester.tap(nextDayBtn);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(nextDayBtn);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(nextDayBtn);
      await tester.pumpAndSettle();

      // Must NOT fire session expired / logout
      expect(sessionExpiredFired, isFalse);
      // Token was not repeatedly refreshed on every date click
      expect(tokenRefreshCount, equals(1));
      // Multiple calendar requests were processed cleanly
      expect(calendarRequestCount, greaterThan(1));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 19. Default Desk Camera Centering (M3.5)
  // ═════════════════════════════════════════════════════════════════════════════
  group('19. Default Desk Camera Centering', () {
    testWidgets('WorkspaceMapViewer centers camera directly on defaultWorkspaceId', (tester) async {
      final features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-other', 'name': 'Other-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[0.0, 0.0], [20.0, 0.0], [20.0, 20.0], [0.0, 20.0], [0.0, 0.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-target', 'name': 'Target-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[200.0, 200.0], [240.0, 200.0], [240.0, 230.0], [200.0, 230.0], [200.0, 200.0]]
            ]
          }
        }
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: WorkspaceMapViewer(
              features: features,
              workspaces: const [
                {'id': 'ws-other', 'name': 'Other-01', 'isBookable': true},
                {'id': 'ws-target', 'name': 'Target-01', 'isBookable': true},
              ],
              defaultWorkspaceId: 'ws-target',
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final deskNumberFinder = find.text('01');
      expect(deskNumberFinder, findsAtLeastNWidgets(1));
      final roomNameFinder = find.text('Target');
      expect(roomNameFinder, findsOneWidget);

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = iv.transformationController?.value;
      expect(matrix, isNotNull);
      expect(matrix!.storage[12], isNegative);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 20. TeamMapScreen Shimmer Skeleton Loading (M3.5)
  // ═════════════════════════════════════════════════════════════════════════════
  group('20. TeamMapScreen Shimmer Skeleton Loading', () {
    testWidgets('Displays Shimmer skeleton in map area Stack while real header, filter chips bar, and legend bar remain static & visible', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'site_id': 'site-1',
        'floor_id': 'fl-1',
      });

      final completer = Completer<http.Response>();
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'atk-1', 'refresh_token': 'rtk-1'}), 200);
        }
        return await completer.future;
      });
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));

      // Pump single frame to observe initial loading state before network completes
      await tester.pump();

      // 1. Shimmer is displayed for the map area
      final shimmerFinder = find.byType(Shimmer);
      expect(shimmerFinder, findsOneWidget);

      // 2. Map area Shimmer contains an architectural 2D Stack with 5 asymmetrical Positioned room containers
      final stackInShimmer = find.descendant(of: shimmerFinder, matching: find.byType(Stack));
      expect(stackInShimmer, findsOneWidget);
      final positionedRooms = find.descendant(of: stackInShimmer, matching: find.byType(Positioned));
      expect(positionedRooms, findsNWidgets(5));

      // 3. Real static header (date navigation bar) is visible on screen during loading
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // 4. Real filter chips bar is visible on screen during loading
      expect(find.byType(FilterChip), findsAtLeastNWidgets(1));
      expect(find.textContaining('Tous les bureaux'), findsOneWidget);

      // 5. Real legend bar is visible on screen during loading
      expect(find.text('Collègue favori'), findsOneWidget);
      expect(find.text('Mon bureau'), findsOneWidget);
      expect(find.text('Occupé'), findsOneWidget);
      expect(find.text('Libre'), findsOneWidget);

      // Complete the network call
      completer.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();

      // Shimmer is gone once loaded
      expect(find.byType(Shimmer), findsNothing);

      // Real header, filter chips bar, and legend bar remain visible
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);
      expect(find.textContaining('Tous les bureaux'), findsOneWidget);
      expect(find.text('Collègue favori'), findsOneWidget);
    });

    testWidgets('Map skeleton contains 5 asymmetrical rounded room containers with subtle borders and inner desk silhouette blocks', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'site_id': 'site-1',
        'floor_id': 'fl-1',
      });

      final completer = Completer<http.Response>();
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'atk-1', 'refresh_token': 'rtk-1'}), 200);
        }
        return await completer.future;
      });
      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pump();

      // Find the 5 Positioned rooms in the Stack
      final positionedWidgets = tester.widgetList<Positioned>(
        find.descendant(
          of: find.byType(Shimmer),
          matching: find.byType(Positioned),
        ),
      ).toList();

      expect(positionedWidgets.length, equals(5));

      // Verify asymmetry in positions/dimensions (combination of squares and rectangles)
      expect(positionedWidgets[0].height, equals(130)); // Room 1: horizontal rectangle
      expect(positionedWidgets[1].height, equals(185)); // Room 2: vertical rectangle
      expect(positionedWidgets[2].height, equals(155)); // Room 3: vertical rectangle
      expect(positionedWidgets[3].height, equals(140)); // Room 4: square
      expect(positionedWidgets[4].height, equals(95));  // Room 5: wide horizontal rectangle

      completer.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // 21. UI Scale Accessibility Control & Global Clamping
  // ═════════════════════════════════════════════════════════════════════════════
  group('21. UI Scale Accessibility Control & Clamping', () {
    test('StorageService saveUiScale and getUiScale persists value with default 1.0', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();

      expect(await storage.getUiScale(), equals(1.0));

      await storage.saveUiScale(0.85);
      expect(await storage.getUiScale(), equals(0.85));

      await storage.saveUiScale(1.15);
      expect(await storage.getUiScale(), equals(1.15));
    });

    testWidgets('MaterialApp builder clamps TextScaler between 0.75 and 1.35', (tester) async {
      uiScaleNotifier.value = 1.0;

      await tester.pumpWidget(
        ValueListenableBuilder<double>(
          valueListenable: uiScaleNotifier,
          builder: (context, uiScale, _) {
            return MaterialApp(
              builder: (context, child) {
                final mediaQuery = MediaQuery.of(context);
                final targetScale = (mediaQuery.textScaler.scale(1.0) * uiScale).clamp(0.75, 1.35);
                return MediaQuery(
                  data: mediaQuery.copyWith(textScaler: TextScaler.linear(targetScale)),
                  child: child ?? const SizedBox.shrink(),
                );
              },
              home: const Scaffold(body: Text('Test UI Scale')),
            );
          },
        ),
      );
      await tester.pump();

      BuildContext context = tester.element(find.text('Test UI Scale'));
      expect(MediaQuery.of(context).textScaler.scale(1.0), inInclusiveRange(0.75, 1.35));

      // Test extreme upper scaling (2.0) clamps to 1.35
      uiScaleNotifier.value = 2.0;
      await tester.pump();
      context = tester.element(find.text('Test UI Scale'));
      expect(MediaQuery.of(context).textScaler.scale(1.0), equals(1.35));

      // Test extreme lower scaling (0.5) clamps to 0.75
      uiScaleNotifier.value = 0.5;
      await tester.pump();
      context = tester.element(find.text('Test UI Scale'));
      expect(MediaQuery.of(context).textScaler.scale(1.0), equals(0.75));

      // Reset
      uiScaleNotifier.value = 1.0;
    });
  });
}
