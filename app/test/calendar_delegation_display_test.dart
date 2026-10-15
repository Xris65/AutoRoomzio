import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/utils/delegation_display_helper.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Calendar Delegation Display (Bug #2 Fix)', () {
    // ═════════════════════════════════════════════════════════════════════════
    // 1. DelegationDisplayHelper Formatting Logic
    // ═════════════════════════════════════════════════════════════════════════
    group('1. DelegationDisplayHelper.formatDelegationLabel', () {
      test('creator != bookedFor displays "Réservé pour [X] par [Y]"', () {
        final label = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'Alice Dupont',
          bookedFor: 'Bob Martin',
        );
        expect(label, equals('Réservé pour Bob Martin par Alice Dupont'));
      });

      test('delegated for current user displays "Réservé par [Y] pour vous"', () {
        final labelWithFlag = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'Alice Dupont',
          bookedFor: 'Bob Martin',
          isForMe: true,
        );
        expect(labelWithFlag, equals('Réservé par Alice Dupont pour vous'));

        final labelWithVous = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'Alice Dupont',
          bookedFor: 'vous',
        );
        expect(labelWithVous, equals('Réservé par Alice Dupont pour vous'));
      });

      test('delegated by current user displays "Réservé pour [X] par vous"', () {
        final labelWithFlag = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'Alice Dupont',
          bookedFor: 'Bob Martin',
          isByMe: true,
        );
        expect(labelWithFlag, equals('Réservé pour Bob Martin par vous'));

        final labelWithVous = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'vous',
          bookedFor: 'Bob Martin',
        );
        expect(labelWithVous, equals('Réservé pour Bob Martin par vous'));
      });

      test('creator == bookedFor displays "Réservé par [bénéficiaire]" without delegation', () {
        final labelSameName = DelegationDisplayHelper.formatDelegationLabel(
          creator: 'Bob Martin',
          bookedFor: 'Bob Martin',
        );
        expect(labelSameName, equals('Réservé par Bob Martin'));
      });

      test('single party provided displays "Réservé par [name]"', () {
        expect(
          DelegationDisplayHelper.formatDelegationLabel(bookedFor: 'Bob Martin'),
          equals('Réservé par Bob Martin'),
        );
        expect(
          DelegationDisplayHelper.formatDelegationLabel(creator: 'Alice Dupont'),
          equals('Réservé par Alice Dupont'),
        );
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // 2. Slot Extraction from API JSON Payloads
    // ═════════════════════════════════════════════════════════════════════════
    group('2. DelegationDisplayHelper.extractReservationOccupant', () {
      test('extracts delegation when creator and bookedFor maps differ', () {
        final slot = {
          'creator': {'id': 'usr-alice', 'name': 'Alice Dupont'},
          'bookedFor': {'id': 'usr-bob', 'name': 'Bob Martin'},
        };
        final result = DelegationDisplayHelper.extractReservationOccupant(slot);
        expect(result, equals('Réservé pour Bob Martin par Alice Dupont'));
      });

      test('extracts delegation for me when current userId matches bookedFor', () {
        final slot = {
          'creator': {'id': 'usr-alice', 'name': 'Alice Dupont'},
          'bookedFor': {'id': 'usr-me-123', 'name': 'Moi-Même'},
        };
        final result = DelegationDisplayHelper.extractReservationOccupant(
          slot,
          myUserId: 'usr-me-123',
        );
        expect(result, equals('Réservé par Alice Dupont pour vous'));
      });

      test('extracts non-delegated booking as simple occupant name', () {
        final slot = {
          'creator': {'id': 'usr-bob', 'name': 'Bob Martin'},
          'user': {'id': 'usr-bob', 'name': 'Bob Martin'},
        };
        final result = DelegationDisplayHelper.extractReservationOccupant(slot);
        expect(result, equals('Bob Martin'));
      });

      test('supports bookedBy and organizer/owner fallback keys', () {
        final slot = {
          'bookedBy': 'Alice Dupont',
          'owner': {'name': 'Charlie Chaplin', 'id': 'usr-charlie'},
        };
        final result = DelegationDisplayHelper.extractReservationOccupant(slot);
        expect(result, equals('Réservé pour Charlie Chaplin par Alice Dupont'));
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // 3. UI Label Adapters (Subtitles, Cards, Dialogs, Calendar Tiles)
    // ═════════════════════════════════════════════════════════════════════════
    group('3. UI Label Adapters', () {
      test('formatOccupiedSubtitle adapts modal bottom sheet text', () {
        expect(
          DelegationDisplayHelper.formatOccupiedSubtitle('Réservé pour Bob par Alice'),
          equals('Réservé pour Bob par Alice.'),
        );
        expect(
          DelegationDisplayHelper.formatOccupiedSubtitle('Bob Martin'),
          equals('Réservé par Bob Martin.'),
        );
        expect(
          DelegationDisplayHelper.formatOccupiedSubtitle('Bob Martin|Alice Dupont'),
          equals('Réservé pour Bob Martin par Alice Dupont.'),
        );
      });

      test('formatOccupiedHomeSubtitle adapts upcoming cards subtitle', () {
        expect(
          DelegationDisplayHelper.formatOccupiedHomeSubtitle('Réservé pour Bob par Alice'),
          equals('Indisponible (réservé pour Bob par Alice)'),
        );
        expect(
          DelegationDisplayHelper.formatOccupiedHomeSubtitle('Bob Martin'),
          equals('Indisponible (réservé par Bob Martin)'),
        );
      });

      test('formatDelegatedHomeSubtitle adapts delegated cards subtitle', () {
        expect(
          DelegationDisplayHelper.formatDelegatedHomeSubtitle(
            delegateName: 'Bob Martin',
            location: 'Bureau 42',
            creatorName: 'Alice Dupont',
          ),
          equals('Réservé pour Bob Martin par Alice Dupont (Bureau 42)'),
        );

        expect(
          DelegationDisplayHelper.formatDelegatedHomeSubtitle(
            delegateName: 'Bob Martin',
            location: 'Bureau 42',
            creatorName: null,
          ),
          equals('Réservé pour Bob Martin (Bureau 42)'),
        );
      });

      test('formatOccupiedCalendarTooltip formats day cell hover/semantics', () {
        expect(
          DelegationDisplayHelper.formatOccupiedCalendarTooltip('Réservé pour Bob par Alice'),
          equals('Réservé pour Bob par Alice'),
        );
        expect(
          DelegationDisplayHelper.formatOccupiedCalendarTooltip('Bob Martin'),
          equals('Réservé par Bob Martin'),
        );
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // 4. HomeScreen Calendar and Dialog Rendering Test
    // ═════════════════════════════════════════════════════════════════════════
    group('4. HomeScreen UI Verification', () {
      testWidgets('Renders explicit delegation in upcoming cards and date tap sheet', (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final now = DateTime.now();
        // Pick a weekday within 13 days
        var targetDate = now.add(const Duration(days: 2));
        if (targetDate.weekday == DateTime.saturday) targetDate = targetDate.add(const Duration(days: 2));
        if (targetDate.weekday == DateTime.sunday) targetDate = targetDate.add(const Duration(days: 1));
        final targetDateStr = targetDate.toIso8601String().split('T').first;

        SharedPreferences.setMockInitialValues({
          'refresh_token': 'dummy_refresh',
          'auth_token': 'dummy_access',
          'workspace_id': 'ws-100',
          'workspace_name': 'Mon Bureau Habituel',
          'floor_id': 'fl-1',
          'requested_dates': <String>[],
          'booked_dates': <String>[],
          'selected_days': ['1', '2', '3', '4', '5'],
          'automation_enabled': true,
          'initial_tab': 0,
        });

        final client = MockClient((req) async {
          if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
            return http.Response(jsonEncode({'access_token': 'mock-access', 'refresh_token': 'mock-refresh'}), 200);
          }
          if (req.url.path.contains('/users/current/bookings')) {
            return http.Response(jsonEncode({'bookings': []}), 200);
          }
          if (req.url.path.contains('/users/current')) {
            return http.Response(jsonEncode({'id': 'u-current-user', 'name': 'Current User'}), 200);
          }
          if (req.url.path.contains('/workspaces/calendars')) {
            // Return occupied desk only for the targeted date
            if (req.body.contains(targetDateStr)) {
              return http.Response(jsonEncode({
                'data': [
                  {
                    'id': 'ws-100',
                    'workspaceId': 'ws-100',
                    'status': 'Reserved',
                    'bookedTimeSlot': {
                      'creator': {'name': 'Alice Dupont', 'id': 'u-alice'},
                      'bookedFor': {'name': 'Bob Martin', 'id': 'u-bob'},
                    }
                  }
                ]
              }), 200);
            }
            return http.Response(jsonEncode({'data': []}), 200);
          }
          return http.Response('[]', 200);
        });

        final api = RoomzApiService(client: client);
        final storage = StorageService();

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(apiService: api, storageService: storage),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        // 1. Verify upcoming card shows "Indisponible (réservé pour Bob Martin par Alice Dupont)"
        final cardFinder = find.text('Indisponible (réservé pour Bob Martin par Alice Dupont)');
        expect(cardFinder, findsOneWidget);

        // 2. Scroll to card and tap it to open details bottom sheet directly
        await tester.ensureVisible(cardFinder);
        await tester.tap(cardFinder);
        await tester.pumpAndSettle();

        // 3. Verify the bottom sheet displays: "Réservé pour Bob Martin par Alice Dupont."
        expect(
          find.text('Réservé pour Bob Martin par Alice Dupont.'),
          findsOneWidget,
        );

        // Close bottom sheet
        Navigator.pop(tester.element(find.text('Réservé pour Bob Martin par Alice Dupont.')));
        await tester.pumpAndSettle();

        // 4. Switch to Calendar tab (index 1)
        await tester.tap(find.text('Calendrier'));
        await tester.pumpAndSettle();

        // 5. Verify calendar tile has tooltip label
        expect(
          find.byTooltip('Réservé pour Bob Martin par Alice Dupont'),
          findsWidgets,
        );
      });
    });
  });
}
