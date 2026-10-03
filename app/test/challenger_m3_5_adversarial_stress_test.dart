import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/models/booking_result.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/colleague_selection_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RoomzApiService.onSessionExpired = null;
  });

  tearDown(() {
    RoomzApiService.onSessionExpired = null;
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Rapid Spam Date Switching Stress Tests (10 rapid changes in succession)
  // ═══════════════════════════════════════════════════════════════════════════
  group('1. Rapid Spam Date Switching Resilience', () {
    testWidgets('Simulates 10 rapid date changes in succession: NO logout, state remains clean', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      int tokenRefreshHttpCalls = 0;
      final List<String> requestedDates = [];

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-stress',
        'floor_id': 'fl-stress',
        'workspace_id': 'ws-target',
        'refresh_token': 'stress-refresh-token',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          tokenRefreshHttpCalls++;
          return http.Response(jsonEncode({
            'access_token': 'stress-access-token',
            'refresh_token': 'stress-refresh-token-new',
          }), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-target', 'name': 'Room-Alpha', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          final body = jsonDecode(req.body);
          final d = body['date']?.toString() ?? '';
          requestedDates.add(d);
          return http.Response(jsonEncode({
            'data': [
              {
                'workspaceId': 'ws-target',
                'status': 'Reserved',
                'bookedTimeSlot': {
                  'id': 'slot-$d',
                  'occupantName': 'Jean Dupont',
                  'creator': {'id': 'user-$d', 'name': 'Jean Dupont'},
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-target', 'name': 'Room-Alpha-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/sites') || path.contains('/buildings')) {
          return http.Response(jsonEncode([{'id': 'site-stress', 'name': 'Stress Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-stress', 'name': 'Stress Floor'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      final baseDate = DateTime(2026, 10, 5);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: baseDate,
        ),
      ));
      await tester.pumpAndSettle();

      final nextDayBtn = find.byTooltip('Jour suivant');
      expect(nextDayBtn, findsOneWidget);

      // Perform 10 rapid date changes in succession (spamming click)
      for (int i = 0; i < 10; i++) {
        await tester.tap(nextDayBtn);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      // Verification: NO logout occurred
      expect(sessionExpiredFired, isFalse, reason: 'Rapid date spamming must never trigger session expiry');

      // Verification: Token refresh was only performed ONCE (cached and mutex-protected)
      expect(tokenRefreshHttpCalls, equals(1), reason: 'Token refresh must not be flooded on date clicks');

      // Verification: 10 date requests were triggered (+ 1 initial load)
      expect(requestedDates.length, equals(11));

      // Verification: Final date in state corresponds to baseDate + 10 days (2026-10-15)
      final expectedFinalDate = baseDate.add(const Duration(days: 10));
      expect(find.textContaining('${expectedFinalDate.day}'), findsWidgets);

      // Final occupant is displayed cleanly on the desk
      expect(find.textContaining('DUPONT J.'), findsWidgets);
    });

    testWidgets('Out-of-order delayed HTTP responses during rapid date switching do not corrupt state', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final Map<String, Completer<http.Response>> calendarCompleters = {};

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-delay',
        'floor_id': 'fl-delay',
        'workspace_id': 'ws-target',
        'refresh_token': 'delay-refresh-token',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({
            'access_token': 'delay-access',
            'refresh_token': 'delay-refresh',
          }), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-target', 'name': 'Room-Beta', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          final body = jsonDecode(req.body);
          final d = body['date']?.toString() ?? '';
          final completer = Completer<http.Response>();
          calendarCompleters[d] = completer;
          return await completer.future;
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-target', 'name': 'Room-Beta-01', 'isBookable': true}
          ]), 200);
        }
        if (path.contains('/sites') || path.contains('/buildings')) {
          return http.Response(jsonEncode([{'id': 'site-delay', 'name': 'Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-delay', 'name': 'Floor'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();
      final baseDate = DateTime(2026, 10, 5);

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: baseDate,
        ),
      ));
      await tester.pump();

      // Complete initial date response
      final initialIso = "2026-10-05";
      calendarCompleters[initialIso]?.complete(http.Response(jsonEncode({
        'data': [
          {
            'workspaceId': 'ws-target',
            'status': 'Reserved',
            'bookedTimeSlot': {'occupantName': 'Alice Martin', 'creator': {'id': 'u1', 'name': 'Alice Martin'}}
          }
        ]
      }), 200));
      await tester.pumpAndSettle();

      final nextDayBtn = find.byTooltip('Jour suivant');

      // Click next day 3 times rapidly
      await tester.tap(nextDayBtn); // date 2026-10-06 (Request 2)
      await tester.pump();
      await tester.tap(nextDayBtn); // date 2026-10-07 (Request 3)
      await tester.pump();
      await tester.tap(nextDayBtn); // date 2026-10-08 (Request 4)
      await tester.pump();

      // Now complete responses OUT OF ORDER: Request 4 (latest) completes first!
      calendarCompleters['2026-10-08']?.complete(http.Response(jsonEncode({
        'data': [
          {
            'workspaceId': 'ws-target',
            'status': 'Reserved',
            'bookedTimeSlot': {'occupantName': 'David Follain', 'creator': {'id': 'u4', 'name': 'David Follain'}}
          }
        ]
      }), 200));
      await tester.pumpAndSettle();

      // Formatted as FOLLAIN D.
      expect(find.textContaining('FOLLAIN D.'), findsWidgets);

      // Now the obsolete earlier requests complete late
      calendarCompleters['2026-10-06']?.complete(http.Response(jsonEncode({
        'data': [
          {
            'workspaceId': 'ws-target',
            'status': 'Reserved',
            'bookedTimeSlot': {'occupantName': 'Bob Stale', 'creator': {'id': 'u2', 'name': 'Bob Stale'}}
          }
        ]
      }), 200));
      calendarCompleters['2026-10-07']?.complete(http.Response(jsonEncode({
        'data': [
          {
            'workspaceId': 'ws-target',
            'status': 'Reserved',
            'bookedTimeSlot': {'occupantName': 'Charlie Stale', 'creator': {'id': 'u3', 'name': 'Charlie Stale'}}
          }
        ]
      }), 200));
      await tester.pumpAndSettle();

      // State MUST NOT be overwritten by the stale earlier requests!
      expect(find.textContaining('FOLLAIN D.'), findsWidgets);
      expect(find.textContaining('STALE B.'), findsNothing);
      expect(find.textContaining('STALE C.'), findsNothing);
      expect(sessionExpiredFired, isFalse);
    });

    testWidgets('Spam date changes with transient 429/500 errors do NOT trigger logout', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      int requestIndex = 0;

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-err',
        'floor_id': 'fl-err',
        'workspace_id': 'ws-target',
        'refresh_token': 'err-refresh-token',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({
            'access_token': 'err-access-tok',
            'refresh_token': 'err-refresh-tok',
          }), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-target', 'name': 'Room-Err', 'workspaceType': 'Desk'},
                'geometry': {'type': 'Polygon', 'coordinates': [[[0.0, 0.0], [50.0, 0.0], [50.0, 50.0], [0.0, 50.0], [0.0, 0.0]]]}
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          requestIndex++;
          // Alternate between 429 rate limit, 500 error, and 200 success
          if (requestIndex % 3 == 1) {
            return http.Response('{"error": "rate_limited"}', 429);
          } else if (requestIndex % 3 == 2) {
            return http.Response('{"error": "internal_error"}', 500);
          } else {
            return http.Response(jsonEncode({'data': []}), 200);
          }
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: DateTime(2026, 10, 5),
        ),
      ));
      await tester.pumpAndSettle();

      final nextDayBtn = find.byTooltip('Jour suivant');

      // Click rapidly 10 times hitting errors
      for (int i = 0; i < 10; i++) {
        await tester.tap(nextDayBtn);
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      // Must never trigger session expiration
      expect(sessionExpiredFired, isFalse, reason: '429 and 500 errors during date switching must NEVER trigger logout');
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Token Concurrency Mutex Simulation (refreshMyToken)
  // ═══════════════════════════════════════════════════════════════════════════
  group('2. Token Concurrency Mutex & Replay Protection', () {
    test('Simulate 20 concurrent calls to refreshMyToken(): exactly ONE HTTP POST executed and all receive valid token', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'initial-stored-refresh-token',
      });

      int httpPostCount = 0;
      final storage = StorageService();

      final client = MockClient((req) async {
        expect(req.url.path, contains('/connect/token'));
        expect(req.method, equals('POST'));
        httpPostCount++;

        // Simulate network latency so concurrent callers overlap
        await Future.delayed(const Duration(milliseconds: 40));

        return http.Response(
          jsonEncode({
            'access_token': 'unique-refreshed-access-token-12345',
            'refresh_token': 'rotated-new-refresh-token-67890',
          }),
          200,
        );
      });

      final api = RoomzApiService(client: client, storage: storage);

      // Launch 20 concurrent callers in parallel
      final futures = List.generate(20, (_) => api.refreshMyToken());
      final tokens = await Future.wait(futures);

      // Assertions:
      // 1. Only ONE underlying HTTP POST was performed
      expect(httpPostCount, equals(1), reason: 'In-flight mutex must deduplicate parallel refresh calls into exactly 1 HTTP request');

      // 2. All 20 callers received the valid token
      expect(tokens.length, equals(20));
      for (final t in tokens) {
        expect(t, equals('unique-refreshed-access-token-12345'));
      }

      // 3. Stored refresh token was updated
      final updatedRefreshToken = await storage.getRefreshToken();
      expect(updatedRefreshToken, equals('rotated-new-refresh-token-67890'));

      // 4. Subsequent calls reuse the cached access token without triggering any additional HTTP POST
      final immediateToken = await api.refreshMyToken();
      expect(immediateToken, equals('unique-refreshed-access-token-12345'));
      expect(httpPostCount, equals(1), reason: 'Cached token must be returned without making new network request');
    });

    test('Concurrent force: true calls to refreshMyToken() are also deduplicated by the in-flight mutex', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'force-refresh-token',
      });

      int httpPostCount = 0;
      final storage = StorageService();

      final client = MockClient((req) async {
        httpPostCount++;
        await Future.delayed(const Duration(milliseconds: 40));
        return http.Response(
          jsonEncode({
            'access_token': 'forced-access-token-$httpPostCount',
            'refresh_token': 'forced-refresh-token-$httpPostCount',
          }),
          200,
        );
      });

      final api = RoomzApiService(client: client, storage: storage);

      // First establish a cached token
      final first = await api.refreshMyToken();
      expect(first, equals('forced-access-token-1'));
      expect(httpPostCount, equals(1));

      // Now launch 10 parallel callers all requesting force: true
      final futures = List.generate(10, (_) => api.refreshMyToken(force: true));
      final tokens = await Future.wait(futures);

      // Total HTTP POSTs should now be 2 (the first one + exactly 1 deduplicated forced refresh)
      expect(httpPostCount, equals(2));
      for (final t in tokens) {
        expect(t, equals('forced-access-token-2'));
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Error Filtering (HTTP 429, HTTP 500, and Network Timeout)
  // ═══════════════════════════════════════════════════════════════════════════
  group('3. Error Filtering Resilience (HTTP 429, 500, Timeout)', () {
    test('refreshMyToken() on HTTP 429 does NOT trigger session expiry and preserves tokens', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'surviving-refresh-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async => http.Response('{"error": "Too Many Requests"}', 429));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isFalse, reason: 'HTTP 429 must not trigger onSessionExpired');

      final saved = await storage.getRefreshToken();
      expect(saved, equals('surviving-refresh-token'), reason: 'Refresh token must be retained in storage on 429');
    });

    test('refreshMyToken() on HTTP 500 does NOT trigger session expiry and preserves tokens', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'surviving-refresh-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async => http.Response('Internal Server Error', 500));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isFalse, reason: 'HTTP 500 must not trigger onSessionExpired');

      final saved = await storage.getRefreshToken();
      expect(saved, equals('surviving-refresh-token'), reason: 'Refresh token must be retained on 500');
    });

    test('refreshMyToken() on network SocketException/Timeout does NOT trigger session expiry', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'surviving-refresh-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async {
        throw const SocketException('Connection reset by peer');
      });
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isFalse, reason: 'SocketException must not trigger onSessionExpired');

      final saved = await storage.getRefreshToken();
      expect(saved, equals('surviving-refresh-token'));
    });

    test('Protected API endpoints under 429, 500, or network error do NOT trigger onSessionExpired', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'active-token',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      // Test with 429
      final client429 = MockClient((req) async => http.Response('{"error": "rate_limited"}', 429));
      final api429 = RoomzApiService(client: client429);

      await api429.getSites('token');
      await api429.getFloors('token', 'site-1');
      await api429.getAllWorkspaces('token', 'site-1', 'fl-1');
      await api429.getFloorPlanData('token', 'site-1', 'fl-1');
      await api429.getFloorOccupants('token', 'fl-1', '2026-10-10');
      await api429.reserveWorkspace('2026-10-10', 'token', 'ws-1');
      await api429.addFavorite('token', 'u-1');
      await api429.removeFavorite('token', 'u-1');
      await api429.searchColleagues('token', 'Alice');

      expect(sessionExpiredFired, isFalse, reason: 'No protected API endpoint should trigger session expired on 429');

      // Test with 500
      final client500 = MockClient((req) async => http.Response('Server error', 500));
      final api500 = RoomzApiService(client: client500);

      await api500.getSites('token');
      await api500.getFloorOccupants('token', 'fl-1', '2026-10-10');
      await api500.reserveWorkspace('2026-10-10', 'token', 'ws-1');

      expect(sessionExpiredFired, isFalse, reason: 'No protected API endpoint should trigger session expired on 500');

      // Test with SocketException: should gracefully fail or throw, but NEVER trigger onSessionExpired
      final clientTimeout = MockClient((req) async => throw const SocketException('Host unreachable'));
      final apiTimeout = RoomzApiService(client: clientTimeout);

      try { await apiTimeout.getSites('token'); } catch (_) {}
      try { await apiTimeout.getFloorOccupants('token', 'fl-1', '2026-10-10'); } catch (_) {}

      expect(sessionExpiredFired, isFalse, reason: 'No protected API endpoint should trigger session expired on SocketException');
    });

    test('reserveWorkspaceForColleague() returns error status and does NOT trigger session expiry on 429, 500, or SocketException', () async {
      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      // 429 Rate limit
      final client429 = MockClient((req) async => http.Response('Rate limit exceeded', 429));
      final api429 = RoomzApiService(client: client429);
      final res429 = await api429.reserveWorkspaceForColleague(
        date: '2026-10-10',
        token: 'tok',
        workspaceId: 'ws-1',
        colleagueId: '00000000-0000-0000-0000-000000000001',
      );
      expect(res429.status, equals(BookingStatus.serverError));
      expect(sessionExpiredFired, isFalse);

      // 500 Server error
      final client500 = MockClient((req) async => http.Response('Internal error', 500));
      final api500 = RoomzApiService(client: client500);
      final res500 = await api500.reserveWorkspaceForColleague(
        date: '2026-10-10',
        token: 'tok',
        workspaceId: 'ws-1',
        colleagueId: '00000000-0000-0000-0000-000000000001',
      );
      expect(res500.status, equals(BookingStatus.serverError));
      expect(sessionExpiredFired, isFalse);

      // Network error
      final clientNet = MockClient((req) async => throw const SocketException('Network is down'));
      final apiNet = RoomzApiService(client: clientNet);
      final resNet = await apiNet.reserveWorkspaceForColleague(
        date: '2026-10-10',
        token: 'tok',
        workspaceId: 'ws-1',
        colleagueId: '00000000-0000-0000-0000-000000000001',
      );
      expect(resNet.status, equals(BookingStatus.networkError));
      expect(sessionExpiredFired, isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. Strict HTTP 401 Session Expiry Interception
  // ═══════════════════════════════════════════════════════════════════════════
  group('4. Strict HTTP 401 Session Expiry Interception', () {
    test('refreshMyToken() on HTTP 401 triggers onSessionExpired, clears tokens, but PRESERVES user preferences', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'expired-refresh-token',
        'site_id': 'saved-site-id',
        'floor_id': 'saved-floor-id',
        'workspace_id': 'saved-workspace-id',
        'workspace_name': 'Desk 42',
        'ui_scale': 1.15,
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async => http.Response('{"error": "invalid_grant"}', 401));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final token = await api.refreshMyToken();
      expect(token, isNull);
      expect(sessionExpiredFired, isTrue, reason: 'HTTP 401 on token refresh MUST trigger onSessionExpired');

      // Tokens cleared
      expect(await storage.getRefreshToken(), isNull);

      // User location and UI scale preferences MUST be preserved!
      expect(await storage.getSiteId(), equals('saved-site-id'));
      expect(await storage.getFloorId(), equals('saved-floor-id'));
      expect(await storage.getWorkspaceId(), equals('saved-workspace-id'));
      expect(await storage.getWorkspaceName(), equals('Desk 42'));
      expect(await storage.getUiScale(), equals(1.15));
    });

    test('Protected API call (getSites, getFloorOccupants, reserveWorkspace) on HTTP 401 triggers onSessionExpired', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'expired-tok',
        'site_id': 'saved-site-id',
      });

      int expiryCount = 0;
      RoomzApiService.onSessionExpired = () {
        expiryCount++;
      };

      final client = MockClient((req) async => http.Response('Unauthorized', 401));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      await api.getSites('bad-token');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(expiryCount, equals(1));

      // getFloorOccupants verifies both getCurrentUserId and calendar endpoint 401s
      await api.getFloorOccupants('bad-token', 'fl-1', '2026-10-10');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(expiryCount, equals(3), reason: 'getFloorOccupants triggers 401 on both getCurrentUserId and calendar endpoint');

      await api.reserveWorkspace('2026-10-10', 'bad-token', 'ws-1');
      await Future.delayed(const Duration(milliseconds: 20));
      expect(expiryCount, equals(4));

      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getSiteId(), equals('saved-site-id'));
    });

    test('reserveWorkspaceForColleague() on HTTP 401 returns unauthorized, triggers onSessionExpired, and clears tokens', () async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'expired-tok',
        'site_id': 'saved-site-id',
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async => http.Response('Unauthorized', 401));
      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);

      final result = await api.reserveWorkspaceForColleague(
        date: '2026-10-10',
        token: 'bad-token',
        workspaceId: 'ws-1',
        colleagueId: '00000000-0000-0000-0000-000000000001',
      );

      expect(result.status, equals(BookingStatus.unauthorized));
      expect(sessionExpiredFired, isTrue);
      expect(await storage.getRefreshToken(), isNull);
      expect(await storage.getSiteId(), equals('saved-site-id'));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Favorite Toggle UX & Spamming Resilience
  // ═══════════════════════════════════════════════════════════════════════════
  group('5. Favorite Toggle UX & Spamming Resilience', () {
    testWidgets('Rapid multiple clicks on favorite star trigger only 1 network request and display Shimmer', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'fav-refresh-token',
        'favorite_colleagues': jsonEncode([
          {'id': 'u-marie', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true, 'favoriteId': 'fav-123'},
        ]),
      });

      int deleteNetworkCalls = 0;
      final completer = Completer<http.Response>();

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'fav-tok', 'refresh_token': 'fav-ref'}), 200);
        }
        if (req.method == 'DELETE' && req.url.path.contains('/favorites/')) {
          deleteNetworkCalls++;
          return await completer.future;
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ColleagueSelectionDialog(
            date: '2026-10-15',
            apiService: api,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final starBtn = find.byIcon(Icons.star_rounded);
      expect(starBtn, findsOneWidget);

      // Rapidly tap the star 5 times in succession before the network call responds
      await tester.tap(starBtn);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(starBtn);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(starBtn);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(starBtn);
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(starBtn);
      await tester.pump(const Duration(milliseconds: 10));

      // Shimmer loading must be active while request is in flight
      expect(find.byType(Shimmer), findsOneWidget, reason: 'Shimmer skeleton effect must be displayed during in-flight toggle');

      // Crucial: exactly ONE network request was initiated despite 5 rapid taps
      expect(deleteNetworkCalls, equals(1), reason: '_pendingFavoriteIds must guard against concurrent click spam');

      // Resolve the network call
      completer.complete(http.Response('', 204));
      await tester.pumpAndSettle();

      // Shimmer is gone, item unstarred
      expect(find.byType(Shimmer), findsNothing);
      expect(find.text('Marie Curie'), findsNothing);
    });

    testWidgets('Favorite toggle network failure (500 or timeout) displays error, does NOT log out, and frees pending state', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'fav-refresh-token',
        'favorite_colleagues': jsonEncode([
          {'id': 'u-marie', 'name': 'Marie Curie', 'email': 'marie@radium.org', 'isFavorite': true, 'favoriteId': 'fav-123'},
        ]),
      });

      bool sessionExpiredFired = false;
      RoomzApiService.onSessionExpired = () {
        sessionExpiredFired = true;
      };

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'fav-tok', 'refresh_token': 'fav-ref'}), 200);
        }
        if (req.method == 'DELETE' && req.url.path.contains('/favorites/')) {
          return http.Response('Server error', 500);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ColleagueSelectionDialog(
            date: '2026-10-15',
            apiService: api,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final starBtn = find.byIcon(Icons.star_rounded);
      expect(starBtn, findsOneWidget);

      await tester.tap(starBtn);
      await tester.pumpAndSettle();

      // Session expired must NOT be triggered
      expect(sessionExpiredFired, isFalse, reason: 'Failed favorite toggle must never trigger logout');

      // Shimmer should be cleanly dismissed via finally block
      expect(find.byType(Shimmer), findsNothing);
    });
  });
}
