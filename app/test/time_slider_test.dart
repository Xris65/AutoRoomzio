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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TimeSliderBar - Weekly Time-Slider Widget Tests', () {
    // 2026-10-19 is a Monday
    final monday = DateTime(2026, 10, 19);

    testWidgets('1. Displays short labels for week days (Lun 19 to Ven 23) when hideWeekends is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSliderBar(
              selectedDate: monday,
              hideWeekends: true,
              onDateSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lun 19'), findsOneWidget);
      expect(find.text('Mar 20'), findsOneWidget);
      expect(find.text('Mer 21'), findsOneWidget);
      expect(find.text('Jeu 22'), findsOneWidget);
      expect(find.text('Ven 23'), findsOneWidget);

      // Weekends should not be visible
      expect(find.text('Sam 24'), findsNothing);
      expect(find.text('Dim 25'), findsNothing);
    });

    testWidgets('2. Displays 7 days including weekend when hideWeekends is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSliderBar(
              selectedDate: monday,
              hideWeekends: false,
              onDateSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lun 19'), findsOneWidget);
      expect(find.text('Ven 23'), findsOneWidget);
      expect(find.text('Sam 24'), findsOneWidget);
      expect(find.text('Dim 25'), findsOneWidget);
    });

    testWidgets('3. Always displays weekend if selectedDate is on a weekend even with hideWeekends=true', (tester) async {
      final saturday = DateTime(2026, 10, 24);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSliderBar(
              selectedDate: saturday,
              hideWeekends: true,
              onDateSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sam 24'), findsOneWidget);
      expect(find.text('Dim 25'), findsOneWidget);
    });

    testWidgets('4. Tapping a day slot triggers onDateSelected callback', (tester) async {
      DateTime? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSliderBar(
              selectedDate: monday,
              hideWeekends: true,
              onDateSelected: (d) => selected = d,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mer 21'));
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.day, equals(21));
      expect(selected!.month, equals(10));
    });

    testWidgets('5. Dragging horizontally across the slider updates the selected day', (tester) async {
      final selectedDates = <DateTime>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: TimeSliderBar(
                selectedDate: monday,
                hideWeekends: true,
                onDateSelected: (d) => selectedDates.add(d),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final firstDayFinder = find.text('Lun 19');
      expect(firstDayFinder, findsOneWidget);

      // Drag from Monday towards the right
      await tester.drag(firstDayFinder, const Offset(250, 0));
      await tester.pumpAndSettle();

      expect(selectedDates, isNotEmpty);
      expect(selectedDates.last.day, greaterThan(19));
    });

    testWidgets('6. Displays discrete reservation badges for booked and pending dates', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: TimeSliderBar(
                selectedDate: monday,
                hideWeekends: true,
                bookedDates: const {'2026-10-20'},
                pendingDates: const {'2026-10-22'},
                onDateSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Confirmed badge "Bureau" and pending badge "Attente"
      expect(find.text('Bureau'), findsOneWidget);
      expect(find.text('Attente'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsOneWidget);
    });

    testWidgets('7. Previous, next, and today navigation controls work seamlessly', (tester) async {
      bool prevCalled = false;
      bool nextCalled = false;
      bool todayCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimeSliderBar(
              selectedDate: DateTime(2026, 1, 1),
              hideWeekends: true,
              onDateSelected: (_) {},
              onPreviousDay: () => prevCalled = true,
              onNextDay: () => nextCalled = true,
              onToday: () => todayCalled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Jour précédent'));
      expect(prevCalled, isTrue);

      await tester.tap(find.byTooltip('Jour suivant'));
      expect(nextCalled, isTrue);

      await tester.tap(find.text("Aujourd'hui"));
      expect(todayCalled, isTrue);
    });

    testWidgets('8. TeamMapScreen populates occupancy cache and serves cached occupancy data', (tester) async {
      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-token',
        'site_id': 'site-1',
        'floor_id': 'fl-1',
      });

      final client = MockClient((request) async {
        final uri = request.url.toString();
        if (uri.contains('/sites/site-1/floors/fl-1/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'B01', 'isReservable': true}
          ]), 200);
        }
        if (uri.contains('/sites/site-1/floors/fl-1/plan')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'properties': {'type': 'room', 'name': 'Room 1'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [
                      [0.0, 0.0],
                      [100.0, 0.0],
                      [100.0, 100.0],
                      [0.0, 100.0],
                      [0.0, 0.0]
                    ]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (uri.contains('/floors/fl-1/occupants') || uri.contains('occupancy')) {
          return http.Response(jsonEncode([
            {
              'workspaceId': 'ws-1',
              'occupantName': 'Alice Test',
              'occupantEmail': 'alice@example.com',
              'isMe': false,
            }
          ]), 200);
        }
        if (uri.contains('/sites')) {
          return http.Response(jsonEncode([
            {'id': 'site-1', 'name': 'Site 1'}
          ]), 200);
        }
        if (uri.contains('/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'}
          ]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: api,
          storageService: storage,
          initialDate: monday,
          initialSiteId: 'site-1',
          initialFloorId: 'fl-1',
        ),
      ));
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(TeamMapScreen));
      final cache = state.occupancyCache as Map<String, dynamic>;
      expect(cache, isNotEmpty);
      expect(cache.containsKey('fl-1_2026-10-19'), isTrue);

      // Tap Mar 20, then tap back Lun 19
      await tester.tap(find.text('Mar 20'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lun 19'));
      await tester.pumpAndSettle();

      expect(cache.containsKey('fl-1_2026-10-19'), isTrue);
    });
  });
}
