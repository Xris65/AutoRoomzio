import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/models/booking_result.dart';
import 'package:auto_roomzio/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String mockToken = 'jwt-sample-token-xyz';
  const String mockWorkspaceId = 'ws-guid-1234';
  const String mockColleagueId = 'usr-guid-5678';
  const String mockDate = '2026-10-20';

  group('Adversarial Challenge 1: Payload Structure & Headers', () {
    test('reserveWorkspaceForColleague posts correct payload and headers', () async {
      http.Request? capturedRequest;
      Map<String, dynamic>? capturedBody;

      final client = MockClient((req) async {
        capturedRequest = req;
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'evt-001'}),
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
        colleagueName: 'Éléonore François-Xavier',
      );

      expect(result.isSuccess, isTrue);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.method, equals('POST'));
      expect(capturedRequest!.url.toString(), equals('https://api.my.roomz.io/bookings'));
      expect(capturedRequest!.headers['authorization'], equals('Bearer $mockToken'));
      expect(capturedRequest!.headers['content-type'], contains('application/json'));
      expect(capturedRequest!.headers['accept'], contains('application/json'));
      expect(capturedRequest!.headers['origin'], equals('https://my.roomz.io'));
      expect(capturedRequest!.headers['referer'], equals('https://my.roomz.io/'));
      expect(capturedRequest!.headers['roomz-source-type'], equals('1'));
      expect(capturedRequest!.headers['x-roomz-source-type'], equals('1'));

      // Validate payload content (Requirement Bug 3 Fix: ensure third-party attribution via bookAsUserId)
      expect(capturedBody, isNotNull);
      expect(capturedBody!['workspaceId'], equals(mockWorkspaceId));
      expect(capturedBody!['localDate'], equals(mockDate));
      expect(capturedBody!['timeSlot'], equals('FullDay'));
      expect(capturedBody!['bookAsUserId'], equals(mockColleagueId));
    });

    test('reserveWorkspaceForColleague with name and email injects complete beneficiary metadata for third-party attribution', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((req) async {
        capturedBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'evt-003'}), 200, headers: {'content-type': 'application/json'});
      });

      final api = RoomzApiService(client: client);
      final result = await api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: 'ext_colleague_123',
        colleagueName: 'Louis Pasteur',
        colleagueEmail: 'pasteur@microbes.fr',
      );

      expect(result.isSuccess, isTrue);
      expect(capturedBody, isNotNull);
      expect(capturedBody!['bookAsExternalOrganizer'], isNotNull);
      expect(capturedBody!['bookAsExternalOrganizer']['displayName'], equals('Louis Pasteur'));
      expect(capturedBody!['bookAsExternalOrganizer']['email'], equals('pasteur@microbes.fr'));
    });

    test('reserveWorkspaceForColleague with null colleagueName handles message appropriately', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'id': 'evt-002'}),
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
        colleagueName: null,
      );

      expect(result.isSuccess, isTrue);
      expect(result.colleagueName, isNull);
      expect(result.message, equals('Bureau réservé avec succès !'));
    });
  });

  group('Adversarial Challenge 2: Response Parsing on 200/201 (Raw UUID, WS/UUID, Nested)', () {
    test('Parses raw UUID in eventId', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'eventId': '3fa85f64-5717-4562-b3fc-2c963f66afa6'}),
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
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('3fa85f64-5717-4562-b3fc-2c963f66afa6'));
    });

    test('Parses workspaceId/UUID compound format in eventId', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'eventId': 'ws-guid-1234/3fa85f64-5717-4562-b3fc-2c963f66afa6'}),
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
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('3fa85f64-5717-4562-b3fc-2c963f66afa6'));
    });

    test('Parses workspaceId/UUID format in id property', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'id': 'ws-guid-1234/custom-event-uuid-88'}),
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
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('custom-event-uuid-88'));
    });

    test('Parses bookingId property', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'bookingId': 'bk-777'}),
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
      );

      expect(result.isSuccess, isTrue);
      expect(result.eventId, equals('bk-777'));
    });

    test('Parses nested data.eventId and data.id properties', () async {
      final clientNested = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'data': {'eventId': 'ws-1/nested-ev-11'}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiNested = RoomzApiService(client: clientNested);
      final resNested = await apiNested.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(resNested.eventId, equals('nested-ev-11'));

      final clientNestedId = MockClient((req) async {
        return http.Response(
          jsonEncode({
            'data': {'id': 'ws-1/nested-id-22'}
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiNestedId = RoomzApiService(client: clientNestedId);
      final resNestedId = await apiNestedId.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(resNestedId.eventId, equals('nested-id-22'));
    });

    test('Handles empty JSON object, empty body, and non-JSON body gracefully without throwing', () async {
      final clientEmptyJson = MockClient((req) async => http.Response('{}', 200));
      final resEmptyJson = await RoomzApiService(client: clientEmptyJson).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(resEmptyJson.isSuccess, isTrue);
      expect(resEmptyJson.eventId, isNull);

      final clientEmptyBody = MockClient((req) async => http.Response('', 200));
      final resEmptyBody = await RoomzApiService(client: clientEmptyBody).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(resEmptyBody.isSuccess, isTrue);
      expect(resEmptyBody.eventId, isNull);

      final clientHtmlBody = MockClient((req) async => http.Response('<html><body>OK</body></html>', 200));
      final resHtmlBody = await RoomzApiService(client: clientHtmlBody).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(resHtmlBody.isSuccess, isTrue);
      expect(resHtmlBody.eventId, isNull);
    });
  });

  group('Adversarial Challenge 3: HTTP 409 Conflict Discrimination Matrix', () {
    Future<BookingResult> runConflictTest(String responseBody, [String? colleagueName]) async {
      final client = MockClient((req) async {
        return http.Response(responseBody, 409, headers: {'content-type': 'application/json'});
      });
      final api = RoomzApiService(client: client);
      return api.reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: colleagueName ?? 'Sophie',
      );
    }

    test('Detects colleague conflict on "already has a reservation"', () async {
      final res = await runConflictTest('{"error": "User already has a reservation on this date"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
      expect(res.isConflictColleague, isTrue);
      expect(res.isConflictDesk, isFalse);
      expect(res.getLocalizedMessage('Sophie'), equals('Sophie a déjà une réservation ce jour-là.'));
    });

    test('Detects colleague conflict on "already has a booking"', () async {
      final res = await runConflictTest('{"message": "Colleague already has a booking for the chosen period"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
    });

    test('Detects colleague conflict on "déjà une réservation" (French API message)', () async {
      final res = await runConflictTest('{"message": "L\'utilisateur a déjà une réservation active"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
    });

    test('Detects colleague conflict on "user_already_booked" error code', () async {
      final res = await runConflictTest('{"code": "USER_ALREADY_BOOKED"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
    });

    test('Detects colleague conflict on "colleague_already_booked" error code', () async {
      final res = await runConflictTest('{"code": "COLLEAGUE_ALREADY_BOOKED"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
    });

    test('Detects colleague conflict on "Cet utilisateur a un autre créneau" (user keyword without desk)', () async {
      final res = await runConflictTest('{"detail": "Cet utilisateur a déjà un créneau enregistré"}');
      expect(res.status, equals(BookingStatus.conflictColleague));
    });

    test('Detects colleague conflict without colleagueName returns generic French message', () async {
      final client = MockClient((req) async => http.Response('{"code": "USER_ALREADY_BOOKED"}', 409));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
        colleagueName: null,
      );
      expect(res.status, equals(BookingStatus.conflictColleague));
      expect(res.message, equals('Ce collègue a déjà une réservation ce jour-là.'));
    });

    test('Detects desk conflict on "Workspace is already reserved by another user" (both desk & user keywords)', () async {
      final res = await runConflictTest('{"error": "Workspace is already reserved by another user"}');
      expect(res.status, equals(BookingStatus.conflictDesk));
      expect(res.isConflictDesk, isTrue);
      expect(res.isConflictColleague, isFalse);
      expect(res.getLocalizedMessage('Sophie'), equals('Ce bureau est déjà réservé par quelqu\'un d\'autre.'));
    });

    test('Detects desk conflict on "Desk occupied"', () async {
      final res = await runConflictTest('{"error": "Desk occupied"}');
      expect(res.status, equals(BookingStatus.conflictDesk));
    });

    test('Detects desk conflict on "Ce bureau est déjà réservé"', () async {
      final res = await runConflictTest('{"message": "Ce bureau est déjà réservé pour la journée"}');
      expect(res.status, equals(BookingStatus.conflictDesk));
    });

    test('Detects desk conflict on "Seat taken"', () async {
      final res = await runConflictTest('{"detail": "Seat taken for 2026-10-20"}');
      expect(res.status, equals(BookingStatus.conflictDesk));
    });

    test('Defaults unknown 409 conflict to conflictDesk', () async {
      final res = await runConflictTest('{"error": "Conflict", "status": 409}');
      expect(res.status, equals(BookingStatus.conflictDesk));
    });
  });

  group('Adversarial Challenge 4: HTTP 400 Horizon Limit, Auth, Server Errors', () {
    test('HTTP 400 maps to invalidDate with 13-day limit message', () async {
      final client = MockClient((req) async => http.Response('{"error": "Out of horizon"}', 400));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.status, equals(BookingStatus.invalidDate));
      expect(res.message, contains('13 jours'));
    });

    test('HTTP 401 maps to unauthorized with session expired message', () async {
      final client = MockClient((req) async => http.Response('{"error": "Unauthorized"}', 401));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.status, equals(BookingStatus.unauthorized));
      expect(res.message, contains('Session expirée'));
    });

    test('HTTP 403 maps to forbidden with lack of delegation permission message', () async {
      final client = MockClient((req) async => http.Response('{"error": "Forbidden"}', 403));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.status, equals(BookingStatus.forbidden));
      expect(res.message, contains('droits pour réserver pour un tiers'));
    });

    test('HTTP 500, 502, 503 map to serverError with status code in message', () async {
      for (final code in [500, 502, 503]) {
        final client = MockClient((req) async => http.Response('Server error', code));
        final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
          date: mockDate,
          token: mockToken,
          workspaceId: mockWorkspaceId,
          colleagueId: mockColleagueId,
        );
        expect(res.status, equals(BookingStatus.serverError));
        expect(res.message, contains('($code)'));
      }
    });

    test('Unexpected HTTP 418 code maps to serverError with body snippet', () async {
      final client = MockClient((req) async => http.Response('I am a teapot', 418));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.status, equals(BookingStatus.serverError));
      expect(res.message, contains('418'));
      expect(res.message, contains('I am a teapot'));
    });
  });

  group('Adversarial Challenge 5: Network Dropouts & Connectivity Failures', () {
    test('SocketException maps to networkError without throwing', () async {
      final client = MockClient((req) async => throw const SocketException('Network unreachable'));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.isSuccess, isFalse);
      expect(res.status, equals(BookingStatus.networkError));
      expect(res.message, contains('réseau inaccessible'));
    });

    test('HttpException maps to networkError without throwing', () async {
      final client = MockClient((req) async => throw const HttpException('Connection closed prematurely'));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.isSuccess, isFalse);
      expect(res.status, equals(BookingStatus.networkError));
      expect(res.message, contains('Erreur de connexion'));
    });

    test('TimeoutException maps to networkError without throwing', () async {
      final client = MockClient((req) async => throw TimeoutException('Connection timed out'));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.isSuccess, isFalse);
      expect(res.status, equals(BookingStatus.networkError));
      expect(res.message, contains('Erreur de connexion'));
    });

    test('http.ClientException maps to networkError without throwing', () async {
      final client = MockClient((req) async => throw http.ClientException('Connection reset'));
      final res = await RoomzApiService(client: client).reserveWorkspaceForColleague(
        date: mockDate,
        token: mockToken,
        workspaceId: mockWorkspaceId,
        colleagueId: mockColleagueId,
      );
      expect(res.isSuccess, isFalse);
      expect(res.status, equals(BookingStatus.networkError));
      expect(res.message, contains('Erreur de connexion'));
    });
  });

  group('Adversarial Challenge 6: Backward Compatibility Verification', () {
    test('RoomzApiService default parameterless constructor instantiates successfully', () {
      final defaultApi = RoomzApiService();
      expect(defaultApi, isNotNull);
    });

    test('RoomzApiService constructor with only StorageService works', () {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      final api = RoomzApiService(storage: storage);
      expect(api, isNotNull);
    });

    test('cancelReservation accepts optional forUserId and includes it in fallback payload', () async {
      Map<String, dynamic>? deletePayload;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.contains('/users/current/bookings')) {
          // Return no bookings in list, so it falls back to body-based DELETE
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.method == 'DELETE' && req.url.path == '/bookings') {
          deletePayload = jsonDecode(req.body);
          return http.Response('', 200);
        }
        return http.Response('', 404);
      });

      SharedPreferences.setMockInitialValues({});
      final api = RoomzApiService();

      final success = await http.runWithClient(() async {
        return await api.cancelReservation(
          mockDate,
          mockToken,
          mockWorkspaceId,
          forUserId: mockColleagueId,
        );
      }, () => client);

      expect(success, isTrue);
      expect(deletePayload, isNotNull);
      expect(deletePayload!['workspaceId'], equals(mockWorkspaceId));
      expect(deletePayload!['localDate'], equals(mockDate));
      expect(deletePayload!['timeSlot'], equals('FullDay'));
      expect(deletePayload!['forUserId'], equals(mockColleagueId));
    });

    test('cancelReservation without optional forUserId or eventId still functions (legacy call)', () async {
      Map<String, dynamic>? deletePayload;
      final client = MockClient((req) async {
        if (req.method == 'GET' && req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.method == 'DELETE' && req.url.path == '/bookings') {
          deletePayload = jsonDecode(req.body);
          return http.Response('', 200);
        }
        return http.Response('', 404);
      });

      final api = RoomzApiService();
      final success = await http.runWithClient(() async {
        return await api.cancelReservation(mockDate, mockToken, mockWorkspaceId);
      }, () => client);

      expect(success, isTrue);
      expect(deletePayload, isNotNull);
      expect(deletePayload!.containsKey('forUserId'), isFalse);
    });
  });

  group('Adversarial Challenge 7: Directory Search & Favorites Parsing Resilience', () {
    test('getFavorites parses diverse response JSON wrappers', () async {
      // Wrapper 1: { data: [...] }
      final c1 = MockClient((req) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'u1', 'name': 'Marie Curie', 'email': 'm@c.fr'}
              ]
            }),
            200,
          ));
      final res1 = await RoomzApiService(client: c1).getFavorites(mockToken);
      expect(res1.length, equals(1));
      expect(res1.first.name, equals('Marie Curie'));
      expect(res1.first.isFavorite, isTrue);

      // Wrapper 2: { users: [...] }
      final c2 = MockClient((req) async => http.Response(
            jsonEncode({
              'users': [
                {'id': 'u2', 'name': 'Blaise Pascal', 'email': 'b@p.fr'}
              ]
            }),
            200,
          ));
      final res2 = await RoomzApiService(client: c2).getFavorites(mockToken);
      expect(res2.length, equals(1));
      expect(res2.first.name, equals('Blaise Pascal'));

      // Wrapper 3: { items: [...] }
      final c3 = MockClient((req) async => http.Response(
            jsonEncode({
              'items': [
                {'id': 'u3', 'name': 'René Descartes', 'email': 'r@d.fr'}
              ]
            }),
            200,
          ));
      final res3 = await RoomzApiService(client: c3).getFavorites(mockToken);
      expect(res3.length, equals(1));
      expect(res3.first.name, equals('René Descartes'));
    });

    test('getFavorites survives 500 error and returns empty list', () async {
      final client = MockClient((req) async => http.Response('Server error', 500));
      final res = await RoomzApiService(client: client).getFavorites(mockToken);
      expect(res, isEmpty);
    });

    test('getFavorites survives SocketException and returns empty list', () async {
      final client = MockClient((req) async => throw const SocketException('DNS failed'));
      final res = await RoomzApiService(client: client).getFavorites(mockToken);
      expect(res, isEmpty);
    });

    test('searchColleagues posts search text body with special characters and accents', () async {
      String? queriedUrl;
      Map<String, dynamic>? capturedBody;
      final client = MockClient((req) async {
        expect(req.method, equals('POST'));
        queriedUrl = req.url.toString();
        capturedBody = jsonDecode(req.body);
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'u9', 'name': 'Élise & Paul', 'email': 'ep@c.fr'}
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final res = await RoomzApiService(client: client).searchColleagues(mockToken, 'Élise & Paul');
      expect(res.length, equals(1));
      expect(queriedUrl, isNotNull);
      expect(queriedUrl, contains('/search'));
      expect(capturedBody, isNotNull);
      expect(capturedBody!['text'], equals('Élise & Paul'));
    });

    test('searchColleagues survives SocketException and returns empty list', () async {
      final client = MockClient((req) async => throw const SocketException('Network offline'));
      final res = await RoomzApiService(client: client).searchColleagues(mockToken, 'Curie');
      expect(res, isEmpty);
    });
  });
}
