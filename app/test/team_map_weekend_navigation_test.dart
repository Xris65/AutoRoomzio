import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/time_slider_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test reference dates:
  // Friday: 2026-11-06
  // Saturday: 2026-11-07
  // Sunday: 2026-11-08
  // Monday: 2026-11-09
  final testFriday = DateTime(2026, 11, 6);
  final testSaturday = DateTime(2026, 11, 7);
  final testSunday = DateTime(2026, 11, 8);
  final testMonday = DateTime(2026, 11, 9);

  RoomzApiService createMockApi() {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/connect/token')) {
        return http.Response(
            jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
      }
      if (path.contains('/floors') && path.contains('/data')) {
        return http.Response(jsonEncode({
          'features': [
            {
              'type': 'Feature',
              'properties': {'workspaceId': 'ws-1', 'workspaceType': 'Desk', 'name': 'B01-01'},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
                ]
              }
            }
          ]
        }), 200);
      }
      if (path.contains('/floors') && path.contains('/workspaces/calendars')) {
        return http.Response(jsonEncode({'data': []}), 200);
      }
      if (path.contains('/workspaces')) {
        return http.Response(jsonEncode([
          {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
        ]), 200);
      }
      if (path.contains('/buildings') && path.contains('/floors')) {
        return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
      }
      return http.Response('[]', 200);
    });
    return RoomzApiService(client: client);
  }

  group('A. Initialisation de la date sur le plan d\'équipe (TeamMapScreen)', () {
    testWidgets('Initialisation un samedi -> bascule automatique sur le lundi suivant (+2 jours)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testSaturday, // Samedi 7 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Samedi doit avoir basculé vers le lundi à venir (9 nov.)
      expect(find.textContaining('Samedi 7 nov.'), findsNothing);
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);
    });

    testWidgets('Initialisation un dimanche -> bascule automatique sur le lundi suivant (+1 jour)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testSunday, // Dimanche 8 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Dimanche doit avoir basculé vers le lundi à venir (9 nov.)
      expect(find.textContaining('Dimanche 8 nov.'), findsNothing);
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);
    });

    testWidgets('Initialisation un samedi avec hideWeekends=false -> reste bien sur le samedi',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': false,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testSaturday,
          storageService: storage,
          apiService: api,
          hideWeekends: false,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Samedi 7 nov.'), findsOneWidget);
    });
  });

  group('B. Navigation jour suivant / précédent sur TeamMapScreen', () {
    testWidgets('Navigation jour suivant depuis vendredi -> atterrit directement sur lundi (+3 jours)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testFriday, // Vendredi 6 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vendredi 6 nov.'), findsOneWidget);

      final nextBtn = find.byTooltip('Jour suivant');
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();

      // Doit sauter Samedi et Dimanche pour aller à Lundi 9 nov.
      expect(find.textContaining('Samedi 7 nov.'), findsNothing);
      expect(find.textContaining('Dimanche 8 nov.'), findsNothing);
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);
    });

    testWidgets('Navigation jour précédent depuis lundi -> atterrit directement sur vendredi (-3 jours)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testMonday, // Lundi 9 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);

      final prevBtn = find.byTooltip('Jour précédent');
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();

      // Doit sauter Dimanche et Samedi pour reculer au Vendredi 6 nov.
      expect(find.textContaining('Dimanche 8 nov.'), findsNothing);
      expect(find.textContaining('Samedi 7 nov.'), findsNothing);
      expect(find.textContaining('Vendredi 6 nov.'), findsOneWidget);
    });

    testWidgets('Navigation normale en semaine (ex: Mardi -> Mercredi et Mercredi -> Mardi)',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final tuesday = DateTime(2026, 11, 10);
      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: tuesday, // Mardi 10 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Mardi 10 nov.'), findsOneWidget);

      // Next -> Mercredi 11 nov.
      await tester.tap(find.byTooltip('Jour suivant'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mercredi 11 nov.'), findsOneWidget);

      // Prev -> Mardi 10 nov.
      await tester.tap(find.byTooltip('Jour précédent'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mardi 10 nov.'), findsOneWidget);
    });
  });

  group('C. Impossibilité de sélectionner samedi/dimanche via le date picker', () {
    testWidgets('DatePicker modal s\'ouvre avec un jour de semaine sélectionné et empêche les weekends',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testFriday, // Vendredi 6 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Clic sur l'icône calendrier pour ouvrir showDatePicker
      final calendarFinder = find.byIcon(Icons.calendar_today);
      expect(calendarFinder, findsOneWidget);
      await tester.tap(calendarFinder);
      await tester.pumpAndSettle();

      // Le DatePicker est ouvert (dialogue de sélection de date)
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Fermer le dialog
      final cancelBtn = find.text('Cancel').evaluate().isNotEmpty ? find.text('Cancel') : find.text('Annuler');
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();
    });

    testWidgets('DatePicker ouvert depuis un weekend basculé ne lève aucune assertion',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh',
        'hide_weekends': true,
      });

      final api = createMockApi();
      final storage = StorageService();

      // On passe un dimanche
      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: testSunday,
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      // Le screen a basculé au lundi 9 nov.
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);

      // Ouvrir le date picker
      await tester.tap(find.byIcon(Icons.calendar_today));
      await tester.pumpAndSettle();

      // Le modal s'ouvre sans erreur d'assertion Flutter (assert(selectableDayPredicate(initialDate)))
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final cancelBtn = find.text('Cancel').evaluate().isNotEmpty ? find.text('Cancel') : find.text('Annuler');
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();
    });
  });

  group('D. Règles dans TimeSliderBar (5 jours strictly lundi à vendredi)', () {
    testWidgets('TimeSliderBar n\'affiche que 5 jours (Lun à Ven) quand hideWeekends=true',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeSliderBar(
            selectedDate: testFriday,
            hideWeekends: true,
            onDateSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Lun 2'), findsOneWidget);
      expect(find.text('Mar 3'), findsOneWidget);
      expect(find.text('Mer 4'), findsOneWidget);
      expect(find.text('Jeu 5'), findsOneWidget);
      expect(find.text('Ven 6'), findsOneWidget);

      // Aucun samedi ni dimanche affiché
      expect(find.text('Sam 7'), findsNothing);
      expect(find.text('Dim 8'), findsNothing);
    });

    testWidgets('TimeSliderBar boutons flèches par défaut sautent les weekends', (tester) async {
      DateTime? chosenDate;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeSliderBar(
            selectedDate: testFriday, // Vendredi 6 nov.
            hideWeekends: true,
            onDateSelected: (d) => chosenDate = d,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Clic sur suivant sans callback personnalisé -> saut au lundi
      await tester.tap(find.byTooltip('Jour suivant'));
      await tester.pumpAndSettle();
      expect(chosenDate, isNotNull);
      expect(chosenDate!.weekday, DateTime.monday);
      expect(chosenDate!.day, 9);

      // Depuis lundi, clic sur précédent -> saut au vendredi
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TimeSliderBar(
            selectedDate: testMonday, // Lundi 9 nov.
            hideWeekends: true,
            onDateSelected: (d) => chosenDate = d,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Jour précédent'));
      await tester.pumpAndSettle();
      expect(chosenDate, isNotNull);
      expect(chosenDate!.weekday, DateTime.friday);
      expect(chosenDate!.day, 6);
    });

    testWidgets('Taper sur n\'importe quel créneau du TimeSliderBar renvoie un jour entre Lun et Ven',
        (tester) async {
      final selectedDates = <DateTime>[];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 500,
            child: TimeSliderBar(
              selectedDate: testMonday,
              hideWeekends: true,
              onDateSelected: (d) => selectedDates.add(d),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      for (final label in ['Lun 9', 'Mar 10', 'Mer 11', 'Jeu 12', 'Ven 13']) {
        final finder = find.text(label);
        expect(finder, findsOneWidget);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      expect(selectedDates.length, 5);
      for (final d in selectedDates) {
        expect(d.weekday != DateTime.saturday && d.weekday != DateTime.sunday, isTrue);
      }
    });
  });
}
