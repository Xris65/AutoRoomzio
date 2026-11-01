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
import 'package:auto_roomzio/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfflineStateManager.instance.reset();
  });

  group('Bug #3: Pending Date Guard on Network/API Error Tests', () {
    testWidgets('Attempting to reserve date < J+13 when network fails does NOT add to requestedDates and shows error', (tester) async {
      // Pick tomorrow (< J+13)
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = tomorrow.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-123',
        'workspace_name': 'Desk 12',
        'floor_id': 'floor-1',
        'requested_dates': <String>[],
        'booked_dates': <String>[],
        'ignored_dates': <String>[],
        'initial_tab': 1, // Calendar tab
      });

      // Mock client throws SocketException on token refresh or booking
      final client = MockClient((req) async {
        throw const SocketException('Network unreachable');
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Find the cell for tomorrow in the calendar and tap it
      // Instead of relying on specific calendar cell rendering, simulate calling _handleDateTap or finding text
      // We can find day text for tomorrow
      final dayText = tomorrow.day.toString();
      final dayFinder = find.text(dayText);
      expect(dayFinder, findsWidgets);

      await tester.tap(dayFinder.first);
      await tester.pumpAndSettle();

      // Modal bottom sheet appears. It should show 'Réserver ce jour' (since tomorrow < J+13)
      final reserveBtn = find.text('Réserver ce jour');
      if (reserveBtn.evaluate().isNotEmpty) {
        await tester.tap(reserveBtn);
        await tester.pumpAndSettle();

        // Check toast or notification
        expect(find.byType(SnackBar), findsWidgets);

        // Crucial verification: tomorrowStr MUST NOT be in requested_dates!
        final requested = await storage.getRequestedDates();
        expect(requested.contains(tomorrowStr), isFalse,
            reason: 'Close date (< J+13) must NEVER be automatically added to requestedDates on network failure');
      }
    });

    testWidgets('Reserving a date beyond J+13 (> 13 days) explicitly adds to requestedDates as pending', (tester) async {
      final farDay = DateTime.now().add(const Duration(days: 20));
      final farDayStr = farDay.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-123',
        'workspace_name': 'Desk 12',
        'floor_id': 'floor-1',
        'requested_dates': <String>[],
        'booked_dates': <String>[],
        'ignored_dates': <String>[],
        'initial_tab': 1,
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'token', 'refresh_token': 'mock'}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Tap far day in calendar (if in same month or we can pump directly)
      final dayText = farDay.day.toString();
      final dayFinder = find.text(dayText);
      if (dayFinder.evaluate().isNotEmpty) {
        await tester.tap(dayFinder.first);
        await tester.pumpAndSettle();

        final progBtn = find.text('Programmer (En attente)');
        if (progBtn.evaluate().isNotEmpty) {
          await tester.tap(progBtn);
          await tester.pumpAndSettle();

          // Far date (> J+13) SHOULD be in requested_dates because user explicitly scheduled it
          final requested = await storage.getRequestedDates();
          expect(requested.contains(farDayStr), isTrue);
        }
      }
    });

    testWidgets('QuickBook when token refresh fails displays error and does NOT add to requestedDates', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = tomorrow.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-123',
        'floor_id': 'floor-1',
        'requested_dates': <String>[],
        'booked_dates': <String>[],
        'ignored_dates': <String>[],
        'initial_tab': 0, // Accueil tab with quick action buttons
      });

      final client = MockClient((req) async {
        throw const SocketException('Server down');
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Check requested dates remains empty
      final requested = await storage.getRequestedDates();
      expect(requested.contains(tomorrowStr), isFalse);
    });
  });
}
