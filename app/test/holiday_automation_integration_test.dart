import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/background_task.dart';
import 'package:auto_roomzio/holiday_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Evolution 3 - Storage & Automation Holiday Integration', () {
    test('skipPublicHolidays defaults to true and holidayCountryCode defaults to FR', () async {
      final storage = StorageService();
      expect(await storage.getSkipPublicHolidays(), isTrue);
      expect(await storage.getHolidayCountryCode(), equals(HolidayService.countryFrance));

      await storage.saveSkipPublicHolidays(false);
      await storage.saveHolidayCountryCode(HolidayService.countrySwitzerland);

      expect(await storage.getSkipPublicHolidays(), isFalse);
      expect(await storage.getHolidayCountryCode(), equals('CH'));
    });

    test('runBackgroundBookingAutomation skips FR public holiday (May 1) when skipPublicHolidays=true, books when false, and honors explicit requestedDates', () async {
      final now = DateTime(2026, 4, 28); // Tue Apr 28 -> +2d = Thu Apr 30, +3d = Fri May 1 (Fête du Travail)
      final bookedDatesList = <String>[];

      Future<int> runScenario({
        required bool skipHolidays,
        List<String> requestedDates = const [],
      }) async {
        bookedDatesList.clear();
        SharedPreferences.setMockInitialValues({});
        final storage = StorageService();
        await storage.saveRefreshToken('mock-token');
        await storage.saveFloorId('fl-1');
        await storage.saveWorkspaceId('ws-1');
        await storage.saveWorkspaceName('Desk 1');
        await storage.saveHideWeekends(true);
        await storage.saveSkipPublicHolidays(skipHolidays);
        await storage.saveHolidayCountryCode('FR');
        await storage.saveAutomationRules([
          const AutomationRule(
            id: 'ws-1',
            siteId: 's1',
            floorId: 'fl-1',
            workspaceId: 'ws-1',
            workspaceName: 'Desk 1',
            days: [5], // Fridays -> May 1, 2026 & May 8, 2026 (both FR holidays!) & May 15 is > 13d
          ),
        ]);
        if (requestedDates.isNotEmpty) {
          await storage.saveRequestedDates(requestedDates);
        }

        final client = MockClient((req) async {
          if (req.url.path.contains('/connect/token')) {
            return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
          }
          if (req.url.path.contains('/users/current/bookings')) {
            return http.Response(jsonEncode({'bookings': <Object>[]}), 200);
          }
          if (req.url.path.contains('/workspaces/calendars')) {
            return http.Response(jsonEncode({'data': <Object>[]}), 200);
          }
          if (req.url.path.contains('/users/current')) {
            return http.Response(jsonEncode({'id': 'u-1'}), 200);
          }
          if (req.url.path.contains('/bookings') && req.method == 'POST') {
            final body = jsonDecode(req.body);
            bookedDatesList.add(body['localDate'].toString());
            return http.Response(jsonEncode({'id': 'ok'}), 201);
          }
          return http.Response('[]', 200);
        });

        final api = RoomzApiService(client: client, storage: storage);
        return runBackgroundBookingAutomation(
          apiService: api,
          storageService: storage,
          nowOverride: now,
        );
      }

      // 1. skipHolidays = true -> May 1 and May 8 (both FR public holidays) are skipped!
      final countSkipped = await runScenario(skipHolidays: true);
      expect(countSkipped, equals(0));
      expect(bookedDatesList, isEmpty);

      // 2. skipHolidays = false -> May 1 and May 8 are booked!
      final countBooked = await runScenario(skipHolidays: false);
      expect(countBooked, equals(2));
      expect(bookedDatesList, containsAll(['2026-05-01', '2026-05-08']));

      // 3. skipHolidays = true, but May 1 is explicitly in requestedDates -> May 1 is honored, May 8 skipped!
      final countOverride = await runScenario(
        skipHolidays: true,
        requestedDates: ['2026-05-01'],
      );
      expect(countOverride, equals(1));
      expect(bookedDatesList, equals(['2026-05-01']));
    });
  });

  group('Evolution 3 - HomeScreen Holiday Controls & Calendar Modal', () {
    testWidgets('HomeScreen Settings tab toggles skipPublicHolidays & selects holiday country (removed from Automate tab)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveWorkspaceId('ws-1');
      await storage.saveWorkspaceName('Desk A');
      await storage.saveFloorId('fl-1');
      await storage.saveInitialTab(2); // Automate tab

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Holiday controls must no longer live in the Automate tab
      expect(find.byKey(const ValueKey('toggle_skip_public_holidays')), findsNothing);
      expect(find.byKey(const ValueKey('holiday_country_selector')), findsNothing);

      // Navigate to Settings (Paramètres) tab
      await tester.tap(find.text('Paramètres'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('toggle_skip_public_holidays'));
      final countrySelector = find.byKey(const ValueKey('holiday_country_selector'));
      await tester.scrollUntilVisible(
        countrySelector,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();

      expect(toggle, findsOneWidget);
      expect(find.text('Jours fériés'), findsOneWidget);
      expect(countrySelector, findsOneWidget);

      // Switch country to Suisse (CH)
      await tester.ensureVisible(find.text('Suisse'));
      await tester.tap(find.text('Suisse'));
      await tester.pumpAndSettle();
      expect(await storage.getHolidayCountryCode(), equals('CH'));

      // Disable skipPublicHolidays -> country selector hides
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(await storage.getSkipPublicHolidays(), isFalse);
      expect(find.byKey(const ValueKey('holiday_country_selector')), findsNothing);
    });

    testWidgets('HomeScreen Calendar tap modal shows holiday banner on public holiday (Dec 25)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveWorkspaceId('ws-1');
      await storage.saveWorkspaceName('Desk A');
      await storage.saveFloorId('fl-1');
      await storage.saveInitialTab(1); // Calendar tab
      await storage.saveSkipPublicHolidays(true);
      await storage.saveHolidayCountryCode('FR');

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate to December 2026 if currently in November 2026 (or find next month)
      final now = DateTime.now();
      if (now.month < 12) {
        final monthsForward = 12 - now.month;
        for (int i = 0; i < monthsForward; i++) {
          await tester.tap(find.byIcon(Icons.chevron_right).first);
          await tester.pumpAndSettle();
        }
      }

      // Tap December 25 (last '25' if Nov 25 shows up, or first/only '25' in Dec)
      await tester.tap(find.text('25').last);
      await tester.pumpAndSettle();

      final Finder holidayBanner = find.byKey(const ValueKey('holiday_banner_in_modal'));
      expect(holidayBanner, findsOneWidget);
      expect(
        find.descendant(
          of: holidayBanner,
          matching: find.byIcon(Icons.celebration_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('Jour férié : Noël (Automatisation suspendue)'), findsOneWidget);
    });
  });
}
