import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String formatDate(DateTime dt) => dt.toIso8601String().split('T').first;

  group('Challenger M1 Adversarial Probes', () {
    // -------------------------------------------------------------------------
    // Probe 1: Sensitivity of Spike Test - Does it fail when past records exist?
    // -------------------------------------------------------------------------
    test('Probe 1: Spike verification assertion genuinely fails if mock returns past records', () async {
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);
      final pastDateStr = formatDate(now.subtract(const Duration(days: 5)));

      // Mock client that returns a past booking
      final mockClientWithPastRecord = MockClient((request) async {
        return http.Response(
          jsonEncode({
            "bookings": [
              {
                "id": "b-past-001",
                "eventId": "ws-101/evt-past",
                "type": "Reserved",
                "eventDate": "${pastDateStr}T09:00:00",
                "workspaceId": "ws-101",
                "workspaceName": "DS-BORD-1-18-D",
              }
            ]
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final response = await mockClientWithPastRecord.get(
        Uri.parse('https://api.my.roomz.io/users/current/bookings'),
        headers: {'Authorization': 'Bearer test-token'},
      );

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final bookings = (data['bookings'] as List).cast<Map<String, dynamic>>();

      final pastBookings = bookings.where((b) {
        final d = DateTime.parse((b['eventDate'] as String).split('T').first);
        return d.isBefore(todayDate);
      }).toList();

      // We assert that the exact check from spike_api_history_test.dart would fail:
      expect(pastBookings, isNotEmpty);
      expect(
        () => expect(pastBookings, isEmpty, reason: 'MyRoomz standard response must contain zero past bookings'),
        throwsA(isA<TestFailure>()),
        reason: 'Spike test must fail if past records are returned by API',
      );
    });

    // -------------------------------------------------------------------------
    // Probe 2: All bookings are on other desks (booked_elsewhere_dates)
    // -------------------------------------------------------------------------
    testWidgets('Probe 2: Handles 100% elsewhere bookings (loyalty ratio = 0%)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 1)));
      final day2 = formatDate(now.add(const Duration(days: 3)));
      final day3 = formatDate(now.add(const Duration(days: 5)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 0,
        'stats_manual_count': 7,
        'booked_dates': <String>[], // 0 bookings on favorite desk
        'booked_elsewhere_dates': [day1, day2, day3], // 3 bookings elsewhere
        'selected_days': ['1', '2', '3', '4', '5'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Total upcoming = 3
      expect(find.text('3'), findsOneWidget);
      expect(find.text('0 sur bureau favori'), findsOneWidget);

      // Favorite desk loyalty ratio = 0% (0 / 3)
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('0 sur 3 à venir'), findsOneWidget);

      // Verify no exceptions or NaN
      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // Probe 3: All bookings are in the past
    // -------------------------------------------------------------------------
    testWidgets('Probe 3: Handles 100% past bookings (upcoming = 0, loyalty fallback = -)', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final past1 = formatDate(now.subtract(const Duration(days: 1)));
      final past2 = formatDate(now.subtract(const Duration(days: 10)));
      final past3 = formatDate(now.subtract(const Duration(days: 30)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 15,
        'stats_manual_count': 8,
        'booked_dates': [past1, past2], // Past favorite desk bookings
        'booked_elsewhere_dates': [past3], // Past elsewhere bookings
        'selected_days': ['1', '3'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // All past bookings must be excluded from upcoming count
      expect(find.text('0'), findsOneWidget); // Card 1 value
      expect(find.text('Aucune réservation'), findsNWidgets(2)); // Card 1 and Card 2 subtitles
      expect(find.text('-'), findsOneWidget); // Card 2 loyalty ratio fallback

      // Historical local counts should still be shown
      expect(find.text('15'), findsOneWidget);
      expect(find.text('15 via automate'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('8 en un clic'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // Probe 4: Very large numbers for auto and manual counts
    // -------------------------------------------------------------------------
    testWidgets('Probe 4: Handles very large numbers in auto and manual counters', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const largeAuto = 999999;
      const largeManual = 1234567;

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': largeAuto,
        'stats_manual_count': largeManual,
        'booked_dates': <String>[],
        'selected_days': <String>[],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(find.text('$largeAuto'), findsOneWidget);
      expect(find.text('$largeAuto via automate'), findsOneWidget);
      expect(find.text('$largeManual'), findsOneWidget);
      expect(find.text('$largeManual en un clic'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // Probe 5: Mobile screen sizes - Layout overflow empirical verification
    // -------------------------------------------------------------------------
    for (final size in [
      const Size(360, 640), // Standard Android compact
      const Size(375, 667), // iPhone SE / 8
      const Size(390, 844), // iPhone 12/13/14
      const Size(412, 915), // Pixel 7
    ]) {
      testWidgets('Probe 5: Layout overflow bug on mobile screen ${size.width}x${size.height}', (WidgetTester tester) async {
        final List<FlutterErrorDetails> caughtErrors = [];
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          caughtErrors.add(details);
        };

        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          FlutterError.onError = originalOnError;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final now = DateTime.now();
        final day1 = formatDate(now.add(const Duration(days: 1)));

        SharedPreferences.setMockInitialValues({
          'refresh_token': 'mock_refresh_token',
          'workspace_name': 'Desk A-42',
          'show_stats_card': true,
          'show_automation_card': true,
          'stats_auto_count': 999,
          'stats_manual_count': 888,
          'booked_dates': [day1],
          'selected_days': ['1', '2', '3', '4', '5'],
        });

        await tester.pumpWidget(const MyApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();

        // Empirically confirms that no RenderFlex overflow occurs on mobile screens after M1 clean UI
        final overflowErrors = caughtErrors.where((e) => e.toString().contains('A RenderFlex overflowed')).toList();
        expect(
          overflowErrors,
          isEmpty,
          reason: 'Unexpected RenderFlex overflow on ${size.width}x${size.height}',
        );
      });
    }
  });
}
