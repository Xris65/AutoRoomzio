import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Evolution 2.1 - StorageService & HomeScreen Settings Toggle', () {
    test('showFavoriteWeekIndicators defaults to true and persists updates', () async {
      final storage = StorageService();
      expect(await storage.getShowFavoriteWeekIndicators(), isTrue);

      await storage.saveShowFavoriteWeekIndicators(false);
      expect(await storage.getShowFavoriteWeekIndicators(), isFalse);

      await storage.saveShowFavoriteWeekIndicators(true);
      expect(await storage.getShowFavoriteWeekIndicators(), isTrue);
    });

    testWidgets('HomeScreen Settings tab toggles showFavoriteWeekIndicators', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveShowAutomation(true);
      await storage.saveShowStats(true);

      final client = MockClient((req) async => http.Response('[]', 200));
      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Paramètres'));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('toggle_favorite_week_indicators'));
      await tester.scrollUntilVisible(toggle, 200);
      expect(toggle, findsOneWidget);
      expect(find.text('Présence des favoris sur la semaine'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(await storage.getShowFavoriteWeekIndicators(), isFalse);
    });
  });

  group('Evolution 2.2 - TeamMapScreen Day Badges & Semaine de mes favoris Modal', () {
    testWidgets('Displays unique ⭐ N badges on TimeSliderBar and opens Semaine de mes favoris modal', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final monday = DateTime(2026, 10, 12); // Monday
      const monStr = '2026-10-12';
      const tueStr = '2026-10-13';
      const wedStr = '2026-10-14';

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveSiteId('site-1');
      await storage.saveFloorId('fl-1');
      await storage.saveHideWeekends(true);
      await storage.saveShowFavoriteWeekIndicators(true);

      await storage.saveFavoriteColleagues([
        const Colleague(id: 'u-alice', name: 'Alice Martin', email: 'alice@corp.com', isFavorite: true),
        const Colleague(id: 'u-bob', name: 'Bob Durand', email: 'bob@corp.com', isFavorite: true),
      ]);

      // Pre-cache floor plan, workspaces, and Tuesday/Wednesday occupants
      await storage.saveFloorPlanData('fl-1', {
        'features': [
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-a12', 'name': 'A-12', 'workspaceType': 'Desk'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
              ]
            }
          },
          {
            'type': 'Feature',
            'properties': {'workspaceId': 'ws-b05', 'name': 'B-05', 'workspaceType': 'Desk'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [[70.0, 10.0], [110.0, 10.0], [110.0, 50.0], [70.0, 50.0], [70.0, 10.0]]
              ]
            }
          },
        ]
      });
      await storage.saveFloorWorkspaces('fl-1', [
        {'id': 'ws-a12', 'name': 'A-12', 'isBookable': true},
        {'id': 'ws-b05', 'name': 'B-05', 'isBookable': true},
      ]);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode(await storage.getFloorPlanData('fl-1')), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          final body = jsonDecode(req.body);
          final reqDate = body['date']?.toString();
          if (reqDate == monStr) {
            // Monday: Alice seated on A-12 (also test deduplication if returned on two keys)
            return http.Response(jsonEncode({
              'data': [
                {
                  'workspaceId': 'ws-a12',
                  'status': 'Reserved',
                  'bookedTimeSlot': {
                    'user': {'id': 'u-alice', 'name': 'Alice Martin', 'email': 'alice@corp.com'}
                  }
                }
              ]
            }), 200);
          }
          if (reqDate == tueStr) {
            // Tuesday: Alice AND Bob
            return http.Response(jsonEncode({
              'data': [
                {
                  'workspaceId': 'ws-a12',
                  'status': 'Reserved',
                  'bookedTimeSlot': {
                    'user': {'id': 'u-alice', 'name': 'Alice Martin', 'email': 'alice@corp.com'}
                  }
                },
                {
                  'workspaceId': 'ws-b05',
                  'status': 'Reserved',
                  'bookedTimeSlot': {
                    'user': {'id': 'u-bob', 'name': 'Bob Durand', 'email': 'bob@corp.com'}
                  }
                }
              ]
            }), 200);
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-a12', 'name': 'A-12', 'isBookable': true},
            {'id': 'ws-b05', 'name': 'B-05', 'isBookable': true},
          ]), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            apiService: api,
            storageService: storage,
            initialDate: monday,
            initialSiteId: 'site-1',
            initialFloorId: 'fl-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Monday has 1 unique favorite (even though occupants map has ws-a12 + lowercase keys)
      expect(find.byKey(const ValueKey('week_day_fav_badge_$monStr')), findsOneWidget);
      expect(find.text('⭐ 1'), findsOneWidget);

      // Tuesday has 2 unique favorites
      expect(find.byKey(const ValueKey('week_day_fav_badge_$tueStr')), findsOneWidget);
      expect(find.text('⭐ 2'), findsOneWidget);

      // Wednesday has 0 favorites -> no badge
      expect(find.byKey(const ValueKey('week_day_fav_badge_$wedStr')), findsNothing);

      // Favorites week summary button is visible with explicit Calendar + Star composite icon
      final summaryBtn = find.byKey(const ValueKey('favorites_week_summary_button'));
      expect(summaryBtn, findsOneWidget);
      expect(find.byIcon(Icons.view_week_rounded), findsNothing);
      expect(
        find.descendant(of: summaryBtn, matching: find.byIcon(Icons.calendar_month_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summaryBtn, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget,
      );

      // Tap summary button -> open "Semaine de mes favoris" modal
      await tester.tap(summaryBtn);
      await tester.pumpAndSettle();

      expect(find.text('Semaine de mes favoris'), findsOneWidget);
      expect(find.text('Alice Martin'), findsWidgets);
      expect(find.text('Bob Durand'), findsWidgets);
      expect(find.text('A-12'), findsWidgets);
      expect(find.text('B-05'), findsWidgets);

      // Tap Bob's Tuesday cell (B-05) -> closes modal and jumps to Tuesday + centers on B-05
      final bobTueCell = find.byKey(const ValueKey('fav_week_cell_u-bob_$tueStr'));
      expect(bobTueCell, findsOneWidget);
      await tester.tap(bobTueCell);
      await tester.pumpAndSettle();

      expect(find.text('Semaine de mes favoris'), findsNothing);
      expect(find.textContaining('Mardi 13 oct.'), findsOneWidget);

      // Re-open modal and disable favorite week indicators from inside modal
      await tester.tap(summaryBtn);
      await tester.pumpAndSettle();

      final modalSwitch = find.byKey(const ValueKey('modal_toggle_favorite_week_indicators'));
      expect(modalSwitch, findsOneWidget);
      await tester.tap(modalSwitch);
      await tester.pumpAndSettle();

      expect(await storage.getShowFavoriteWeekIndicators(), isFalse);
      // Underlying UI immediately hides day-bar badges, while keeping the AppBar button visible
      expect(find.byKey(const ValueKey('week_day_fav_badge_$monStr')), findsNothing);
      expect(find.byKey(const ValueKey('week_day_fav_badge_$tueStr')), findsNothing);
      expect(summaryBtn, findsOneWidget);
    });

    testWidgets(
        'When showFavoriteWeekIndicators is false at startup, day badges are hidden but summary button stays visible and can re-enable them',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final monday = DateTime(2026, 10, 12);
      const monStr = '2026-10-12';
      const tueStr = '2026-10-13';

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveSiteId('site-1');
      await storage.saveFloorId('fl-1');
      await storage.saveShowFavoriteWeekIndicators(false);
      await storage.saveFavoriteColleagues([
        const Colleague(id: 'u-alice', name: 'Alice Martin', email: 'alice@corp.com', isFavorite: true),
      ]);
      await storage.saveFloorOccupants('fl-1', monStr, {
        'ws-a12': const DeskOccupant(
          workspaceId: 'ws-a12',
          occupantId: 'u-alice',
          occupantName: 'Alice Martin',
          occupantEmail: 'alice@corp.com',
        ),
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({'features': []}), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          final body = jsonDecode(req.body);
          final reqDate = body['date']?.toString();
          if (reqDate == tueStr) {
            return http.Response(jsonEncode({
              'data': [
                {
                  'workspaceId': 'ws-a12',
                  'status': 'Reserved',
                  'bookedTimeSlot': {
                    'user': {'id': 'u-alice', 'name': 'Alice Martin', 'email': 'alice@corp.com'}
                  }
                }
              ]
            }), 200);
          }
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([{'id': 'ws-a12', 'name': 'A-12', 'isBookable': true}]), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: TeamMapScreen(
            apiService: api,
            storageService: storage,
            initialDate: monday,
            initialSiteId: 'site-1',
            initialFloorId: 'fl-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Day-bar badges are hidden when showFavoriteWeekIndicators is false
      expect(find.byKey(const ValueKey('week_day_fav_badge_$monStr')), findsNothing);
      expect(find.byKey(const ValueKey('week_day_fav_badge_$tueStr')), findsNothing);

      // AppBar button remains present, clickable, and uses Calendar + Star icons (never view_week_rounded)
      final summaryBtn = find.byKey(const ValueKey('favorites_week_summary_button'));
      expect(summaryBtn, findsOneWidget);
      expect(find.byIcon(Icons.view_week_rounded), findsNothing);
      expect(
        find.descendant(of: summaryBtn, matching: find.byIcon(Icons.calendar_month_rounded)),
        findsOneWidget,
      );
      final starInButtonFinder = find.descendant(
        of: summaryBtn,
        matching: find.byIcon(Icons.star_rounded),
      );
      expect(starInButtonFinder, findsOneWidget);
      final dimmedStarIcon = tester.widget<Icon>(starInButtonFinder);
      expect(dimmedStarIcon.color?.a, closeTo(0.55, 0.02));

      // Tapping the button opens the modal with the week's favorites even while badges are off
      await tester.tap(summaryBtn);
      await tester.pumpAndSettle();

      expect(find.text('Semaine de mes favoris'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.calendar_month_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('Alice Martin'), findsWidgets);
      expect(find.text('A-12'), findsWidgets);

      // Re-enabling the switch inside the modal immediately restores the day-bar badges
      final modalSwitch = find.byKey(const ValueKey('modal_toggle_favorite_week_indicators'));
      expect(modalSwitch, findsOneWidget);
      await tester.tap(modalSwitch);
      await tester.pumpAndSettle();

      expect(await storage.getShowFavoriteWeekIndicators(), isTrue);
      expect(find.byKey(const ValueKey('week_day_fav_badge_$monStr')), findsOneWidget);
      expect(find.byKey(const ValueKey('week_day_fav_badge_$tueStr')), findsOneWidget);
      expect(find.text('⭐ 1'), findsNWidgets(2));

      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

      final activeStarIcon = tester.widget<Icon>(starInButtonFinder);
      expect(activeStarIcon.color?.a, closeTo(1.0, 0.01));
    });
  });
}
