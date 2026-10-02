import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Helper to format ISO date string (YYYY-MM-DD)
  String formatDate(DateTime dt) => dt.toIso8601String().split('T').first;

  group('Statistics Tab Clean UI & Metrics Verification (Requirement R1)', () {
    testWidgets('renders 4 clean metric cards and configured rhythm banner with valid data', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 2)));
      final day2 = formatDate(now.add(const Duration(days: 4)));
      final day3 = formatDate(now.add(const Duration(days: 6)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 12,
        'stats_manual_count': 5,
        'booked_dates': [day1, day2], // 2 bookings on favorite desk
        'booked_elsewhere_dates': [day3], // 1 booking on another desk
        'selected_days': ['1', '3', '5'], // Mon, Wed, Fri
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100)); // complete _loadData async tasks

      // Verify HomeScreen is rendered
      expect(find.byType(HomeScreen), findsOneWidget);

      // Navigate to Stats tab via bottom nav bar
      final statsTabFinder = find.text('Stats');
      expect(statsTabFinder, findsOneWidget);
      await tester.tap(statsTabFinder);
      await tester.pumpAndSettle();

      // 1. Verify Header
      expect(find.text('Vos Statistiques'), findsOneWidget);
      expect(find.text("L'impact de l'automatisation sur votre quotidien"), findsOneWidget);

      // 2. Verify 4 Clean Metric Cards Titles
      expect(find.text('Réservations à venir'), findsOneWidget);
      expect(find.text('Taux Bureau Favori'), findsOneWidget);
      expect(find.text('Automatisées'), findsOneWidget);
      expect(find.text('Manuelles'), findsOneWidget);

      // 3. Verify Metric Card Values:
      // Total upcoming = 2 here + 1 elsewhere = 3
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 sur bureau favori'), findsOneWidget);

      // Loyalty ratio = 2 / 3 = 67%
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('2 sur 3 à venir'), findsOneWidget);

      // Automated = 12, Manual = 5
      expect(find.text('12'), findsOneWidget);
      expect(find.text('12 via automate'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('5 en un clic'), findsOneWidget);

      // 4. Verify Configured Rhythm Banner
      expect(find.text('Rythme de Présence Paramétré'), findsOneWidget);
      expect(find.text('3 jours / sem.'), findsOneWidget);
      expect(find.text('Lundi, Mercredi, Vendredi'), findsOneWidget);
    });

    testWidgets('proves fabricated and misleading metrics are strictly removed', (WidgetTester tester) async {
      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 1)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 1,
        'stats_manual_count': 0,
        'booked_dates': [day1],
        'selected_days': ['2'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Negative assertions: fabricated calculations MUST NOT be present
      expect(find.text('Moyenne de Présentiel'), findsNothing);
      expect(find.text('Jour Favori'), findsNothing);
      expect(find.textContaining('jrs/mois'), findsNothing);
      expect(find.textContaining('de tes venues'), findsNothing);
    });

    testWidgets('card tap displays modal bottom sheet with accurate tooltip information', (WidgetTester tester) async {
      final now = DateTime.now();
      final day1 = formatDate(now.add(const Duration(days: 1)));

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 5,
        'stats_manual_count': 2,
        'booked_dates': [day1],
        'selected_days': ['1'],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Tap on "Réservations à venir" card
      await tester.tap(find.text('Réservations à venir'));
      await tester.pumpAndSettle();

      // Verify bottom sheet modal opened
      expect(find.text("J'ai compris"), findsOneWidget);
      expect(find.textContaining("issues de MyRoomz"), findsOneWidget);

      // Dismiss modal
      await tester.tap(find.text("J'ai compris"));
      await tester.pumpAndSettle();

      expect(find.text("J'ai compris"), findsNothing);
    });

    testWidgets('handles empty state and unconfigured rhythm gracefully without crashing', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': true,
        'show_automation_card': true,
        'stats_auto_count': 0,
        'stats_manual_count': 0,
        'booked_dates': <String>[],
        'booked_elsewhere_dates': <String>[],
        'selected_days': <String>[],
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Stats'));
      await tester.pumpAndSettle();

      // Zero bookings state
      expect(find.text('0'), findsWidgets);
      expect(find.text('Aucune réservation'), findsWidgets);
      expect(find.text('-'), findsOneWidget); // Loyalty fallback
      expect(find.text('Par AutoRoomzio'), findsOneWidget);
      expect(find.text('En un clic'), findsOneWidget);

      // Unconfigured rhythm state
      expect(find.text('Non configuré'), findsOneWidget);
      expect(find.text("Définissez vos jours dans l'onglet Automate"), findsOneWidget);
    });

    testWidgets('honors show_stats_card setting and hides tab when disabled', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-42',
        'show_stats_card': false, // DISABLED
        'show_automation_card': true,
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Stats tab must NOT be present in bottom navigation
      expect(find.text('Stats'), findsNothing);
    });
  });
}
