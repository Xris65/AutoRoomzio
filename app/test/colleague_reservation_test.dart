import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/models/booking_result.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/widgets/colleague_selection_dialog.dart';
import 'package:auto_roomzio/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // 1. Colleague Domain Model Tests
  // =========================================================================
  group('1. Colleague Domain Model Tests', () {
    test('Serialization and deserialization preserves all fields', () {
      const colleague = Colleague(
        id: 'usr-101',
        name: 'Marie Curie',
        email: 'marie.curie@radium.fr',
        isFavorite: true,
        deskName: 'DS-BORD-1-18-D',
        roomName: 'Etage 1 Open Space',
        avatarUrl: 'https://cdn.example.com/curie.png',
      );

      final jsonMap = colleague.toJson();
      expect(jsonMap['id'], equals('usr-101'));
      expect(jsonMap['name'], equals('Marie Curie'));
      expect(jsonMap['email'], equals('marie.curie@radium.fr'));
      expect(jsonMap['isFavorite'], isTrue);
      expect(jsonMap['deskName'], equals('DS-BORD-1-18-D'));
      expect(jsonMap['roomName'], equals('Etage 1 Open Space'));
      expect(jsonMap['avatarUrl'], equals('https://cdn.example.com/curie.png'));

      final restored = Colleague.fromJson(jsonMap);
      expect(restored, equals(colleague));
    });

    test('fromJson handles partial JSON and alternative MyRoomz keys', () {
      final jsonMinimal = {
        'id': 'usr-202',
        'displayName': 'Alexandre Dumas',
        'mail': 'alex@dumas.fr',
        'favorite': true,
        'workspaceName': 'Desk B-04',
        'photo': 'https://photo.url/pic.jpg',
      };

      final colleague = Colleague.fromJson(jsonMinimal);
      expect(colleague.id, equals('usr-202'));
      expect(colleague.name, equals('Alexandre Dumas'));
      expect(colleague.email, equals('alex@dumas.fr'));
      expect(colleague.isFavorite, isTrue);
      expect(colleague.deskName, equals('Desk B-04'));
      expect(colleague.avatarUrl, equals('https://photo.url/pic.jpg'));
    });

    test('Initials calculation handles various name formats', () {
      // Standard two words
      expect(const Colleague(id: '1', name: 'Marie Laurent').initials, equals('ML'));
      // Single word
      expect(const Colleague(id: '2', name: 'Alice').initials, equals('A'));
      // Multiple words (first + last)
      expect(const Colleague(id: '3', name: 'Charles Louis de Montesquieu').initials, equals('CM'));
      // Irregular spacing
      expect(const Colleague(id: '4', name: '  Victor   Hugo  ').initials, equals('VH'));
      // Accents
      expect(const Colleague(id: '5', name: 'Élodie Vasseur').initials, equals('ÉV'));
      // Empty and whitespace
      expect(const Colleague(id: '6', name: '').initials, equals('?'));
      expect(const Colleague(id: '7', name: '   ').initials, equals('?'));
    });

    test('Value equality and hashCode behavior', () {
      const c1 = Colleague(id: '1', name: 'Jean', email: 'j@a.com', isFavorite: true);
      const c2 = Colleague(id: '1', name: 'Jean', email: 'j@a.com', isFavorite: true);
      const c3 = Colleague(id: '1', name: 'Jean', email: 'j@a.com', isFavorite: false);

      expect(c1, equals(c2));
      expect(c1.hashCode, equals(c2.hashCode));
      expect(c1, isNot(equals(c3)));
    });

    test('copyWith creates modified clone preserving untouched fields', () {
      const original = Colleague(
        id: '1',
        name: 'Thomas Novak',
        email: 't@novak.com',
        isFavorite: false,
        deskName: 'Desk 12',
      );

      final modified = original.copyWith(isFavorite: true, deskName: 'Desk 14');
      expect(modified.id, equals('1'));
      expect(modified.name, equals('Thomas Novak'));
      expect(modified.email, equals('t@novak.com'));
      expect(modified.isFavorite, isTrue);
      expect(modified.deskName, equals('Desk 14'));
      expect(original.isFavorite, isFalse);
    });
  });

  // =========================================================================
  // 2. BookingResult Domain Model Tests
  // =========================================================================
  group('2. BookingResult Domain Model Tests', () {
    test('Success status getters and localized messages', () {
      const result = BookingResult.success(
        eventId: 'evt-uuid-456',
        colleagueId: 'usr-1',
        colleagueName: 'Marie',
      );

      expect(result.isSuccess, isTrue);
      expect(result.isConflict, isFalse);
      expect(result.eventId, equals('evt-uuid-456'));
      expect(result.getLocalizedMessage(), equals('Bureau réservé pour Marie !'));
    });

    test('Conflict status mappings and localized French messages', () {
      const deskConflict = BookingResult.conflictDesk();
      expect(deskConflict.isSuccess, isFalse);
      expect(deskConflict.isConflict, isTrue);
      expect(deskConflict.isConflictDesk, isTrue);
      expect(deskConflict.isConflictColleague, isFalse);
      expect(deskConflict.getLocalizedMessage('Thomas'), equals('Ce bureau est déjà réservé par quelqu\'un d\'autre.'));

      const colleagueConflict = BookingResult.conflictColleague();
      expect(colleagueConflict.isSuccess, isFalse);
      expect(colleagueConflict.isConflict, isTrue);
      expect(colleagueConflict.isConflictColleague, isTrue);
      expect(colleagueConflict.isConflictDesk, isFalse);
      expect(colleagueConflict.getLocalizedMessage('Thomas'), equals('Thomas a déjà une réservation ce jour-là.'));
    });

    test('Remaining status codes have appropriate localized French messages', () {
      const horizon = BookingResult(
        status: BookingStatus.invalidDate,
        message: 'Invalid date',
      );
      expect(horizon.getLocalizedMessage(), equals("La réservation manuelle est limitée à 13 jours à l'avance."));

      const unauthorized = BookingResult(
        status: BookingStatus.unauthorized,
        message: 'Unauthorized',
      );
      expect(unauthorized.getLocalizedMessage(), equals('Session expirée. Reconnexion requise.'));

      const forbidden = BookingResult(
        status: BookingStatus.forbidden,
        message: 'Forbidden',
      );
      expect(forbidden.getLocalizedMessage(), equals('Votre profil n\'a pas les droits pour réserver pour un tiers.'));

      const serverError = BookingResult(
        status: BookingStatus.serverError,
        message: 'Erreur 500 interne',
      );
      expect(serverError.getLocalizedMessage(), equals('Erreur 500 interne'));

      const networkError = BookingResult(
        status: BookingStatus.networkError,
        message: 'Erreur de connexion',
      );
      expect(networkError.getLocalizedMessage(), equals('Erreur de connexion'));
    });
  });

  // =========================================================================
  // 3. StorageService Favorite Colleagues Persistence Tests
  // =========================================================================
  group('3. StorageService Favorite Colleagues Persistence Tests', () {
    late StorageService storage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
    });

    test('getFavoriteColleagues returns empty list initially', () async {
      final list = await storage.getFavoriteColleagues();
      expect(list, isEmpty);
    });

    test('saveFavoriteColleagues and getFavoriteColleagues roundtrip', () async {
      final colleagues = [
        const Colleague(id: '1', name: 'Alexandre Dumas', email: 'alex@corp.com', isFavorite: true),
        const Colleague(id: '2', name: 'Marie Laurent', email: 'marie@corp.com', isFavorite: true),
      ];

      await storage.saveFavoriteColleagues(colleagues);
      final retrieved = await storage.getFavoriteColleagues();

      expect(retrieved.length, equals(2));
      expect(retrieved[0].name, equals('Alexandre Dumas'));
      expect(retrieved[1].name, equals('Marie Laurent'));
    });

    test('addFavoriteColleague appends and updates idempotently', () async {
      const col1 = Colleague(id: 'c1', name: 'Claire Bernard', email: 'c@b.com');
      await storage.addFavoriteColleague(col1);

      var list = await storage.getFavoriteColleagues();
      expect(list.length, equals(1));
      expect(list.first.isFavorite, isTrue);

      // Updating same ID with new desk name
      const col1Updated = Colleague(id: 'c1', name: 'Claire Bernard', deskName: 'Desk A');
      await storage.addFavoriteColleague(col1Updated);

      list = await storage.getFavoriteColleagues();
      expect(list.length, equals(1));
      expect(list.first.deskName, equals('Desk A'));
      expect(list.first.isFavorite, isTrue);
    });

    test('removeFavoriteColleague deletes specific colleague', () async {
      await storage.saveFavoriteColleagues([
        const Colleague(id: 'c1', name: 'User 1', isFavorite: true),
        const Colleague(id: 'c2', name: 'User 2', isFavorite: true),
      ]);

      await storage.removeFavoriteColleague('c1');
      final list = await storage.getFavoriteColleagues();

      expect(list.length, equals(1));
      expect(list.first.id, equals('c2'));
    });

    test('isFavoriteColleague correctly reports favorite status', () async {
      await storage.addFavoriteColleague(const Colleague(id: 'c99', name: 'VIP Colleague'));

      expect(await storage.isFavoriteColleague('c99'), isTrue);
      expect(await storage.isFavoriteColleague('c00'), isFalse);
    });

    test('getFavoriteColleagues handles corrupted JSON gracefully', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': 'malformed-json-content{{{',
      });

      final list = await storage.getFavoriteColleagues();
      expect(list, isEmpty);
    });
  });

  // =========================================================================
  // 4. RoomzApiService Delegation & Directory Tests (with MockClient)
  // =========================================================================
  group('4. RoomzApiService Delegation & Directory Tests', () {
    const String mockToken = 'mock-bearer-token';
    const String mockWorkspaceId = 'ws-uuid-101';
    const String mockColleagueId = 'user-uuid-202';
    const String mockColleagueName = 'Marie Curie';
    const String mockDate = '2026-10-15';

    test('HTTP 200 with eventId in "ws/uuid" format extracts UUID and sends bookAsUserId for internal user', () async {
      final client = MockClient((req) async {
        expect(req.method, equals('POST'));
        expect(req.url.path, equals('/bookings'));
        final body = jsonDecode(req.body);
        expect(body['workspaceId'], equals(mockWorkspaceId));
        expect(body['localDate'], equals(mockDate));
        expect(body['timeSlot'], equals('FullDay'));
        expect(body['bookAsUserId'], equals(mockColleagueId));

        return http.Response(
          jsonEncode({'id': 'b-1', 'eventId': '$mockWorkspaceId/evt-uuid-999'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: mockColleagueName,
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, equals(BookingStatus.success));
      expect(result.eventId, equals('evt-uuid-999'));
      expect(result.message, contains(mockColleagueName));
    });

    test('reserveWorkspaceForColleague sends bookAsExternalOrganizer for external colleague', () async {
      final client = MockClient((req) async {
        final body = jsonDecode(req.body);
        expect(body['workspaceId'], equals(mockWorkspaceId));
        expect(body['localDate'], equals(mockDate));
        expect(body['timeSlot'], equals('FullDay'));
        expect(body['bookAsExternalOrganizer'], isNotNull);
        expect(body['bookAsExternalOrganizer']['displayName'], equals('Marie Curie'));
        expect(body['bookAsExternalOrganizer']['email'], equals('marie@curie.org'));

        return http.Response(
          jsonEncode({'eventId': 'evt-delegated-uuid-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: 'ext_colleague_123',
        colleagueName: 'Marie Curie',
        colleagueEmail: 'marie@curie.org',
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('evt-delegated-uuid-1'));
      expect(result.colleagueName, equals('Marie Curie'));
      expect(result.colleagueEmail, equals('marie@curie.org'));
    });

    test('HTTP 201 with plain id extracts eventId', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'id': 'evt-plain-888'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: mockColleagueName,
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('evt-plain-888'));
    });

    test('HTTP 409 conflict when colleague already booked returns conflictColleague', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': 'Conflict', 'message': 'User already has a reservation on this date'}),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: mockColleagueName,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals(BookingStatus.conflictColleague));
      expect(result.getLocalizedMessage(mockColleagueName), contains('a déjà une réservation'));
    });

    test('HTTP 409 conflict when desk is already occupied returns conflictDesk', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': 'Conflict', 'message': 'Workspace is already reserved by another user'}),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: mockColleagueName,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals(BookingStatus.conflictDesk));
      expect(result.getLocalizedMessage(mockColleagueName), contains('Ce bureau est déjà réservé'));
    });

    test('HTTP 400 returns invalidDate (13 days horizon limit)', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': 'BadRequest', 'message': 'Booking not permitted beyond 13 days'}),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );

      expect(result.status, equals(BookingStatus.invalidDate));
    });

    test('HTTP 401 returns unauthorized', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({'error': 'Unauthorized'}), 401);
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );

      expect(result.status, equals(BookingStatus.unauthorized));
    });

    test('HTTP 403 returns forbidden', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({'error': 'Forbidden', 'message': 'Cannot delegate'}), 403);
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );

      expect(result.status, equals(BookingStatus.forbidden));
    });

    test('Network error returns networkError without throwing', () async {
      final client = MockClient((req) async {
        throw const SocketException('Network unreachable');
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals(BookingStatus.networkError));
    });

    test('getFavorites parses JSON array correctly', () async {
      final client = MockClient((req) async {
        expect(req.url.path, equals('/users/current/favorites'));
        return http.Response(
          jsonEncode([
            {'id': 'u-1', 'name': 'Albert Einstein', 'email': 'albert@relativity.org'},
            {'id': 'u-2', 'name': 'Niels Bohr', 'email': 'niels@quantum.org'},
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final favorites = await api.getFavorites(mockToken);

      expect(favorites.length, equals(2));
      expect(favorites.first.name, equals('Albert Einstein'));
      expect(favorites.first.initials, equals('AE'));
      expect(favorites.first.isFavorite, isTrue);
    });

    test('getFavorites gracefully returns empty list on 404', () async {
      final client = MockClient((req) async {
        return http.Response(jsonEncode({'error': 'Not Found'}), 404);
      });

      final api = RoomzApiService(client: client);
      final favorites = await api.getFavorites(mockToken);
      expect(favorites, isEmpty);
    });

    test('searchColleagues parses query and returns matching users', () async {
      final client = MockClient((req) async {
        expect(req.method, equals('POST'));
        expect(req.url.path, equals('/search'));
        final body = jsonDecode(req.body);
        expect(body['text'], equals('Curie'));
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'u-3', 'name': 'Marie Curie', 'email': 'marie@radium.org'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = RoomzApiService(client: client);
      final results = await api.searchColleagues(mockToken, 'Curie');

      expect(results.length, equals(1));
      expect(results.first.name, equals('Marie Curie'));
    });

    test('searchColleagues short-circuits on empty query without HTTP call', () async {
      int callCount = 0;
      final client = MockClient((req) async {
        callCount++;
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final results = await api.searchColleagues(mockToken, '   ');

      expect(results, isEmpty);
      expect(callCount, equals(0));
    });

    test('getFavorites falls back to /favorites if /users/current/favorites fails', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/users/current/favorites') {
          return http.Response(jsonEncode({'error': 'Not found'}), 404);
        }
        if (req.url.path == '/favorites') {
          return http.Response(
            jsonEncode([
              {'id': 'u-fav-1', 'name': 'Paul Langevin', 'email': 'paul@phys.fr'}
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final favs = await api.getFavorites(mockToken);

      expect(favs.length, equals(1));
      expect(favs.first.name, equals('Paul Langevin'));
      expect(favs.first.isFavorite, isTrue);
    });

    test('getFavorites falls back to harvesting bookings if favorites endpoints are empty', () async {
      final client = MockClient((req) async {
        if (req.url.path.contains('favorites')) {
          return http.Response('[]', 200);
        }
        if (req.url.path == '/users/current/bookings') {
          return http.Response(
            jsonEncode({
              'bookings': [
                {
                  'type': 'Reserved',
                  'creator': {'id': 'my-user-id', 'name': 'Me'},
                  'organizer': {'id': 'col-1', 'name': 'Henri Becquerel', 'email': 'henri@radium.fr'},
                  'workspaceName': 'Desk B-01',
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final favs = await api.getFavorites(mockToken);

      expect(favs.length, equals(1));
      expect(favs.first.name, equals('Henri Becquerel'));
      expect(favs.first.email, equals('henri@radium.fr'));
      expect(favs.first.isFavorite, isTrue);
    });

    test('searchColleagues falls back to harvested directory if /search returns 403', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/search') {
          return http.Response(jsonEncode({'error': 'Forbidden'}), 403);
        }
        if (req.url.path == '/users/current/bookings') {
          return http.Response(
            jsonEncode({
              'bookings': [
                {
                  'type': 'Reserved',
                  'creator': {'id': 'my-user-id', 'name': 'Me'},
                  'organizer': {'id': 'col-2', 'name': 'Pierre Curie', 'email': 'pierre@radium.fr'},
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final results = await api.searchColleagues(mockToken, 'Pierre');

      expect(results.length, equals(1));
      expect(results.first.name, equals('Pierre Curie'));
      expect(results.first.email, equals('pierre@radium.fr'));
    });
  });

  // =========================================================================
  // 5. ColleagueSelectionDialog Widget Tests
  // =========================================================================
  group('5. ColleagueSelectionDialog Widget Tests', () {
    testWidgets('Displays header, date, desk name, and empty state', (tester) async {
      SharedPreferences.setMockInitialValues({'favorite_colleagues': '[]'});

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(
              date: '2026-10-15',
              deskName: 'DS-BORD-1-18-D',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Réserver pour un collègue'), findsOneWidget);
      expect(find.text('2026-10-15 • DS-BORD-1-18-D'), findsOneWidget);
      expect(find.text('Aucun collègue favori'), findsOneWidget);
    });

    testWidgets('Displays favorite colleagues with avatar initials and star', (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([
          {'id': 'u-1', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true},
          {'id': 'u-2', 'name': 'Albert Einstein', 'email': 'albert@relativity.org', 'isFavorite': true},
        ]),
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(date: '2026-10-15'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('MC'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsOneWidget);
      expect(find.text('AE'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
    });

    testWidgets('Instant search filtering on typed query', (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([
          {'id': 'u-1', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true},
          {'id': 'u-2', 'name': 'Albert Einstein', 'email': 'albert@relativity.org', 'isFavorite': true},
        ]),
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(date: '2026-10-15'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Curie');
      await tester.pump();

      expect(find.text('Marie Curie'), findsOneWidget);
      expect(find.text('Albert Einstein'), findsNothing);
    });

    testWidgets('Tapping colleague row opens confirmation dialog and confirms selection', (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([
          {'id': 'u-1', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true},
        ]),
      });

      Colleague? selectedColleague;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(
              date: '2026-10-15',
              deskName: 'DS-BORD-1-18-D',
              onColleagueSelected: (c) => selectedColleague = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Marie Curie'));
      await tester.pumpAndSettle();

      expect(find.text('Confirmer la réservation'), findsOneWidget);
      expect(find.text('Date : 2026-10-15'), findsOneWidget);
      expect(find.text('Bureau : DS-BORD-1-18-D'), findsOneWidget);

      await tester.tap(find.text('CONFIRMER'));
      await tester.pumpAndSettle();

      expect(selectedColleague?.name, equals('Marie Curie'));
    });

    testWidgets('Toggling star updates favorites persistence in StorageService', (tester) async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([
          {'id': 'u-1', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true},
        ]),
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(date: '2026-10-15'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the star button to unstar
      await tester.tap(find.byIcon(Icons.star_rounded));
      await tester.pumpAndSettle();

      final storage = StorageService();
      final favs = await storage.getFavoriteColleagues();
      expect(favs, isEmpty);
      expect(find.text('Marie Curie'), findsNothing);
      expect(find.text('Aucun collègue favori'), findsOneWidget);
    });

    testWidgets('Initial loading queries remote favorites and updates UI', (tester) async {
      SharedPreferences.setMockInitialValues({'favorite_colleagues': '[]', 'refresh_token': 'test_token'});
      final client = MockClient((req) async {
        if (req.url.path.contains('token')) {
          return http.Response(
            jsonEncode({'access_token': 'test_access', 'refresh_token': 'test_refresh'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (req.url.path.contains('favorites')) {
          return http.Response(
            jsonEncode([
              {'id': 'u-remote-1', 'name': 'Rosalind Franklin', 'email': 'rosalind@dna.org', 'isFavorite': true}
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(
              date: '2026-10-15',
              apiService: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rosalind Franklin'), findsOneWidget);
      expect(find.text('RF'), findsOneWidget);
    });

    testWidgets('Nouveau collègue button opens form with Name and Email validation', (tester) async {
      SharedPreferences.setMockInitialValues({'favorite_colleagues': '[]'});

      Colleague? selectedColleague;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(
              date: '2026-10-15',
              deskName: 'Desk 42',
              onColleagueSelected: (c) => selectedColleague = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the "Nouveau collègue (hors liste)" button
      final newColleagueBtn = find.text('Nouveau collègue (hors liste)');
      expect(newColleagueBtn, findsOneWidget);
      await tester.tap(newColleagueBtn);
      await tester.pumpAndSettle();

      expect(find.text('Nouveau collègue'), findsOneWidget);
      expect(find.text('Nom et prénom *'), findsOneWidget);
      expect(find.text('Adresse email *'), findsOneWidget);

      // Tap CONTINUER without entering anything -> validation error
      await tester.tap(find.text('CONTINUER'));
      await tester.pumpAndSettle();

      expect(find.text('Veuillez saisir un nom'), findsOneWidget);

      // Enter name but invalid email
      final textFields = find.byType(TextFormField);
      await tester.enterText(textFields.first, 'Ada Lovelace');
      await tester.enterText(textFields.last, 'not-an-email');
      await tester.tap(find.text('CONTINUER'));
      await tester.pumpAndSettle();

      expect(find.text('Veuillez saisir une adresse email valide'), findsOneWidget);

      // Enter valid email
      await tester.enterText(textFields.last, 'ada.lovelace@algorithm.org');
      await tester.tap(find.text('CONTINUER'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear with both name and email!
      expect(find.text('Confirmer la réservation'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Ada Lovelace')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('ada.lovelace@algorithm.org')),
        findsOneWidget,
      );
      expect(find.text('Bureau : Desk 42'), findsOneWidget);

      // Confirm
      await tester.tap(find.text('CONFIRMER'));
      await tester.pumpAndSettle();

      expect(selectedColleague?.name, equals('Ada Lovelace'));
      expect(selectedColleague?.email, equals('ada.lovelace@algorithm.org'));
    });
  });

  // =========================================================================
  // 6. HomeScreen Day Tap Colleague Reservation Option Integration
  // =========================================================================
  group('6. HomeScreen Integration Tests', () {
    testWidgets('Future available day tap presents "Réserver pour un collègue" action', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      // Pick a weekday 2 to 5 days in the future
      DateTime targetDay = now.add(const Duration(days: 2));
      while (targetDay.weekday == DateTime.saturday || targetDay.weekday == DateTime.sunday) {
        targetDay = targetDay.add(const Duration(days: 1));
      }
      final targetDayNum = '${targetDay.day}';

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'DS-BORD-1-18-D',
        'workspace_id': 'ws-101',
        'initial_tab': 1,
        'show_all_reservations': true,
        'show_delegated_reservations': true,
        'hide_weekends': false,
      });

      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // Navigate to Calendar tab if not already on it
      final calTabFinder = find.text('Calendrier');
      if (calTabFinder.evaluate().isNotEmpty) {
        await tester.tap(calTabFinder);
        await tester.pumpAndSettle();
      }

      final dayFinder = find.text(targetDayNum).first;
      await tester.tap(dayFinder);
      await tester.pumpAndSettle();

      expect(find.text('Réserver pour un collègue'), findsOneWidget);
      expect(find.byIcon(Icons.group_add_outlined), findsOneWidget);
    });
  });
}
