import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Pending Bookings Card & Calendar Sync Tests', () {
    testWidgets('Pending booking card on Home screen shows delete button (Supprimer) and NEVER Bloquer', (tester) async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final tomorrowStr = tomorrow.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-desk-1',
        'workspace_name': 'Desk Alpha',
        'floor_id': 'fl-1',
        'requested_dates': [tomorrowStr],
        'booked_dates': <String>[],
        'ignored_dates': <String>[],
        'initial_tab': 0, // Accueil tab
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/reservations') || req.url.path.contains('/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/occupancy') || req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Find the pending card on home screen
      expect(find.text('Programmé en attente (Desk Alpha)'), findsNothing); // unless name set
      // The pending card should be rendered with delete outline icon
      final deleteBtn = find.byTooltip('Supprimer');
      expect(deleteBtn, findsWidgets);

      // Verify Bloquer is NOT present on the pending card
      final blockBtn = find.byTooltip('Bloquer');
      expect(blockBtn, findsNothing);

      // Tap the delete button on the pending booking
      await tester.tap(deleteBtn.first);
      await tester.pumpAndSettle();

      // Verify it was removed from requested_dates
      final requested = await storage.getRequestedDates();
      expect(requested.contains(tomorrowStr), isFalse);

      // Verify it was NOT added to ignored_dates (not blocked!)
      final ignored = await storage.getIgnoredDates();
      expect(ignored.contains(tomorrowStr), isFalse);
    });

    testWidgets('Calendar date tap modal for pending booking hides Bloquer and cancels cleanly', (tester) async {
      final targetDate = DateTime.now().add(const Duration(days: 3));
      final targetDateStr = targetDate.toIso8601String().split('T').first;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-refresh-token',
        'workspace_id': 'ws-desk-1',
        'workspace_name': 'Desk Alpha',
        'floor_id': 'fl-1',
        'requested_dates': [targetDateStr],
        'booked_dates': <String>[],
        'ignored_dates': <String>[],
        'initial_tab': 1, // Calendar tab
      });

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
        }
        if (req.url.path.contains('/reservations') || req.url.path.contains('/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/occupancy') || req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // Tap on the target day in the TableCalendar
      final dayCell = find.text('${targetDate.day}');
      expect(dayCell, findsWidgets);
      await tester.tap(dayCell.first);
      await tester.pumpAndSettle();

      // Check bottom sheet options
      expect(find.text('Annuler la programmation'), findsOneWidget);
      // "Bloquer (Ignorer l'automatisation)" MUST be strictly hidden!
      expect(find.text("Bloquer (Ignorer l'automatisation)"), findsNothing);

      // Tap "Annuler la programmation"
      await tester.tap(find.text('Annuler la programmation'));
      await tester.pumpAndSettle();

      // Verify date is removed from storage requested_dates
      final requested = await storage.getRequestedDates();
      expect(requested.contains(targetDateStr), isFalse);

      // Verify date is NOT in ignored_dates
      final ignored = await storage.getIgnoredDates();
      expect(ignored.contains(targetDateStr), isFalse);
    });
  });
}
