import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String formatDate(DateTime dt) => dt.toIso8601String().split('T').first;

  group('Empirical Challenger M1-2: SharedPreferences Resilience & Malformed Data', () {
    // -------------------------------------------------------------------------
    // Test 1: Completely empty SharedPreferences
    // -------------------------------------------------------------------------
    testWidgets('1. Handles completely empty SharedPreferences ({}) without uncaught exceptions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // No keys whatsoever
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
    });

    // -------------------------------------------------------------------------
    // Test 2: Missing stats_auto_count and stats_manual_count keys
    // -------------------------------------------------------------------------
    testWidgets('2. Handles missing stats counters without uncaught exceptions', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        // Notice: stats_auto_count and stats_manual_count are NOT provided
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Auto count defaults to 0
      expect(find.text('Par AutoRoomzio'), findsOneWidget);
      // Manual count defaults to 0
      expect(find.text('En un clic'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 3: Missing booked_dates and booked_elsewhere_dates keys
    // -------------------------------------------------------------------------
    testWidgets('3. Handles missing booked_dates and booked_elsewhere_dates keys', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'stats_auto_count': 3,
        'stats_manual_count': 1,
        // No booked_dates or booked_elsewhere_dates
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('0'), findsWidgets);
      expect(find.text('Aucune réservation'), findsNWidgets(2));
      expect(find.text('-'), findsOneWidget); // Loyalty fallback
    });

    // -------------------------------------------------------------------------
    // Test 4: Missing selected_days key (fallback to StorageService defaults [2, 4])
    // -------------------------------------------------------------------------
    testWidgets('4. Handles missing selected_days key gracefully', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        // selected_days is missing: StorageService defaults to [2, 4] (Tue, Thu)
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Rythme de Présence Paramétré'), findsOneWidget);
      expect(find.text('2 jours / sem.'), findsOneWidget);
      expect(find.text('Mardi, Jeudi'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 5: Empty selected_days list
    // -------------------------------------------------------------------------
    testWidgets('5. Handles explicitly empty selected_days list', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'selected_days': <String>[],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Non configuré'), findsOneWidget);
      expect(find.text("Définissez vos jours dans l'onglet Automate"), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 6: Malformed selected_days values (unhandled FormatException vulnerability)
    // -------------------------------------------------------------------------
    test('6. StorageService.getDays() throws unhandled FormatException on malformed selected_days', () async {
      SharedPreferences.setMockInitialValues({
        'selected_days': ['foo', 'bar'],
      });

      final storage = StorageService();
      // StorageService.getDays uses `days?.map(int.parse).toList()` which throws FormatException on non-numeric strings
      expect(
        () async => await storage.getDays(),
        throwsA(isA<FormatException>()),
        reason: 'Proves StorageService does not use int.tryParse, leading to uncaught FormatException',
      );
    });

    // -------------------------------------------------------------------------
    // Test 7: Malformed date strings in booked_dates
    // -------------------------------------------------------------------------
    testWidgets('7. Handles malformed date strings in booked_dates without crashing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final validFuture = formatDate(now.add(const Duration(days: 2)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'booked_dates': ['not-a-valid-date', '', '2026/99/99', validFuture],
        'booked_elsewhere_dates': ['garbage-date', '???'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // String.compareTo handles arbitrary string comparison without throwing FormatException
      expect(tester.takeException(), isNull);
      expect(find.text('Réservations à venir'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 8: Null workspace_name handling
    // -------------------------------------------------------------------------
    testWidgets('8. Handles null workspace_name in loyalty tooltip without crashing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 1)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        // workspace_name is omitted (null in storage)
        'show_stats_card': true,
        'booked_dates': [day1],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Tap on loyalty card to open bottom sheet tooltip
      await tester.tap(find.text('Taux Bureau Favori'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text("J'ai compris"), findsOneWidget);

      await tester.tap(find.text("J'ai compris"));
      await tester.pumpAndSettle();
    });

    // -------------------------------------------------------------------------
    // Test 9: Negative counters in stats_auto_count / stats_manual_count
    // -------------------------------------------------------------------------
    testWidgets('9. Handles negative counters without crashing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'stats_auto_count': -10,
        'stats_manual_count': -5,
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('-10'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 10: Strict negative assertions across all states
    // -------------------------------------------------------------------------
    testWidgets('10. Negative assertions verify absolute absence of legacy fabricated strings', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 1)));
      final day2 = formatDate(now.add(const Duration(days: 3)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'stats_auto_count': 50,
        'stats_manual_count': 20,
        'booked_dates': [day1],
        'booked_elsewhere_dates': [day2],
        'selected_days': ['1', '2', '3', '4', '5'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Verify that NO legacy strings exist in the widget tree
      expect(find.text('Moyenne de Présentiel'), findsNothing);
      expect(find.text('Jour Favori'), findsNothing);
      expect(find.textContaining('Moyenne de Présentiel'), findsNothing);
      expect(find.textContaining('Jour Favori'), findsNothing);
      expect(find.textContaining('jrs/mois'), findsNothing);
      expect(find.textContaining('de tes venues'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
