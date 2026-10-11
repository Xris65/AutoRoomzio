import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Friday Nov 6, 2026 (far from current date so diff != 0, 1, -1)
  final friday = DateTime(2026, 11, 6);

  RoomzApiService createMockApi({Function(String url, String body)? onPost}) {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path.contains('/connect/token')) {
        return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
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
      if (path.contains('/workspaces') && req.method == 'GET') {
        return http.Response(jsonEncode([
          {'id': 'ws-1', 'name': 'B01-01', 'isBookable': true}
        ]), 200);
      }
      if (path.contains('/bookings') && req.method == 'POST') {
        if (onPost != null) {
          onPost(req.url.toString(), req.body);
        }
        return http.Response(jsonEncode({'id': 'res-1'}), 200);
      }
      if (path.contains('/buildings') && path.contains('/floors')) {
        return http.Response(jsonEncode([
          {'id': 'fl-1', 'name': 'Étage 1'}
        ]), 200);
      }
      return http.Response('[]', 200);
    });
    return RoomzApiService(client: client);
  }

  group('1. Navigation par flèches < et > sur le plan d\'équipe', () {
    testWidgets('< et > avancent/reculent TOUJOURS d\'un jour sans jamais sauter les weekends (même si hideWeekends = true)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': true, // Même avec l'option activée, < et > ne sautent jamais les weekends
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: friday, // Vendredi 6 nov.
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('Vendredi 6 nov.'), findsOneWidget);

      final nextBtn = find.byTooltip('Jour suivant');
      final prevBtn = find.byTooltip('Jour précédent');

      // Click > : Vendredi 6 nov. -> Samedi 7 nov.
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Samedi 7 nov.'), findsOneWidget);

      // Click > : Samedi 7 nov. -> Dimanche 8 nov.
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dimanche 8 nov.'), findsOneWidget);

      // Click > : Dimanche 8 nov. -> Lundi 9 nov.
      await tester.tap(nextBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Lundi 9 nov.'), findsOneWidget);

      // Click < : Lundi 9 nov. -> Dimanche 8 nov.
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dimanche 8 nov.'), findsOneWidget);

      // Click < : Dimanche 8 nov. -> Samedi 7 nov.
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Samedi 7 nov.'), findsOneWidget);

      // Click < : Samedi 7 nov. -> Vendredi 6 nov.
      await tester.tap(prevBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Vendredi 6 nov.'), findsOneWidget);
    });
  });

  group('2. Réservation de bureaux le weekend selon les paramètres', () {
    testWidgets('Si "Masquer les weekends" est DÉSACTIVÉ (false) : la réservation le weekend est TOTALEMENT AUTORISÉE', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final daysUntilSat = (DateTime.saturday - now.weekday + 7) % 7;
      final targetSat = now.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
      final saturdayDate = DateTime(targetSat.year, targetSat.month, targetSat.day);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': false, // Option DÉSACTIVÉE
      });

      bool reserveCalled = false;
      final api = createMockApi(onPost: (url, body) {
        if (url.contains('/bookings')) {
          reserveCalled = true;
        }
      });
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: saturdayDate,
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      final deskFinder = find.text('01');
      expect(deskFinder, findsWidgets);
      await tester.tap(deskFinder.first);
      await tester.pumpAndSettle();

      // "Réservations fermées le weekend" ne doit PAS être affiché
      expect(find.text("Réservations fermées le weekend"), findsNothing);

      // Les boutons de réservation DOIVENT être présents
      final reserveMeBtn = find.text("Réserver ce bureau pour moi");
      expect(reserveMeBtn, findsOneWidget);
      expect(find.text("Réserver ce bureau pour un collègue"), findsOneWidget);

      // La réservation fonctionne sans être bloquée par un snackbar
      await tester.tap(reserveMeBtn);
      await tester.pumpAndSettle();

      expect(find.text("Les réservations sont fermées le weekend"), findsNothing);
      expect(reserveCalled, isTrue);
    });

    testWidgets('Si "Masquer les weekends" est ACTIVÉ (true) : la réservation le weekend est BLOQUÉE avec mention', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final now = DateTime.now();
      final daysUntilSat = (DateTime.saturday - now.weekday + 7) % 7;
      final targetSat = now.add(Duration(days: daysUntilSat == 0 ? 7 : daysUntilSat));
      final saturdayDate = DateTime(targetSat.year, targetSat.month, targetSat.day);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'refresh_token': 'mock-refresh-token',
        'hide_weekends': true, // Option ACTIVÉE
      });

      final api = createMockApi();
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          initialDate: saturdayDate,
          storageService: storage,
          apiService: api,
        ),
      ));
      await tester.pumpAndSettle();

      final deskFinder = find.text('01');
      expect(deskFinder, findsWidgets);
      await tester.tap(deskFinder.first);
      await tester.pumpAndSettle();

      // "Réservations fermées le weekend" DOIT être affiché
      expect(find.text("Réservations fermées le weekend"), findsOneWidget);

      // Les boutons de réservation sont bloqués
      expect(find.text("Réserver ce bureau pour moi"), findsNothing);
      expect(find.text("Réserver ce bureau pour un collègue"), findsNothing);
    });
  });
}
