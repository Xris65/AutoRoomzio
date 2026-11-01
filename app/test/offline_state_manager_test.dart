import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:auto_roomzio/offline_state_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStateManager stateManager;

  setUp(() {
    stateManager = OfflineStateManager.instance;
    stateManager.reset();
  });

  tearDown(() {
    stateManager.reset();
  });

  group('OfflineStateManager Unit Tests', () {
    // ── R1.1: Online Startup Default ──────────────────────────────────────────
    test('initial state defaults to isOffline == false', () {
      expect(stateManager.isOffline, isFalse);
      expect(stateManager.isOfflineNotifier.value, isFalse);
    });

    test('singleton instance returns identical reference', () {
      final instance1 = OfflineStateManager.instance;
      final instance2 = OfflineStateManager();
      expect(identical(instance1, instance2), isTrue);
    });

    // ── R2.1: Reactive Offline Detection ──────────────────────────────────────
    test('markOffline switches isOffline to true and notifies listeners', () {
      final notifications = <bool>[];
      stateManager.isOfflineNotifier.addListener(() {
        notifications.add(stateManager.isOffline);
      });

      stateManager.markOffline();

      expect(stateManager.isOffline, isTrue);
      expect(stateManager.isOfflineNotifier.value, isTrue);
      expect(notifications, [true]);
    });

    test('markOffline is idempotent and avoids redundant notifications', () {
      int count = 0;
      stateManager.isOfflineNotifier.addListener(() {
        count++;
      });

      stateManager.markOffline();
      stateManager.markOffline();
      stateManager.markOffline();

      expect(stateManager.isOffline, isTrue);
      expect(count, equals(1));
    });

    // ── R2.2: Reactive Online Restoration ─────────────────────────────────────
    test('markOnline switches isOffline back to false and notifies listeners', () {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final notifications = <bool>[];
      stateManager.isOfflineNotifier.addListener(() {
        notifications.add(stateManager.isOffline);
      });

      stateManager.markOnline();

      expect(stateManager.isOffline, isFalse);
      expect(notifications, [false]);
    });

    test('markOnline is idempotent when already online', () {
      int count = 0;
      stateManager.isOfflineNotifier.addListener(() {
        count++;
      });

      stateManager.markOnline();
      stateManager.markOnline();

      expect(stateManager.isOffline, isFalse);
      expect(count, equals(0));
    });

    test('reset resets isOffline to false without error', () {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      stateManager.reset();

      expect(stateManager.isOffline, isFalse);
    });

    // ── Connectivity Error Detection ──────────────────────────────────────────
    group('isConnectivityError evaluation', () {
      test('identifies SocketException as connectivity error', () {
        const error = SocketException('Failed host lookup: api.my.roomz.io');
        expect(stateManager.isConnectivityError(error), isTrue);
      });

      test('identifies http.ClientException as connectivity error', () {
        final error = http.ClientException('Connection closed before full header was received');
        expect(stateManager.isConnectivityError(error), isTrue);
      });

      test('identifies TimeoutException as connectivity error', () {
        final error = TimeoutException('Connection timed out after 10000ms');
        expect(stateManager.isConnectivityError(error), isTrue);
      });

      test('identifies connection-related string messages as connectivity error', () {
        expect(stateManager.isConnectivityError(Exception('Network is unreachable')), isTrue);
        expect(stateManager.isConnectivityError(Exception('Connection refused')), isTrue);
        expect(stateManager.isConnectivityError(Exception('Connection reset by peer')), isTrue);
        expect(stateManager.isConnectivityError(Exception('Software caused connection abort')), isTrue);
        expect(stateManager.isConnectivityError(Exception('Network error')), isTrue);
        expect(stateManager.isConnectivityError(Exception('Broken pipe')), isTrue);
      });

      test('rejects business or format errors from being treated as connectivity error', () {
        expect(stateManager.isConnectivityError(const FormatException('Malformed JSON received')), isFalse);
        expect(stateManager.isConnectivityError(ArgumentError('Invalid token parameter')), isFalse);
        expect(stateManager.isConnectivityError(StateError('Bad state')), isFalse);
        expect(stateManager.isConnectivityError(RangeError.index(5, [1, 2])), isFalse);
      });

      test('reportException flips offline for connectivity errors and ignores others', () {
        stateManager.reset();
        stateManager.reportException(const FormatException('Invalid JSON'));
        expect(stateManager.isOffline, isFalse);

        stateManager.reportException(const SocketException('No route to host'));
        expect(stateManager.isOffline, isTrue);
      });
    });
  });

  group('OfflineAwareHttpClient Continuous Unblocked Requests & Reactivity', () {
    // ── R1.2: Continuous Unblocked Requests ───────────────────────────────────
    test('forwards requests through inner client without blocking when offline', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      bool innerCalled = false;
      Uri? requestedUri;
      String? requestedMethod;
      String? requestedHeader;

      final mockInner = MockClient((request) async {
        innerCalled = true;
        requestedUri = request.url;
        requestedMethod = request.method;
        requestedHeader = request.headers['X-Custom-Header'];
        return http.Response('{"status": "ok"}', 200);
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      final response = await client.get(
        Uri.parse('https://api.my.roomz.io/workspaces'),
        headers: {'X-Custom-Header': 'TestValue'},
      );

      // Verify request was NOT blocked or short-circuited
      expect(innerCalled, isTrue);
      expect(requestedUri, Uri.parse('https://api.my.roomz.io/workspaces'));
      expect(requestedMethod, 'GET');
      expect(requestedHeader, 'TestValue');
      expect(response.statusCode, 200);
      expect(response.body, '{"status": "ok"}');

      // Verify reactive recovery: successful response marks online immediately
      expect(stateManager.isOffline, isFalse);
    });

    test('preserves POST body and payload integrity without modification', () async {
      stateManager.markOffline();

      String? capturedBody;
      final mockInner = MockClient((request) async {
        capturedBody = request.body;
        return http.Response('{"created": true}', 201);
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      final payload = jsonEncode({'workspaceId': 'ws-123', 'date': '2026-11-01'});
      final response = await client.post(
        Uri.parse('https://api.my.roomz.io/reservations'),
        body: payload,
        headers: {'Content-Type': 'application/json'},
      );

      expect(capturedBody, equals(payload));
      expect(response.statusCode, 201);
      expect(stateManager.isOffline, isFalse);
    });

    // ── R2.1: Reactive Detection on Network Errors ────────────────────────────
    test('SocketException immediately marks offline and rethrows exception', () async {
      stateManager.reset();
      expect(stateManager.isOffline, isFalse);

      final mockInner = MockClient((request) async {
        throw const SocketException('OS Error: Failed host lookup: api.my.roomz.io, errno = 11001');
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      await expectLater(
        client.get(Uri.parse('https://api.my.roomz.io/floors')),
        throwsA(isA<SocketException>()),
      );

      // Verify offline state was triggered
      expect(stateManager.isOffline, isTrue);
    });

    test('TimeoutException immediately marks offline and rethrows', () async {
      stateManager.reset();
      expect(stateManager.isOffline, isFalse);

      final mockInner = MockClient((request) async {
        throw TimeoutException('Connection timed out waiting for gateway');
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      await expectLater(
        client.get(Uri.parse('https://api.my.roomz.io/users/current')),
        throwsA(isA<TimeoutException>()),
      );

      expect(stateManager.isOffline, isTrue);
    });

    test('ClientException immediately marks offline and rethrows', () async {
      stateManager.reset();
      expect(stateManager.isOffline, isFalse);

      final mockInner = MockClient((request) async {
        throw http.ClientException('Connection closed before full header was received');
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      await expectLater(
        client.get(Uri.parse('https://api.my.roomz.io/data')),
        throwsA(isA<http.ClientException>()),
      );

      expect(stateManager.isOffline, isTrue);
    });

    test('non-connectivity errors do not trigger offline mode', () async {
      stateManager.reset();
      expect(stateManager.isOffline, isFalse);

      final mockInner = MockClient((request) async {
        throw const FormatException('Corrupted response chunk');
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      await expectLater(
        client.get(Uri.parse('https://api.my.roomz.io/corrupted')),
        throwsA(isA<FormatException>()),
      );

      // isOffline must remain false for non-connectivity exceptions
      expect(stateManager.isOffline, isFalse);
    });

    // ── R2.2: Reactive Recovery ───────────────────────────────────────────────
    test('receiving HTTP 200 response immediately restores online mode (isOffline = false)', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final mockInner = MockClient((request) async {
        return http.Response('{"data": []}', 200);
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      final response = await client.get(Uri.parse('https://api.my.roomz.io/ping'));
      expect(response.statusCode, 200);
      expect(stateManager.isOffline, isFalse);
    });

    test('receiving server error (e.g. HTTP 500 or 404) also confirms server connectivity and restores online mode', () async {
      stateManager.markOffline();
      expect(stateManager.isOffline, isTrue);

      final mockInner = MockClient((request) async {
        return http.Response('{"error": "Internal Server Error"}', 500);
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      final response = await client.get(Uri.parse('https://api.my.roomz.io/status'));
      expect(response.statusCode, 500);
      expect(stateManager.isOffline, isFalse);
    });

    // ── Parallel & Sequential Workload Transitions ────────────────────────────
    test('handles sequence of failing then recovering requests cleanly', () async {
      stateManager.reset();
      int attempt = 0;

      final mockInner = MockClient((request) async {
        attempt++;
        if (attempt == 1) {
          throw const SocketException('Connection lost');
        } else if (attempt == 2) {
          throw TimeoutException('Timed out');
        } else {
          return http.Response('{"recovered": true}', 200);
        }
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      // Attempt 1: Network drop
      await expectLater(client.get(Uri.parse('https://api.my.roomz.io/test1')), throwsA(isA<SocketException>()));
      expect(stateManager.isOffline, isTrue);

      // Attempt 2: Still down (timeout)
      await expectLater(client.get(Uri.parse('https://api.my.roomz.io/test2')), throwsA(isA<TimeoutException>()));
      expect(stateManager.isOffline, isTrue);

      // Attempt 3: Network returns
      final resp = await client.get(Uri.parse('https://api.my.roomz.io/test3'));
      expect(resp.statusCode, 200);
      expect(stateManager.isOffline, isFalse);
    });

    test('concurrent requests through client correctly resolve and update state', () async {
      stateManager.markOffline();

      final mockInner = MockClient((request) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return http.Response('{"index": "${request.url.path}"}', 200);
      });

      final client = OfflineAwareHttpClient(mockInner, stateManager);

      final futures = [
        client.get(Uri.parse('https://api.my.roomz.io/req1')),
        client.get(Uri.parse('https://api.my.roomz.io/req2')),
        client.get(Uri.parse('https://api.my.roomz.io/req3')),
      ];

      final results = await Future.wait(futures);
      expect(results, hasLength(3));
      for (final r in results) {
        expect(r.statusCode, 200);
      }
      expect(stateManager.isOffline, isFalse);
    });
  });
}
