import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/background_task.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/setup_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Evolution 1.1 - AutomationRule & StorageService Persistence/Migration', () {
    test('AutomationRule serializes, deserializes, normalizes days, and copyWith works', () {
      const rule = AutomationRule(
        id: 'ws-1',
        siteId: 'site-1',
        floorId: 'fl-1',
        workspaceId: 'ws-1',
        workspaceName: 'Bureau A-10',
        days: [5, 1, 3, 1, 9, 0],
      );

      final json = rule.toJson();
      expect(json['days'], equals([1, 3, 5]));

      final restored = AutomationRule.fromJson(json);
      expect(restored.id, equals('ws-1'));
      expect(restored.siteId, equals('site-1'));
      expect(restored.floorId, equals('fl-1'));
      expect(restored.workspaceId, equals('ws-1'));
      expect(restored.workspaceName, equals('Bureau A-10'));
      expect(restored.days, equals([1, 3, 5]));

      final updated = restored.copyWith(workspaceName: 'Bureau B-20', days: [4, 2]);
      expect(updated.workspaceName, equals('Bureau B-20'));
      expect(updated.days, equals([2, 4]));
    });

    test('Migrates legacy v1.6 config to automation_rules_v1 seamlessly and preserves empty state once deleted', () async {
      SharedPreferences.setMockInitialValues({
        'site_id': 'site-hq',
        'floor_id': 'fl-2',
        'workspace_id': 'ws-legacy',
        'workspace_name': 'Desk Legacy 42',
        'selected_days': ['2', '4'],
      });

      final storage = StorageService();
      final rules = await storage.getAutomationRules();

      expect(rules.length, equals(1));
      expect(rules.first.workspaceId, equals('ws-legacy'));
      expect(rules.first.workspaceName, equals('Desk Legacy 42'));
      expect(rules.first.siteId, equals('site-hq'));
      expect(rules.first.floorId, equals('fl-2'));
      expect(rules.first.days, equals([2, 4]));
      expect(await storage.hasAutomationRules(), isTrue);

      // Explicitly saving empty rules must NOT re-trigger legacy migration
      await storage.saveAutomationRules([]);
      final afterDelete = await storage.getAutomationRules();
      expect(afterDelete, isEmpty);
      expect(await storage.getDays(), isEmpty);
    });

    test('Enforces weekday uniqueness invariant and keeps selected_days synchronized', () async {
      final storage = StorageService();
      const ruleA = AutomationRule(
        id: 'ws-a',
        siteId: 's1',
        floorId: 'f1',
        workspaceId: 'ws-a',
        workspaceName: 'Place A',
        days: [1, 2, 3],
      );
      const ruleB = AutomationRule(
        id: 'ws-b',
        siteId: 's1',
        floorId: 'f2',
        workspaceId: 'ws-b',
        workspaceName: 'Place B',
        days: [2, 3, 4, 5],
      );

      await storage.saveAutomationRules([ruleA, ruleB]);

      final saved = await storage.getAutomationRules();
      expect(saved.length, equals(2));
      expect(saved[0].days, equals([1, 2, 3]));
      // Duplicate days 2 & 3 must only be kept by one rule
      expect(saved[1].days, equals([4, 5]));
      expect(await storage.getDays(), equals([1, 2, 3, 4, 5]));

      final map = await storage.getWeekdayAutomationMap();
      expect(map[1]?.workspaceId, equals('ws-a'));
      expect(map[4]?.workspaceId, equals('ws-b'));
      expect((await storage.getAutomationRuleForWeekday(2))?.workspaceId, equals('ws-a'));
      expect(await storage.getAutomationRuleForWeekday(7), isNull);
    });

    test('Strict decoupling: resetWorkspace, saveWorkspaceId, saveWorkspaceName never touch automation_rules_v1', () async {
      final storage = StorageService();
      await storage.saveSiteId('site-1');
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-home');
      await storage.saveWorkspaceName('Home Desk');

      const rule = AutomationRule(
        id: 'ws-auto',
        siteId: 'site-1',
        floorId: 'fl-2',
        workspaceId: 'ws-auto',
        workspaceName: 'Auto Desk',
        days: [1, 3, 5],
      );
      await storage.saveAutomationRules([rule]);

      await storage.saveWorkspaceId('ws-new-home');
      await storage.saveWorkspaceName('New Home Desk');
      var rules = await storage.getAutomationRules();
      expect(rules.length, equals(1));
      expect(rules.first.workspaceId, equals('ws-auto'));

      await storage.resetWorkspace();
      expect(await storage.getWorkspaceId(), isNull);
      expect(await storage.getWorkspaceName(), isNull);
      rules = await storage.getAutomationRules();
      expect(rules.length, equals(1));
      expect(rules.first.workspaceId, equals('ws-auto'));
      expect(rules.first.days, equals([1, 3, 5]));
    });
  });

  group('Evolution 1.2 - SetupScreen pickOnly mode', () {
    testWidgets('SetupScreen(pickOnly: true) returns selection without modifying default home workspace in StorageService', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-home',
        'floor_id': 'fl-home',
        'workspace_id': 'ws-home',
        'workspace_name': 'Mon Bureau Accueil',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/buildings')) {
          return http.Response(jsonEncode([
            {'id': 'site-home', 'name': 'Site Accueil'},
            {'id': 'site-other', 'name': 'Site Annexe'},
          ]), 200);
        }
        if (path.contains('/site-other/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-other', 'name': 'Étage Annexe'},
          ]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-home', 'name': 'Étage Accueil'},
          ]), 200);
        }
        if (path.contains('/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-picked', 'name': 'Annexe-07', 'isReservable': true},
          ]), 200);
        }
        if (path.endsWith('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-picked', 'name': 'Annexe-07', 'workspaceType': 'Desk'},
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
        return http.Response('[]', 200);
      });

      final storage = StorageService();
      final api = RoomzApiService(client: client, storage: storage);
      Map<String, String>? pickedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  pickedResult = await Navigator.of(context).push<Map<String, String>>(
                    MaterialPageRoute(
                      builder: (_) => SetupScreen(
                        accessToken: 'tok',
                        apiService: api,
                        storageService: storage,
                        pickOnly: true,
                        titleOverride: 'Ajouter une place automatisée',
                      ),
                    ),
                  );
                },
                child: const Text('Pick Desk'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick Desk'));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter une place automatisée'), findsOneWidget);

      // Go back to step 0 and select Site Annexe -> Étage Annexe
      await tester.tap(find.text('Bâtiment').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Site Annexe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Étage Annexe'));
      await tester.pumpAndSettle();

      // Verify storage site_id and floor_id were NOT overwritten during pickOnly
      expect(await storage.getSiteId(), equals('site-home'));
      expect(await storage.getFloorId(), equals('fl-home'));

      final viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      viewer.onSelected({'id': 'ws-picked', 'name': 'Annexe-07'});
      await tester.pumpAndSettle();

      expect(pickedResult, isNotNull);
      expect(pickedResult!['siteId'], equals('site-other'));
      expect(pickedResult!['floorId'], equals('fl-other'));
      expect(pickedResult!['workspaceId'], equals('ws-picked'));
      expect(pickedResult!['workspaceName'], equals('Annexe-07'));

      // Home storage remains completely untouched
      expect(await storage.getSiteId(), equals('site-home'));
      expect(await storage.getFloorId(), equals('fl-home'));
      expect(await storage.getWorkspaceId(), equals('ws-home'));
      expect(await storage.getWorkspaceName(), equals('Mon Bureau Accueil'));
    });
  });

  group('Evolution 1.5 - Multi-Desk Engine in runBackgroundBookingAutomation', () {
    test('Reserves different desks per weekday even when default home desk is null, and prioritizes requestedDates', () async {
      final storage = StorageService();
      await storage.saveRefreshToken('mock-token');
      await storage.saveHideWeekends(true);
      await storage.saveSkipPublicHolidays(false);

      // Strictly NO default home workspaceId / floorId configured!
      expect(await storage.getWorkspaceId(), isNull);

      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-mon',
          siteId: 's1',
          floorId: 'f1',
          workspaceId: 'ws-mon',
          workspaceName: 'Bureau Lundi',
          days: [1], // Monday
        ),
        const AutomationRule(
          id: 'ws-tue',
          siteId: 's1',
          floorId: 'f2',
          workspaceId: 'ws-tue',
          workspaceName: 'Bureau Mardi',
          days: [2], // Tuesday
        ),
      ]);

      // Sunday 2026-10-11 -> day +1 = Monday 2026-10-12, day +2 = Tuesday 2026-10-13
      final now = DateTime(2026, 10, 11);
      // Override Tuesday 2026-10-13 with a one-off requested desk
      await storage.addRequestedDate(
        '2026-10-13',
        workspaceId: 'ws-override',
        workspaceName: 'Bureau Ponctuel',
      );

      final bookingsMade = <String, String>{};
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token') || req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          final body = jsonDecode(req.body);
          bookingsMade[body['localDate'].toString()] = body['workspaceId'].toString();
          return http.Response(jsonEncode({'id': 'ok'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);
      final count = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
      );

      // Across 13 days from Sunday Oct 11:
      // Mon Oct 12 (ws-mon), Tue Oct 13 (ws-override), Mon Oct 19 (ws-mon), Tue Oct 20 (ws-tue) => 4 bookings
      expect(count, equals(4));
      expect(bookingsMade['2026-10-12'], equals('ws-mon'));
      expect(bookingsMade['2026-10-13'], equals('ws-override'));
      expect(bookingsMade['2026-10-19'], equals('ws-mon'));
      expect(bookingsMade['2026-10-20'], equals('ws-tue'));

      final elsewhereMap = await storage.getBookedElsewhereMap();
      expect(elsewhereMap['2026-10-12'], equals('Bureau Lundi'));
      expect(elsewhereMap['2026-10-13'], equals('Bureau Ponctuel'));
      expect(await storage.getRequestedDates(), isEmpty);
    });

    test('When default workspaceId is set, splits bookings between booked_dates and booked_elsewhere_map', () async {
      final storage = StorageService();
      await storage.saveRefreshToken('mock-token');
      await storage.saveFloorId('f1');
      await storage.saveWorkspaceId('ws-default');
      await storage.saveWorkspaceName('Mon Bureau Défaut');
      await storage.saveHideWeekends(true);
      await storage.saveSkipPublicHolidays(false);

      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-default',
          siteId: 's1',
          floorId: 'f1',
          workspaceId: 'ws-default',
          workspaceName: 'Mon Bureau Défaut',
          days: [1], // Monday
        ),
        const AutomationRule(
          id: 'ws-other',
          siteId: 's1',
          floorId: 'f2',
          workspaceId: 'ws-other',
          workspaceName: 'Autre Salle',
          days: [3], // Wednesday
        ),
      ]);

      final now = DateTime(2026, 10, 11); // Sun -> Mon Oct 12, Wed Oct 14, Mon Oct 19, Wed Oct 21
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'me-1'}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          return http.Response(jsonEncode({'id': 'ok'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);
      final count = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
      );

      expect(count, equals(4));
      final bookedHere = await storage.getBookedDates();
      expect(bookedHere, containsAll(['2026-10-12', '2026-10-19']));
      expect(bookedHere, isNot(contains('2026-10-14')));

      final elsewhere = await storage.getBookedElsewhereMap();
      expect(elsewhere['2026-10-14'], equals('Autre Salle'));
      expect(elsewhere['2026-10-21'], equals('Autre Salle'));
    });
  });

  group('Evolution 1.3 & 1.4 - HomeScreen Multi-Place UI & TeamMapScreen Shortcut', () {
    testWidgets('HomeScreen Automate tab shows weekly summary, conflict warning, replacement dialog, and deletion', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveWorkspaceId('ws-a');
      await storage.saveWorkspaceName('Desk A');
      await storage.saveFloorId('fl-1');
      await storage.saveInitialTab(2); // Automate tab
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-a',
          siteId: 's1',
          floorId: 'fl-1',
          workspaceId: 'ws-a',
          workspaceName: 'Desk A',
          days: [1], // Monday
        ),
        const AutomationRule(
          id: 'ws-b',
          siteId: 's1',
          floorId: 'fl-1',
          workspaceId: 'ws-b',
          workspaceName: 'Desk B',
          days: [2], // Tuesday
        ),
      ]);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Weekly summary banner visible
      expect(find.byKey(const ValueKey('weekly_summary_banner')), findsOneWidget);
      expect(find.text('Ma semaine type'), findsOneWidget);
      expect(find.byKey(const ValueKey('add_automation_rule_button')), findsOneWidget);

      // Desk A card shows conflict chip for Tuesday ("Mar • Desk B")
      final conflictChip = find.byKey(const ValueKey('rule_day_chip_ws-a_2'));
      expect(conflictChip, findsOneWidget);
      expect(find.descendant(of: conflictChip, matching: find.text('Mar • Desk B')), findsOneWidget);
      expect(find.descendant(of: conflictChip, matching: find.byIcon(Icons.swap_horiz_rounded)), findsOneWidget);

      // Tap conflict chip -> confirmation dialog opens
      await tester.ensureVisible(conflictChip);
      await tester.tap(conflictChip);
      await tester.pumpAndSettle();

      expect(find.text('Conflit sur le Mardi'), findsOneWidget);
      expect(find.textContaining('Desk B'), findsWidgets);
      expect(find.byKey(const ValueKey('confirm_replace_day_button')), findsOneWidget);

      // Confirm replacement
      await tester.tap(find.byKey(const ValueKey('confirm_replace_day_button')));
      await tester.pumpAndSettle();

      // Verify storage updated: Desk A now has [1, 2], Desk B has []
      final rulesAfterReplace = await storage.getAutomationRules();
      expect(rulesAfterReplace.firstWhere((r) => r.workspaceId == 'ws-a').days, equals([1, 2]));
      expect(rulesAfterReplace.firstWhere((r) => r.workspaceId == 'ws-b').days, isEmpty);

      // Delete Desk B rule
      final deleteBtn = find.byKey(const ValueKey('delete_automation_rule_ws-b'));
      await tester.ensureVisible(deleteBtn);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      final rulesAfterDelete = await storage.getAutomationRules();
      expect(rulesAfterDelete.length, equals(1));
      expect(rulesAfterDelete.first.workspaceId, equals('ws-a'));
    });

    testWidgets('TeamMapScreen free desk sheet provides "Automatiser ce bureau" with conflict replacement', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveSiteId('site-1');
      await storage.saveFloorId('fl-1');
      await storage.saveHideWeekends(true);
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-existing',
          siteId: 'site-1',
          floorId: 'fl-1',
          workspaceId: 'ws-existing',
          workspaceName: 'Bureau Ancien',
          days: [3], // Wednesday
        ),
      ]);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-new-desk', 'workspaceType': 'Desk', 'name': 'B01-55'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-new-desk', 'name': 'B01-55', 'isBookable': true}
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
            initialDate: DateTime(2026, 10, 12),
            initialSiteId: 'site-1',
            initialFloorId: 'fl-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap desk B01-55 on map
      await tester.tap(find.text('55'));
      await tester.pumpAndSettle();

      // "Automatiser ce bureau" button must be shown
      final autoBtn = find.byKey(const ValueKey('automate_desk_button'));
      expect(autoBtn, findsOneWidget);
      await tester.tap(autoBtn);
      await tester.pumpAndSettle();

      expect(find.text('Automatiser B01-55'), findsOneWidget);
      // Wednesday (day 3) shows conflict with Bureau Ancien
      final wedRow = find.byKey(const ValueKey('desk_auto_day_3'));
      expect(find.descendant(of: wedRow, matching: find.text('⇄ Bureau Ancien')), findsOneWidget);

      await tester.tap(wedRow);
      await tester.pumpAndSettle();

      expect(find.text('Conflit sur le Mercredi'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_replace_day_button')));
      await tester.pumpAndSettle();

      // Also assign Monday (day 1) cleanly without conflict
      await tester.tap(find.byKey(const ValueKey('desk_auto_day_1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('close_desk_automation_sheet_button')));
      await tester.pumpAndSettle();

      final rules = await storage.getAutomationRules();
      final newDeskRule = rules.firstWhere((r) => r.workspaceId == 'ws-new-desk');
      expect(newDeskRule.days, equals([1, 3]));
      final oldDeskRule = rules.firstWhere((r) => r.workspaceId == 'ws-existing');
      expect(oldDeskRule.days, isEmpty);
    });

    testWidgets('HomeScreen Home tab displays per-day multi-desk projections and Automate tab adds a new place via SetupScreen(pickOnly: true)', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveSiteId('site-1');
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-default');
      await storage.saveWorkspaceName('Bureau Défaut');
      await storage.saveAutomationEnabled(true);
      await storage.saveProjectionsCount(7);
      await storage.saveSkipPublicHolidays(false);
      await storage.saveHideWeekends(false);
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-default',
          siteId: 'site-1',
          floorId: 'fl-1',
          workspaceId: 'ws-default',
          workspaceName: 'Bureau Défaut',
          days: [1, 2, 3, 4, 5], // Mon-Fri
        ),
        const AutomationRule(
          id: 'ws-weekend',
          siteId: 'site-1',
          floorId: 'fl-1',
          workspaceId: 'ws-weekend',
          workspaceName: 'Bureau Calme',
          days: [6, 7], // Sat-Sun
        ),
      ]);

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/buildings')) {
          if (path.contains('/floors')) {
            return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
          }
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Site 1'}]), 200);
        }
        if (path.contains('/workspaces/all')) {
          return http.Response(jsonEncode([
            {'id': 'ws-added', 'name': 'Salle C-99', 'isReservable': true},
          ]), 200);
        }
        if (path.endsWith('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-added', 'name': 'Salle C-99', 'workspaceType': 'Desk'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [50.0, 10.0], [50.0, 50.0], [10.0, 50.0], [10.0, 10.0]]
                  ]
                }
              }
            ]
          }), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Home tab projections show both Bureau Défaut (weekdays) and Bureau Calme (weekend)
      expect(find.text('Sera réservé (Bureau Défaut)'), findsWidgets);
      expect(find.text('Sera réservé (Bureau Calme)'), findsWidgets);

      // Navigate to Automate tab and add a new place via SetupScreen(pickOnly: true)
      await tester.tap(find.text('Automate'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('add_automation_rule_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ajouter une place automatisée'), findsOneWidget);
      final viewer = tester.widget<WorkspaceMapViewer>(find.byType(WorkspaceMapViewer));
      viewer.onSelected({'id': 'ws-added', 'name': 'Salle C-99'});
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('automation_rule_card_ws-added')), findsOneWidget);
      expect(find.text('Salle C-99'), findsWidgets);
      // Home default workspace remains untouched
      expect(await storage.getWorkspaceId(), equals('ws-default'));
      expect(await storage.getWorkspaceName(), equals('Bureau Défaut'));
    });

    testWidgets('Weekly summary banner displays vertical list with full desk names, distinct rule accents, and unwrapped conflict chips on mobile width', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveInitialTab(2); // Automate tab
      await storage.saveHideWeekends(true);
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-bord',
          siteId: 's1',
          floorId: 'fl-1',
          workspaceId: 'ws-bord',
          workspaceName: 'DS-BORD-1-12',
          days: [1, 3], // Monday, Wednesday
        ),
        const AutomationRule(
          id: 'ws-long',
          siteId: 's1',
          floorId: 'fl-2',
          workspaceId: 'ws-long',
          workspaceName: 'Bâtiment Principal - Open Space Nord-Est 42',
          days: [2], // Tuesday
        ),
      ]);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // All 5 weekday rows exist inside weekly_summary_banner in vertical order
      final monRow = find.byKey(const ValueKey('weekly_summary_day_1'));
      final tueRow = find.byKey(const ValueKey('weekly_summary_day_2'));
      final wedRow = find.byKey(const ValueKey('weekly_summary_day_3'));
      final thuRow = find.byKey(const ValueKey('weekly_summary_day_4'));
      final friRow = find.byKey(const ValueKey('weekly_summary_day_5'));
      expect(monRow, findsOneWidget);
      expect(tueRow, findsOneWidget);
      expect(wedRow, findsOneWidget);
      expect(thuRow, findsOneWidget);
      expect(friRow, findsOneWidget);

      expect(tester.getTopLeft(monRow).dy, lessThan(tester.getTopLeft(tueRow).dy));
      expect(tester.getTopLeft(tueRow).dy, lessThan(tester.getTopLeft(wedRow).dy));

      // Full desk names and unassigned labels are displayed
      expect(find.descendant(of: monRow, matching: find.text('DS-BORD-1-12')), findsOneWidget);
      expect(find.descendant(of: wedRow, matching: find.text('DS-BORD-1-12')), findsOneWidget);
      expect(
        find.descendant(
          of: tueRow,
          matching: find.text('Bâtiment Principal - Open Space Nord-Est 42'),
        ),
        findsOneWidget,
      );
      expect(find.descendant(of: thuRow, matching: find.text('Aucun bureau automatisé')), findsOneWidget);
      expect(find.descendant(of: friRow, matching: find.text('Aucun bureau automatisé')), findsOneWidget);

      // Same rule shares pill color (Mon & Wed), different rule gets a distinct accent (Tue)
      BoxDecoration? findPillDecoration(Finder row) {
        final containers = tester.widgetList<Container>(
          find.descendant(of: row, matching: find.byType(Container)),
        );
        for (final c in containers) {
          final dec = c.decoration;
          if (dec is BoxDecoration && dec.borderRadius == BorderRadius.circular(10)) {
            return dec;
          }
        }
        return null;
      }

      final monDec = findPillDecoration(monRow);
      final wedDec = findPillDecoration(wedRow);
      final tueDec = findPillDecoration(tueRow);
      expect(monDec, isNotNull);
      expect(wedDec, isNotNull);
      expect(tueDec, isNotNull);
      expect(monDec!.color, equals(wedDec!.color));
      expect(monDec.color, isNot(equals(tueDec!.color)));

      // Long conflict chip renders full name with softWrap and no maxWidth clipping
      final longConflictChip = find.byKey(const ValueKey('rule_day_chip_ws-bord_2'));
      expect(longConflictChip, findsOneWidget);
      final conflictText = tester.widget<Text>(
        find.descendant(
          of: longConflictChip,
          matching: find.text('Mar • Bâtiment Principal - Open Space Nord-Est 42'),
        ),
      );
      expect(conflictText.softWrap, isTrue);
      expect(conflictText.maxLines, isNull);
    });

    testWidgets('When automation is disabled, Automate tab shows paused indicators, disables execution tiles, keeps rules editable, and allows re-enabling', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      int bookingPosts = 0;
      final storage = StorageService();
      await storage.saveRefreshToken('mock-refresh');
      await storage.saveSiteId('s1');
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-a');
      await storage.saveWorkspaceName('Desk A');
      await storage.saveAutomationEnabled(false);
      await storage.saveHideWeekends(true);
      await storage.saveSkipPublicHolidays(false);
      await storage.saveProjectionsCount(7);
      await storage.saveInitialTab(0); // Start on Home tab to verify no recurring projections while paused
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-a',
          siteId: 's1',
          floorId: 'fl-1',
          workspaceId: 'ws-a',
          workspaceName: 'Desk A',
          days: [1], // Monday
        ),
      ]);

      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          bookingPosts++;
          return http.Response(jsonEncode({'id': 'ok'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(apiService: api, storageService: storage),
        ),
      );
      await tester.pumpAndSettle();

      // Home tab must NOT display recurring projections while automation is disabled
      expect(find.text('Sera réservé (Desk A)'), findsNothing);

      // Navigate to Automate tab
      await tester.tap(find.text('Automate'));
      await tester.pumpAndSettle();

      // Paused banner, weekly summary badge, and helper subtext are visible
      expect(find.byKey(const ValueKey('automation_disabled_banner')), findsOneWidget);
      expect(
        find.text('Automatisation en pause — aucune réservation automatique ne sera effectuée.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('weekly_summary_paused_badge')), findsOneWidget);
      expect(find.text('En pause'), findsOneWidget);
      expect(
        find.text('Activez l\'automatisation ci-dessus pour exécuter ces règles.'),
        findsOneWidget,
      );

      // Execution tiles are visible but disabled
      final timeTileFinder = find.widgetWithText(ListTile, "Heure d'exécution");
      final runNowTileFinder = find.byKey(const ValueKey('run_automation_now_tile'));
      expect(timeTileFinder, findsOneWidget);
      expect(runNowTileFinder, findsOneWidget);
      final timeTile = tester.widget<ListTile>(timeTileFinder);
      final runNowTile = tester.widget<ListTile>(runNowTileFinder);
      expect(timeTile.enabled, isFalse);
      expect(timeTile.onTap, isNull);
      expect(runNowTile.enabled, isFalse);
      expect(runNowTile.onTap, isNull);

      // Tapping disabled "Lancer maintenant" triggers zero API calls
      await tester.tap(runNowTileFinder);
      await tester.pumpAndSettle();
      expect(bookingPosts, equals(0));

      // Weekly summary and rule cards use paused opacities (0.45 and 0.65)
      final summaryOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(const ValueKey('weekly_summary_banner')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(summaryOpacity.opacity, equals(0.45));

      final rulesOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('automation_rule_card_ws-a')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(rulesOpacity.opacity, equals(0.65));

      // Rules remain editable while paused: add Wednesday (day 3) to Desk A
      final wedChip = find.byKey(const ValueKey('rule_day_chip_ws-a_3'));
      await tester.ensureVisible(wedChip);
      await tester.tap(wedChip);
      await tester.pumpAndSettle();

      final updatedRules = await storage.getAutomationRules();
      expect(updatedRules.firstWhere((r) => r.workspaceId == 'ws-a').days, equals([1, 3]));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('weekly_summary_day_3')),
          matching: find.text('Desk A'),
        ),
        findsOneWidget,
      );

      // Re-enable the main automation switch
      final mainSwitch = find.byKey(const ValueKey('toggle_automation_enabled'));
      await tester.ensureVisible(mainSwitch);
      await tester.tap(mainSwitch);
      await tester.pumpAndSettle();

      expect(await storage.getAutomationEnabled(), isTrue);
      expect(find.byKey(const ValueKey('automation_disabled_banner')), findsNothing);
      expect(find.byKey(const ValueKey('weekly_summary_paused_badge')), findsNothing);
      expect(
        find.text('Activez l\'automatisation ci-dessus pour exécuter ces règles.'),
        findsNothing,
      );
      expect(tester.widget<ListTile>(timeTileFinder).enabled, isTrue);
      expect(tester.widget<ListTile>(runNowTileFinder).enabled, isTrue);

      final activeSummaryOpacity = tester.widget<AnimatedOpacity>(
        find.descendant(
          of: find.byKey(const ValueKey('weekly_summary_banner')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(activeSummaryOpacity.opacity, equals(1.0));

      final activeRulesOpacity = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.byKey(const ValueKey('automation_rule_card_ws-a')),
          matching: find.byType(AnimatedOpacity),
        ),
      );
      expect(activeRulesOpacity.opacity, equals(1.0));

      // Home tab now displays recurring projections for Desk A
      await tester.tap(find.text('Accueil'));
      await tester.pumpAndSettle();
      expect(find.text('Sera réservé (Desk A)'), findsWidgets);
    });

    test('runBackgroundBookingAutomation respects enforceAutomationEnabled when true and preserves backward compatibility by default', () async {
      final storage = StorageService();
      await storage.saveRefreshToken('mock-token');
      await storage.saveFloorId('f1');
      await storage.saveWorkspaceId('ws-1');
      await storage.saveWorkspaceName('Desk 1');
      await storage.saveHideWeekends(true);
      await storage.saveSkipPublicHolidays(false);
      await storage.saveAutomationEnabled(false);
      await storage.saveAutomationRules([
        const AutomationRule(
          id: 'ws-1',
          siteId: 's1',
          floorId: 'f1',
          workspaceId: 'ws-1',
          workspaceName: 'Desk 1',
          days: [1],
        ),
      ]);

      int bookingsCalled = 0;
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'tok', 'refresh_token': 'ref'}), 200);
        }
        if (req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'u-1'}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          bookingsCalled++;
          return http.Response(jsonEncode({'id': 'ok'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client, storage: storage);
      final now = DateTime(2026, 10, 11);

      // With enforceAutomationEnabled: true and automation_enabled == false -> aborts with 0
      final countEnforcedOff = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
        enforceAutomationEnabled: true,
      );
      expect(countEnforcedOff, equals(0));
      expect(bookingsCalled, equals(0));

      // With enforceAutomationEnabled: true and automation_enabled == true -> reserves
      await storage.saveAutomationEnabled(true);
      final countEnforcedOn = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
        enforceAutomationEnabled: true,
      );
      expect(countEnforcedOn, equals(2));
      expect(bookingsCalled, equals(2));
    });
  });
}
