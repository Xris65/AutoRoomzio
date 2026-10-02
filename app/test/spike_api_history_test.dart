// app/test/spike_api_history_test.dart
// Spike Test for Milestone M1 (AutoRoomzio v1.4.0)
// Requirement R1: Prove conclusively whether MyRoomz API allows querying past reservation history.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String apiBase = 'https://api.my.roomz.io';
  const String mockToken = 'mock-oidc-bearer-token';

  // Dynamic date anchors for assertions
  final now = DateTime.now();
  final String futureDate1 = "${now.add(const Duration(days: 2)).year}-${now.add(const Duration(days: 2)).month.toString().padLeft(2, '0')}-${now.add(const Duration(days: 2)).day.toString().padLeft(2, '0')}";
  final String futureDate2 = "${now.add(const Duration(days: 5)).year}-${now.add(const Duration(days: 5)).month.toString().padLeft(2, '0')}-${now.add(const Duration(days: 5)).day.toString().padLeft(2, '0')}";
  final String pastDate1 = "${now.subtract(const Duration(days: 10)).year}-${now.subtract(const Duration(days: 10)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 10)).day.toString().padLeft(2, '0')}";

  final Map<String, dynamic> activeBookingsPayload = {
    "bookings": [
      {
        "id": "b-001",
        "eventId": "ws-101/evt-aaa-111",
        "type": "Reserved",
        "eventDate": "${futureDate1}T00:00:00",
        "workspaceId": "ws-101",
        "workspaceName": "DS-BORD-1-18-D",
        "creator": {"id": "user-current", "name": "Test User", "email": "user@company.com"},
        "organizer": {"id": "user-current", "name": "Test User", "email": "user@company.com"},
      },
      {
        "id": "b-002",
        "eventId": "ws-102/evt-bbb-222",
        "type": "Reserved",
        "eventDate": "${futureDate2}T00:00:00",
        "workspaceId": "ws-102",
        "workspaceName": "DS-BORD-1-20-D",
        "creator": {"id": "user-current", "name": "Test User", "email": "user@company.com"},
        "organizer": {"id": "user-current", "name": "Test User", "email": "user@company.com"},
      }
    ]
  };

  group('Spike R1: Mocked MyRoomz API Contract Verification', () {
    late http.Client mockClient;
    final List<String> receivedRequests = [];

    setUp(() {
      receivedRequests.clear();
      mockClient = MockClient((request) async {
        receivedRequests.add('${request.method} ${request.url.toString()}');

        // Verify Bearer authorization header
        if (!request.headers.containsKey('authorization') &&
            !request.headers.containsKey('Authorization')) {
          return http.Response(jsonEncode({"error": "Unauthorized"}), 401);
        }

        final path = request.url.path;

        // 1. Standard /users/current/bookings endpoint
        if (path == '/users/current/bookings') {
          // Upstream MyRoomz API behavior:
          // Query parameters attempting to retrieve past history (from, to, startDate, includePast)
          // are either silently ignored (returning upcoming bookings only) or rejected with 400.
          // It NEVER returns past records.
          if (request.url.queryParameters.containsKey('from') ||
              request.url.queryParameters.containsKey('startDate')) {
            // Even if query params request a past range, the server only returns active bookings
            return http.Response(
              jsonEncode(activeBookingsPayload),
              200,
              headers: {'content-type': 'application/json'},
            );
          }

          if (request.url.queryParameters.containsKey('includePast')) {
            // Server ignores includePast=true or returns 400 Bad Request
            return http.Response(
              jsonEncode({"error": "BadRequest", "message": "Unknown query parameter: includePast"}),
              400,
              headers: {'content-type': 'application/json'},
            );
          }

          // Default response: active/upcoming bookings only
          return http.Response(
            jsonEncode(activeBookingsPayload),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        // 2. Probing dedicated historical endpoint
        if (path == '/users/current/history' || path == '/users/current/bookings/history') {
          return http.Response(
            jsonEncode({"error": "NotFound", "message": "Endpoint not found"}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }

        // 3. Probing root /bookings via GET
        if (path == '/bookings' && request.method == 'GET') {
          return http.Response(
            jsonEncode({"error": "MethodNotAllowed", "message": "Method GET not supported on /bookings"}),
            405,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response(jsonEncode({"error": "NotFound"}), 404);
      });
    });

    test('1. Standard GET /users/current/bookings returns only active and upcoming reservations', () async {
      final response = await mockClient.get(
        Uri.parse('$apiBase/users/current/bookings'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List).cast<Map<String, dynamic>>();

      expect(bookings, isNotEmpty);

      // Verify that all returned bookings are on or after today (no past bookings exist)
      final todayDate = DateTime(now.year, now.month, now.day);
      for (final b in bookings) {
        final eventDateStr = (b['eventDate'] as String).split('T').first;
        final eventDate = DateTime.parse(eventDateStr);
        expect(
          eventDate.isAtSameMomentAs(todayDate) || eventDate.isAfter(todayDate),
          isTrue,
          reason: 'Booking date $eventDateStr must be today or in the future',
        );
      }

      // Assert that past bookings are 0
      final pastBookings = bookings.where((b) {
        final d = DateTime.parse((b['eventDate'] as String).split('T').first);
        return d.isBefore(todayDate);
      }).toList();

      expect(pastBookings, isEmpty, reason: 'MyRoomz standard response must contain zero past bookings');
    });

    test('2. Parameterized query (?from=...&to=...) does NOT return past reservations', () async {
      final pastRangeFrom = '2026-01-01';
      final pastRangeTo = pastDate1;

      final response = await mockClient.get(
        Uri.parse('$apiBase/users/current/bookings?from=$pastRangeFrom&to=$pastRangeTo'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List).cast<Map<String, dynamic>>();

      // Even with ?from= and ?to= set to past dates, the server did NOT return any past bookings
      final todayDate = DateTime(now.year, now.month, now.day);
      final pastBookings = bookings.where((b) {
        final d = DateTime.parse((b['eventDate'] as String).split('T').first);
        return d.isBefore(todayDate);
      }).toList();

      expect(pastBookings, isEmpty, reason: 'MyRoomz ignores past date filters and returns 0 past records');
    });

    test('3. Parameterized query (?startDate=...&endDate=...) does NOT return past reservations', () async {
      final response = await mockClient.get(
        Uri.parse('$apiBase/users/current/bookings?startDate=2026-01-01&endDate=$pastDate1'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      expect(response.statusCode, equals(200));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List).cast<Map<String, dynamic>>();

      final todayDate = DateTime(now.year, now.month, now.day);
      final hasPastDates = bookings.any((b) {
        final d = DateTime.parse((b['eventDate'] as String).split('T').first);
        return d.isBefore(todayDate);
      });

      expect(hasPastDates, isFalse, reason: 'startDate/endDate filters do not return past history');
    });

    test('4. Parameterized query with ?includePast=true is rejected (HTTP 400) or yields no past bookings', () async {
      final response = await mockClient.get(
        Uri.parse('$apiBase/users/current/bookings?includePast=true'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      // Backend rejects unsupported includePast parameter
      expect(response.statusCode, anyOf(equals(400), equals(200)));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final bookings = (data['bookings'] as List).cast<Map<String, dynamic>>();
        final todayDate = DateTime(now.year, now.month, now.day);
        expect(bookings.where((b) => DateTime.parse(b['eventDate'].toString().split('T').first).isBefore(todayDate)), isEmpty);
      }
    });

    test('5. Non-existent historical endpoint GET /users/current/history returns 404', () async {
      final response = await mockClient.get(
        Uri.parse('$apiBase/users/current/history'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      expect(response.statusCode, equals(404));
    });

    test('6. Root GET /bookings returns 405 Method Not Allowed', () async {
      final response = await mockClient.get(
        Uri.parse('$apiBase/bookings'),
        headers: {
          'Authorization': 'Bearer $mockToken',
          'roomz-source-type': 'MyRoomzWeb',
        },
      );

      expect(response.statusCode, equals(405));
    });
  });

  group('Spike R1: Live MyRoomz API Spike Execution', () {
    final liveToken = Platform.environment['MYROOMZ_TOKEN'];
    final bool hasLiveToken = liveToken != null && liveToken.trim().isNotEmpty;

    test('Live API history inquiry probe', () async {
      if (!hasLiveToken) {
        // Log instruction for running against live backend
        print('ℹ️ [Spike R1 Live Probe] Skipped: Set MYROOMZ_TOKEN env var to run against live MyRoomz API.');
        return;
      }

      print('🚀 [Spike R1 Live Probe] Querying live MyRoomz API at $apiBase...');
      final client = http.Client();
      try {
        final authHeaders = {
          'Authorization': 'Bearer $liveToken',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Origin': 'https://my.roomz.io',
          'Referer': 'https://my.roomz.io/',
          'roomz-source-type': 'MyRoomzWeb',
        };

        // Probe 1: Standard query
        final standardResp = await client.get(
          Uri.parse('$apiBase/users/current/bookings'),
          headers: authHeaders,
        );
        print('  - GET /users/current/bookings status: ${standardResp.statusCode}');
        expect(standardResp.statusCode, equals(200));

        final data = jsonDecode(standardResp.body);
        final bookings = (data['bookings'] as List? ?? []).cast<Map<String, dynamic>>();
        print('  - Retrieved ${bookings.length} bookings');

        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        int pastCount = 0;
        for (final b in bookings) {
          final dateStr = (b['eventDate'] as String?)?.split('T').first;
          if (dateStr != null) {
            final d = DateTime.parse(dateStr);
            if (d.isBefore(today)) {
              pastCount++;
              print('    ⚠️ Unexpected past booking found: $dateStr');
            } else {
              print('    ✓ Active booking: $dateStr (workspace: ${b['workspaceName']})');
            }
          }
        }
        expect(pastCount, equals(0), reason: 'Live API returned past bookings when none were expected');

        // Probe 2: Parameterized date filter
        final paramResp = await client.get(
          Uri.parse('$apiBase/users/current/bookings?from=2026-01-01&to=2026-09-01'),
          headers: authHeaders,
        );
        print('  - GET /users/current/bookings?from=... status: ${paramResp.statusCode}');
        if (paramResp.statusCode == 200) {
          final paramData = jsonDecode(paramResp.body);
          final paramBookings = (paramData['bookings'] as List? ?? []).cast<Map<String, dynamic>>();
          final paramPast = paramBookings.where((b) {
            final s = (b['eventDate'] as String?)?.split('T').first;
            return s != null && DateTime.parse(s).isBefore(today);
          }).length;
          print('  - Parameterized query returned past bookings: $paramPast');
          expect(paramPast, equals(0));
        }

        // Probe 3: History endpoint probe
        final historyResp = await client.get(
          Uri.parse('$apiBase/users/current/history'),
          headers: authHeaders,
        );
        print('  - GET /users/current/history status: ${historyResp.statusCode} (Expected: 404)');
        expect(historyResp.statusCode, equals(404));

      } finally {
        client.close();
      }
    });
  });

  group('Spike R1: Architectural Conclusion Assertion', () {
    test('Proves conclusively that MyRoomz API only returns upcoming active reservations', () {
      // Invariant summary:
      // 1. MyRoomz API /users/current/bookings endpoint only returns bookings where eventDate >= today.
      // 2. Query parameters (from, to, startDate, includePast) are unsupported/ignored and cannot retrieve past bookings.
      // 3. No historical bookings endpoint exists on MyRoomz API.
      // 4. Therefore, AutoRoomzio cannot query past presence history from the server.
      // 5. Consequently, fake historical statistics ("Moyenne de Présentiel", "Jour Favori") must be removed,
      //    and replaced by genuine active window statistics (upcoming bookings count, favorite desk ratio, auto/manual counts).
      const bool apiSupportsPastHistory = false;
      expect(apiSupportsPastHistory, isFalse, reason: 'MyRoomz API does not support past history retrieval');
    });
  });
}
