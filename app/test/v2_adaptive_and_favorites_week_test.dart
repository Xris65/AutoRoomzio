import 'dart:convert';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/screens/home/widgets/settings_tab.dart';
import 'package:auto_roomzio/screens/home/widgets/weekly_cockpit_card.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map/widgets/favorites_week_modal.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/services/profile_sync_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/utils/date_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, Object> _sampleFloorPlan() {
  return <String, Object>{
    'features': <Map<String, Object>>[
      <String, Object>{
        'type': 'Feature',
        'properties': <String, Object>{
          'workspaceId': 'ws-a01',
          'workspaceType': 'Desk',
          'name': 'A01',
        },
        'geometry': <String, Object>{
          'type': 'Polygon',
          'coordinates': <List<List<double>>>[
            <List<double>>[
              <double>[10.0, 10.0],
              <double>[40.0, 10.0],
              <double>[40.0, 40.0],
              <double>[10.0, 40.0],
              <double>[10.0, 10.0],
            ],
          ],
        },
      },
      <String, Object>{
        'type': 'Feature',
        'properties': <String, Object>{
          'workspaceId': 'ws-b02',
          'workspaceType': 'Desk',
          'name': 'B02',
        },
        'geometry': <String, Object>{
          'type': 'Polygon',
          'coordinates': <List<List<double>>>[
            <List<double>>[
              <double>[60.0, 10.0],
              <double>[90.0, 10.0],
              <double>[90.0, 40.0],
              <double>[60.0, 40.0],
              <double>[60.0, 10.0],
            ],
          ],
        },
      },
    ],
  };
}

List<Map<String, Object>> _sampleWorkspaces() {
  return <Map<String, Object>>[
    <String, Object>{
      'id': 'ws-a01',
      'name': 'A01',
      'isBookable': true,
      'floorId': 'fl-1',
    },
    <String, Object>{
      'id': 'ws-b02',
      'name': 'B02',
      'isBookable': true,
      'floorId': 'fl-1',
    },
  ];
}

MockClient _createHomeMockClient() {
  return MockClient((http.Request req) async {
    final String path = req.url.path;
    if (path.contains('/connect/token')) {
      return http.Response(
        jsonEncode(<String, String>{
          'access_token': 'mock-access',
        }),
        200,
      );
    }
    if (path.contains('/floors') && path.contains('/data')) {
      return http.Response(jsonEncode(_sampleFloorPlan()), 200);
    }
    if (path.contains('/buildings') && path.contains('/floors')) {
      return http.Response(
        jsonEncode(<Map<String, String>>[
          <String, String>{'id': 'fl-1', 'name': 'Étage 1'},
        ]),
        200,
      );
    }
    if (path.contains('/workspaces/calendars')) {
      return http.Response(
        jsonEncode(<String, Object>{'data': <Object>[]}),
        200,
      );
    }
    if (path.contains('/workspaces')) {
      return http.Response(jsonEncode(_sampleWorkspaces()), 200);
    }
    if (path.contains('/favorites')) {
      return http.Response(jsonEncode(<Object>[]), 200);
    }
    if (path.contains('/bookings')) {
      return http.Response(jsonEncode(<Object>[]), 200);
    }
    return http.Response('[]', 200);
  });
}

Future<StorageService> _seedConfiguredStorage() async {
  final StorageService storage = StorageService();
  storage.clearMemoryCache();
  await storage.saveRefreshToken('keep-my-refresh-token');
  await storage.saveSiteId('site-1');
  await storage.saveFloorId('fl-1');
  await storage.saveWorkspaceId('ws-a01');
  await storage.saveWorkspaceName('A01');
  await storage.saveShowAutomation(true);
  await storage.saveShowStats(true);
  await storage.saveHideWeekends(true);
  await storage.saveFloorPlanData('fl-1', _sampleFloorPlan());
  await storage.saveFloorWorkspaces('fl-1', _sampleWorkspaces());
  return storage;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfflineStateManager.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageService().clearMemoryCache();
  });

  tearDown(() {
    StorageService().clearMemoryCache();
  });

  group('1. FavoritesWeekModal Multi-Week Navigation & Caching', () {
    testWidgets(
      'navigating next/prev updates range label, loads & caches week presences, and reset button restores initial week',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final DateTime wednesday = DateTime(2026, 11, 25);
        const String wedIso = '2026-11-25';
        const String nextTueIso = '2026-12-01';

        const Colleague alice = Colleague(
          id: 'u-alice',
          name: 'Alice Martin',
          email: 'alice@corp.com',
          isFavorite: true,
        );

        final List<String> fetchedDates = <String>[];
        final MockClient client = MockClient((http.Request req) async {
          final String path = req.url.path;
          if (path.contains('/connect/token')) {
            return http.Response(
              jsonEncode(<String, String>{
                'access_token': 'mock-access',
                'refresh_token': 'mock-refresh',
              }),
              200,
            );
          }
          if (path.contains('/workspaces/calendars')) {
            final Object? decoded = jsonDecode(req.body);
            final String? reqDate = decoded is Map<Object?, Object?>
                ? decoded['date']?.toString()
                : null;
            if (reqDate != null) {
              fetchedDates.add(reqDate);
            }
            if (reqDate == nextTueIso) {
              return http.Response(
                jsonEncode(<String, Object>{
                  'data': <Map<String, Object>>[
                    <String, Object>{
                      'workspaceId': 'ws-b02',
                      'status': 'Reserved',
                      'bookedTimeSlot': <String, Object>{
                        'user': <String, String>{
                          'id': 'u-alice',
                          'name': 'Alice Martin',
                          'email': 'alice@corp.com',
                        },
                      },
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode(<String, Object>{'data': <Object>[]}),
              200,
            );
          }
          return http.Response('[]', 200);
        });
        final RoomzApiService api = RoomzApiService(
          client: client,
          storage: storage,
        );

        final Map<String, Map<String, DeskOccupant>> cacheUpdates =
            <String, Map<String, DeskOccupant>>{};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FavoritesWeekModal(
                selectedDate: wednesday,
                floorId: 'fl-1',
                hideWeekends: true,
                initialShowIndicators: true,
                savedFavorites: const <Colleague>[alice],
                currentOccupants: const <String, DeskOccupant>{
                  'ws-a01': DeskOccupant(
                    workspaceId: 'ws-a01',
                    occupantId: 'u-alice',
                    occupantName: 'Alice Martin',
                    occupantEmail: 'alice@corp.com',
                  ),
                },
                occupancyCache: const <String, Map<String, DeskOccupant>>{},
                allWorkspaces: _sampleWorkspaces(),
                favoriteIds: const <String>{'u-alice', 'alice@corp.com'},
                favoriteEmailsNormalized: const <String>{'alice@corp.com'},
                favoriteNamesNormalized: const <String>{'alice martin'},
                apiService: api,
                storageService: storage,
                onCacheUpdated: (
                  String cacheKey,
                  Map<String, DeskOccupant> occs,
                ) {
                  cacheUpdates[cacheKey] = occs;
                },
                onJumpToDesk: (DateTime targetDay, String workspaceId) {},
                onToggleIndicators: (bool enabled) async {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final Finder rangeFinder = find.byKey(
          const ValueKey<String>('fav_week_range_label'),
        );
        final Finder prevBtn = find.byKey(
          const ValueKey<String>('fav_week_prev_btn'),
        );
        final Finder nextBtn = find.byKey(
          const ValueKey<String>('fav_week_next_btn'),
        );
        final Finder resetBtn = find.byKey(
          const ValueKey<String>('fav_week_reset_btn'),
        );

        expect(
          tester.widget<Text>(rangeFinder).data,
          equals('23 nov. – 27 nov. 2026'),
        );
        expect(resetBtn, findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('fav_week_cell_u-alice_$wedIso')),
            matching: find.text('A01'),
          ),
          findsOneWidget,
        );

        // Navigate to next week
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(rangeFinder).data,
          equals('30 nov. – 4 déc. 2026'),
        );
        expect(resetBtn, findsOneWidget);
        expect(fetchedDates, contains(nextTueIso));
        expect(cacheUpdates.containsKey('fl-1_$nextTueIso'), isTrue);

        final Map<String, DeskOccupant> storedNextTue =
            await storage.getFloorOccupants('fl-1', nextTueIso);
        expect(storedNextTue.containsKey('ws-b02'), isTrue);

        expect(
          find.descendant(
            of: find.byKey(
              const ValueKey<String>('fav_week_cell_u-alice_$nextTueIso'),
            ),
            matching: find.text('B02'),
          ),
          findsOneWidget,
        );
        expect(find.text('1/5 j.'), findsOneWidget);

        // Navigate back to previous (initial) week
        await tester.tap(prevBtn);
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(rangeFinder).data,
          equals('23 nov. – 27 nov. 2026'),
        );
        expect(resetBtn, findsNothing);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('fav_week_cell_u-alice_$wedIso')),
            matching: find.text('A01'),
          ),
          findsOneWidget,
        );

        // Navigate forward two weeks (uses cache on week +1, loads week +2), then reset
        final int fetchCountBeforeRevisit = fetchedDates.length;
        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
        expect(fetchedDates.length, equals(fetchCountBeforeRevisit));

        await tester.tap(nextBtn);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(rangeFinder).data,
          equals('7 déc. – 11 déc. 2026'),
        );
        expect(resetBtn, findsOneWidget);

        await tester.tap(resetBtn);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(rangeFinder).data,
          equals('23 nov. – 27 nov. 2026'),
        );
        expect(resetBtn, findsNothing);
      },
    );
  });

  group('2. AdaptiveAppShell / HomeScreen Responsive Breakpoints', () {
    testWidgets(
      'Mobile (400x800): renders M3 NavigationBar with Plan destination and zero overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final RoomzApiService api = RoomzApiService(
          client: _createHomeMockClient(),
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(storageService: storage, apiService: api),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
        expect(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('Plan'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('toggle_split_map_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'Tablet (800x600): renders NavigationRail with labels and zero overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final RoomzApiService api = RoomzApiService(
          client: _createHomeMockClient(),
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(storageService: storage, apiService: api),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationRail), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing);

        final NavigationRail rail = tester.widget<NavigationRail>(
          find.byType(NavigationRail),
        );
        expect(rail.extended, isFalse);
        expect(rail.labelType, equals(NavigationRailLabelType.all));
        expect(
          find.descendant(
            of: find.byType(NavigationRail),
            matching: find.text('Plan'),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Desktop / Web (1440x900): renders NavigationRail + synchronized Split-View with embedded TeamMapScreen and zero overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final RoomzApiService api = RoomzApiService(
          client: _createHomeMockClient(),
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(storageService: storage, apiService: api),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(NavigationRail), findsOneWidget);
        final NavigationRail rail = tester.widget<NavigationRail>(
          find.byType(NavigationRail),
        );
        expect(rail.extended, isTrue);

        final Finder splitToggle = find.byKey(
          const ValueKey<String>('toggle_split_map_button'),
        );
        expect(splitToggle, findsOneWidget);

        final Finder embeddedSplitMap = find.byKey(
          const ValueKey<String>('embedded_split_team_map'),
        );
        expect(embeddedSplitMap, findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is TeamMapScreen && w.isEmbedded,
          ),
          findsOneWidget,
        );

        // Toggle split map off and back on without errors
        await tester.tap(splitToggle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(embeddedSplitMap, findsNothing);

        await tester.tap(splitToggle);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(embeddedSplitMap, findsOneWidget);
      },
    );
  });

  group('3. WeeklyCockpitCard Statuses, Week Navigation & Cached Favorites', () {
    testWidgets(
      'renders "Ma semaine", changes days on prev/next arrows, and displays status + cached favorite badge',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(600, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final DateTime wednesday = DateTime(2026, 11, 25);
        const String monIso = '2026-11-23';
        const String tueIso = '2026-11-24';
        const String wedIso = '2026-11-25';
        const String thuIso = '2026-11-26';
        const String friIso = '2026-11-27';
        const String nextWedIso = '2026-12-02';

        await storage.saveFavoriteColleagues(const <Colleague>[
          Colleague(
            id: 'u-alice',
            name: 'Alice Martin',
            email: 'alice@corp.com',
            isFavorite: true,
          ),
          Colleague(
            id: 'u-bob',
            name: 'Bob Durand',
            email: 'bob@corp.com',
            isFavorite: true,
          ),
        ]);
        await storage.saveFloorOccupants('fl-1', wedIso, const <String, DeskOccupant>{
          'ws-a01': DeskOccupant(
            workspaceId: 'ws-a01',
            occupantId: 'u-alice',
            occupantName: 'Alice Martin',
            occupantEmail: 'alice@corp.com',
          ),
          'ws-b02': DeskOccupant(
            workspaceId: 'ws-b02',
            occupantId: 'u-bob',
            occupantName: 'Bob Durand',
            occupantEmail: 'bob@corp.com',
          ),
        });

        DateTime? tappedDay;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WeeklyCockpitCard(
                selectedDate: wednesday,
                onDaySelected: (DateTime day) => tappedDay = day,
                hideWeekends: true,
                showAutomation: true,
                automationEnabled: true,
                automationRules: const <AutomationRule>[
                  AutomationRule(
                    id: 'ws-a01',
                    siteId: 'site-1',
                    floorId: 'fl-1',
                    workspaceId: 'ws-a01',
                    workspaceName: 'A01',
                    days: <int>[DateTime.monday],
                  ),
                ],
                selectedDays: const <int>[DateTime.monday],
                isVacation: (DateTime d) =>
                    DateHelpers.formatIsoDate(d) == friIso,
                skipPublicHolidays: false,
                holidayCountryCode: 'FR',
                bookedDates: const <String>{wedIso},
                requestedDates: const <String>{thuIso},
                ignoredDates: const <String>{},
                bookedElsewhereMap: const <String, String>{tueIso: 'Salle B'},
                storageService: storage,
                floorId: 'fl-1',
                showFavoriteWeekIndicators: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Ma semaine'), findsOneWidget);
        expect(find.text('23 nov. – 27 nov.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('cockpit_day_$monIso')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('cockpit_day_$wedIso')),
          findsOneWidget,
        );

        // Cached favorite badge for Wednesday (2 favorites)
        final Finder favBadge = find.byKey(
          const ValueKey<String>('cockpit_fav_badge_$wedIso'),
        );
        expect(favBadge, findsOneWidget);
        expect(
          find.descendant(of: favBadge, matching: find.text('⭐ 2')),
          findsOneWidget,
        );

        // Status tooltips reflect booked, booked elsewhere, requested, vacation
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Tooltip &&
                (w.message ?? '').contains('Réservé sur votre bureau') &&
                (w.message ?? '').contains('2 favoris'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Tooltip &&
                (w.message ?? '').contains('Réservé ailleurs (Salle B)'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Tooltip &&
                (w.message ?? '').contains('Programmé en attente'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (Widget w) =>
                w is Tooltip && (w.message ?? '').contains('En congés'),
          ),
          findsOneWidget,
        );

        // Tap Wednesday selects day
        await tester.tap(
          find.byKey(const ValueKey<String>('cockpit_day_$wedIso')),
        );
        expect(tappedDay, isNotNull);
        expect(DateHelpers.formatIsoDate(tappedDay!), equals(wedIso));

        // Navigate next week -> days change
        await tester.tap(
          find.byKey(const ValueKey<String>('cockpit_week_next_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('30 nov. – 4 déc.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('cockpit_day_$wedIso')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('cockpit_day_$nextWedIso')),
          findsOneWidget,
        );

        // Navigate prev week -> initial days & favorite badge return
        await tester.tap(
          find.byKey(const ValueKey<String>('cockpit_week_prev_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('23 nov. – 27 nov.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey<String>('cockpit_day_$wedIso')),
          findsOneWidget,
        );
        expect(favBadge, findsOneWidget);
      },
    );
  });

  group('4. SettingsTab .roomzio Export & Import UI Flow', () {
    testWidgets(
      'exports ROOMZIO2:... code and imports a valid code restoring rules/vacations without clearing refresh_token',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        await storage.saveAutomationRules(const <AutomationRule>[
          AutomationRule(
            id: 'ws-a01',
            siteId: 'site-1',
            floorId: 'fl-1',
            workspaceId: 'ws-a01',
            workspaceName: 'A01',
            days: <int>[DateTime.tuesday, DateTime.thursday],
          ),
        ]);
        await storage.saveVacations(const <Map<String, String>>[
          <String, String>{'start': '2026-12-24', 'end': '2026-12-31'},
        ]);
        await storage.saveFavoriteColleagues(const <Colleague>[
          Colleague(
            id: 'u-alice',
            name: 'Alice Martin',
            email: 'alice@corp.com',
            isFavorite: true,
          ),
        ]);

        // Pre-generate an external valid ROOMZIO2:... backup to import later
        final String backupCode = await ProfileSyncService.exportProfileCode(
          storage,
          includeAuthToken: false,
        );
        expect(backupCode, startsWith('ROOMZIO2:'));

        final RoomzApiService api = RoomzApiService(
          client: _createHomeMockClient(),
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(storageService: storage, apiService: api),
          ),
        );
        await tester.pumpAndSettle();

        // Go to Paramètres tab
        await tester.tap(find.text('Paramètres'));
        await tester.pumpAndSettle();

        final Finder settingsScrollable = find.descendant(
          of: find.byType(SettingsTab),
          matching: find.byType(Scrollable),
        );

        // 1) Export flow
        final Finder exportTile = find.byKey(
          const ValueKey<String>('export_roomzio_tile'),
        );
        await tester.scrollUntilVisible(
          exportTile,
          250,
          scrollable: settingsScrollable,
        );
        await tester.tap(exportTile);
        await tester.pumpAndSettle();

        final Finder exportedTextFinder = find.byKey(
          const ValueKey<String>('exported_roomzio_code_text'),
        );
        expect(exportedTextFinder, findsOneWidget);
        final String? exportedCode =
            tester.widget<SelectableText>(exportedTextFinder).data;
        expect(exportedCode, isNotNull);
        expect(exportedCode, startsWith('ROOMZIO2:'));

        await tester.tap(find.text('Fermer'));
        await tester.pumpAndSettle();

        // Wipe rules, vacations & favorites locally while keeping refresh_token
        await storage.saveAutomationRules(const <AutomationRule>[]);
        await storage.saveVacations(const <Map<String, String>>[]);
        await storage.saveFavoriteColleagues(const <Colleague>[]);
        expect(await storage.getAutomationRules(), isEmpty);
        expect(await storage.getVacations(), isEmpty);
        expect(await storage.getRefreshToken(), equals('keep-my-refresh-token'));

        // 2) Import flow
        final Finder importTile = find.byKey(
          const ValueKey<String>('import_roomzio_tile'),
        );
        await tester.scrollUntilVisible(
          importTile,
          250,
          scrollable: settingsScrollable,
        );
        await tester.tap(importTile);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey<String>('import_roomzio_input')),
          backupCode,
        );
        await tester.tap(
          find.byKey(const ValueKey<String>('confirm_import_roomzio_btn')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Configuration restaurée !'), findsOneWidget);
        expect(find.text('• 1 règle(s) multi-bureaux'), findsOneWidget);
        expect(find.text('• 1 collègue(s) favori(s)'), findsOneWidget);
        expect(find.text('• 1 période(s) de congés'), findsOneWidget);

        await tester.tap(
          find.byKey(const ValueKey<String>('close_import_roomzio_btn')),
        );
        await tester.pumpAndSettle();

        // Verify restoration and preservation of existing refresh_token
        final List<AutomationRule> restoredRules =
            await storage.getAutomationRules();
        expect(restoredRules.length, equals(1));
        expect(restoredRules.first.workspaceId, equals('ws-a01'));
        expect(
          restoredRules.first.days,
          equals(<int>[DateTime.tuesday, DateTime.thursday]),
        );

        final List<Map<String, String>> restoredVacations =
            await storage.getVacations();
        expect(restoredVacations.length, equals(1));
        expect(restoredVacations.first['start'], equals('2026-12-24'));
        expect(restoredVacations.first['end'], equals('2026-12-31'));

        expect(
          await storage.getRefreshToken(),
          equals('keep-my-refresh-token'),
        );
      },
    );
  });
}
