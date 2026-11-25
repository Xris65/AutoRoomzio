import 'dart:convert';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/screens/home/widgets/calendar_tab.dart';
import 'package:auto_roomzio/screens/home/widgets/home_dashboard_tab.dart';
import 'package:auto_roomzio/screens/home/widgets/weekly_cockpit_card.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
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
      'workspaceId': 'ws-a01',
      'name': 'A01',
      'isBookable': true,
      'floorId': 'fl-1',
    },
    <String, Object>{
      'id': 'ws-b02',
      'workspaceId': 'ws-b02',
      'name': 'B02',
      'isBookable': true,
      'floorId': 'fl-1',
    },
  ];
}

Future<StorageService> _seedConfiguredStorage() async {
  final StorageService storage = StorageService();
  storage.clearMemoryCache();
  await storage.saveRefreshToken('mock-refresh-token');
  await storage.saveSiteId('site-1');
  await storage.saveFloorId('fl-1');
  await storage.saveWorkspaceId('ws-a01');
  await storage.saveWorkspaceName('A01');
  await storage.saveShowAutomation(false);
  await storage.saveShowStats(false);
  await storage.saveHideWeekends(false);
  await storage.saveShowFavoriteWeekIndicators(true);
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

  group('1. RoomzApiService.fetchFavoritesOrNull Pagination & Deduplication', () {
    test(
      'paginates across offset=0 and offset=100 (>100 items), deduplicates, and stops cleanly',
      () async {
        final List<int> requestedOffsets = <int>[];

        final MockClient client = MockClient((http.Request req) async {
          if (req.url.path.endsWith('/favorites')) {
            final int offset =
                int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
            requestedOffsets.add(offset);

            if (offset == 0) {
              final List<Map<String, Object>> page0 =
                  List<Map<String, Object>>.generate(
                100,
                (int idx) => <String, Object>{
                  'id': 'fav-$idx',
                  'name': 'Collègue $idx',
                  'email': 'colleague$idx@corp.com',
                },
              );
              return http.Response(jsonEncode(page0), 200);
            }

            if (offset == 100) {
              // 25 entries: 1 duplicate (fav-0) + 24 new entries
              final List<Map<String, Object>> page1 = <Map<String, Object>>[
                <String, Object>{
                  'id': 'fav-0',
                  'name': 'Collègue 0 (Doublon)',
                  'email': 'colleague0@corp.com',
                },
                ...List<Map<String, Object>>.generate(
                  24,
                  (int idx) {
                    final int numId = 100 + idx;
                    return <String, Object>{
                      'id': 'fav-$numId',
                      'name': 'Collègue $numId',
                      'email': 'colleague$numId@corp.com',
                    };
                  },
                ),
              ];
              return http.Response(jsonEncode(page1), 200);
            }

            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        });

        final RoomzApiService api = RoomzApiService(client: client);
        final List<Colleague>? favorites =
            await api.fetchFavoritesOrNull('mock-token');

        expect(favorites, isNotNull);
        expect(requestedOffsets, equals(<int>[0, 100]));
        expect(favorites!.length, equals(124));
        expect(
          favorites.every((Colleague c) => c.isFavorite),
          isTrue,
        );
        expect(
          favorites.any((Colleague c) => c.id == 'fav-123'),
          isTrue,
        );
      },
    );

    test(
      'stops cleanly when offset=100 returns only duplicates (addedInPage == 0)',
      () async {
        final List<int> requestedOffsets = <int>[];

        final MockClient client = MockClient((http.Request req) async {
          if (req.url.path.endsWith('/favorites')) {
            final int offset =
                int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
            requestedOffsets.add(offset);

            final List<Map<String, Object>> fullDuplicatePage =
                List<Map<String, Object>>.generate(
              100,
              (int idx) => <String, Object>{
                'id': 'fav-$idx',
                'name': 'Collègue $idx',
                'email': 'colleague$idx@corp.com',
              },
            );
            return http.Response(jsonEncode(fullDuplicatePage), 200);
          }
          return http.Response('[]', 200);
        });

        final RoomzApiService api = RoomzApiService(client: client);
        final List<Colleague>? favorites =
            await api.fetchFavoritesOrNull('mock-token');

        expect(favorites, isNotNull);
        expect(requestedOffsets, equals(<int>[0, 100]));
        expect(favorites!.length, equals(100));
      },
    );

    test('returns null on HTTP error to preserve offline/local cache', () async {
      final MockClient client = MockClient((http.Request req) async {
        return http.Response('{"error": "server_error"}', 500);
      });

      final RoomzApiService api = RoomzApiService(client: client);
      final List<Colleague>? favorites =
          await api.fetchFavoritesOrNull('mock-token');

      expect(favorites, isNull);
    });
  });

  group('2. HomeScreen 13-Day Horizon Sync, Badges & Dashboard Cleanup', () {
    testWidgets(
      'syncs /favorites, persists 13-day floor occupants, renders star badges on WeeklyCockpitCard & CalendarTab, and omits redundant Home cards',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(430, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final StorageService storage = await _seedConfiguredStorage();
        final DateTime today = normalizeLocalDate(DateTime.now());
        final String todayIso = DateHelpers.formatIsoDate(today);
        final String dayPlus1Iso =
            DateHelpers.formatIsoDate(addCalendarDays(today, 1));
        final String dayPlus7Iso =
            DateHelpers.formatIsoDate(addCalendarDays(today, 7));
        final String dayPlus13Iso =
            DateHelpers.formatIsoDate(addCalendarDays(today, 13));

        final Set<String> activeFavoriteDates = <String>{
          todayIso,
          dayPlus1Iso,
          dayPlus7Iso,
          dayPlus13Iso,
        };
        final Set<String> syncedCalendarDates = <String>{};
        bool favoritesEndpointCalled = false;

        final MockClient client = MockClient((http.Request req) async {
          final String path = req.url.path;
          if (path.contains('/connect/token')) {
            return http.Response(
              jsonEncode(<String, String>{'access_token': 'mock-access'}),
              200,
            );
          }
          if (path.endsWith('/users/current')) {
            return http.Response(
              jsonEncode(<String, String>{
                'id': 'usr-me',
                'email': 'me@corp.com',
              }),
              200,
            );
          }
          if (path.contains('/users/current/bookings')) {
            return http.Response(jsonEncode(<Object>[]), 200);
          }
          if (path.contains('/favorites')) {
            favoritesEndpointCalled = true;
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{
                  'id': 'u-alice',
                  'name': 'Alice Martin',
                  'email': 'alice@corp.com',
                },
              ]),
              200,
            );
          }
          if (path.contains('/buildings') && path.contains('/floors')) {
            return http.Response(
              jsonEncode(<Map<String, String>>[
                <String, String>{'id': 'fl-1', 'name': 'Étage 1'},
              ]),
              200,
            );
          }
          if (path.contains('/floors') && path.contains('/data')) {
            return http.Response(jsonEncode(_sampleFloorPlan()), 200);
          }
          if (path.contains('/workspaces/calendars')) {
            final Object? decoded = jsonDecode(req.body);
            final String? reqDate = decoded is Map<Object?, Object?>
                ? decoded['date']?.toString()
                : null;
            if (reqDate != null) {
              syncedCalendarDates.add(reqDate);
            }
            if (reqDate != null && activeFavoriteDates.contains(reqDate)) {
              return http.Response(
                jsonEncode(<String, Object>{
                  'data': <Map<String, Object>>[
                    <String, Object>{
                      'workspaceId': 'ws-b02',
                      'status': 'Reserved',
                      'bookedTimeSlot': <String, Object>{
                        'eventId': 'evt-$reqDate',
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
          if (path.contains('/workspaces')) {
            return http.Response(jsonEncode(_sampleWorkspaces()), 200);
          }
          return http.Response('[]', 200);
        });

        final RoomzApiService api = RoomzApiService(
          client: client,
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(storageService: storage, apiService: api),
          ),
        );
        await tester.pumpAndSettle();

        // 1. /favorites synced and merged locally
        expect(favoritesEndpointCalled, isTrue);
        final List<Colleague> savedFavs = await storage.getFavoriteColleagues();
        expect(
          savedFavs.any((Colleague c) => c.id == 'u-alice' && c.isFavorite),
          isTrue,
        );

        // 2. All 14 dates (today .. today + 13) synced and persisted in storage
        for (int i = 0; i <= 13; i++) {
          final String iso = DateHelpers.formatIsoDate(addCalendarDays(today, i));
          expect(
            syncedCalendarDates,
            contains(iso),
            reason: 'Expected HomeScreen sync to request occupancy for $iso',
          );
        }
        final Map<String, DeskOccupant> day13Occs =
            await storage.getFloorOccupants('fl-1', dayPlus13Iso);
        expect(day13Occs['ws-b02']?.occupantName, equals('Alice Martin'));

        // 3. Redundant cards removed from HomeDashboardTab
        expect(find.byType(HomeDashboardTab), findsOneWidget);
        expect(find.text("Plan d'équipe"), findsNothing);
        expect(find.text('Mes collègues favoris'), findsNothing);

        // 4. WeeklyCockpitCard displays favorite ⭐ badge on today's week
        expect(find.byType(WeeklyCockpitCard), findsOneWidget);
        final Finder todayCockpitBadge = find.byKey(
          ValueKey<String>('cockpit_fav_badge_$todayIso'),
        );
        expect(todayCockpitBadge, findsOneWidget);
        expect(
          find.descendant(
            of: todayCockpitBadge,
            matching: find.byIcon(Icons.star_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: todayCockpitBadge,
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        // Navigate WeeklyCockpitCard to next week -> day+7 badge visible from synced horizon
        await tester.tap(
          find.byKey(const ValueKey<String>('cockpit_week_next_btn')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(ValueKey<String>('cockpit_fav_badge_$dayPlus7Iso')),
          findsOneWidget,
        );

        // 5. Switch to CalendarTab and verify calendar_fav_badge_*
        await tester.tap(find.text('Calendrier'));
        await tester.pumpAndSettle();
        expect(find.byType(CalendarTab), findsOneWidget);

        final Finder todayCalBadge = find.byKey(
          ValueKey<String>('calendar_fav_badge_$todayIso'),
        );
        expect(todayCalBadge, findsOneWidget);
        expect(
          find.descendant(
            of: todayCalBadge,
            matching: find.byIcon(Icons.star_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: todayCalBadge,
            matching: find.text('1'),
          ),
          findsOneWidget,
        );

        // If today+13 falls in the next month relative to today, advance the calendar page
        // so its badge is also directly rendered and verified on CalendarTab.
        final DateTime dayPlus13 = addCalendarDays(today, 13);
        if (dayPlus13.month != today.month) {
          final Finder nextMonthBtn = find.byIcon(Icons.chevron_right);
          if (nextMonthBtn.evaluate().isNotEmpty) {
            await tester.tap(nextMonthBtn.first);
            await tester.pumpAndSettle();
          }
        }
        expect(
          find.byKey(ValueKey<String>('calendar_fav_badge_$dayPlus13Iso')),
          findsOneWidget,
        );
      },
    );
  });

  group('3. TeamMapScreen 13-Day Preload & Plan Favorites Manager Button', () {
    testWidgets(
      'preloads entire today..today+13 horizon beyond current week and exposes plan_manage_favorites_button',
      (WidgetTester tester) async {
        final StorageService storage = await _seedConfiguredStorage();
        await storage.saveFavoriteColleagues(const <Colleague>[
          Colleague(
            id: 'u-alice',
            name: 'Alice Martin',
            email: 'alice@corp.com',
            isFavorite: true,
          ),
        ]);

        final DateTime today = normalizeLocalDate(DateTime.now());
        final String dayPlus10Iso =
            DateHelpers.formatIsoDate(addCalendarDays(today, 10));
        final String dayPlus13Iso =
            DateHelpers.formatIsoDate(addCalendarDays(today, 13));
        final Set<String> fetchedDates = <String>{};

        final MockClient client = MockClient((http.Request req) async {
          final String path = req.url.path;
          if (path.contains('/connect/token')) {
            return http.Response(
              jsonEncode(<String, String>{'access_token': 'mock-access'}),
              200,
            );
          }
          if (path.endsWith('/users/current')) {
            return http.Response(
              jsonEncode(<String, String>{
                'id': 'usr-me',
                'email': 'me@corp.com',
              }),
              200,
            );
          }
          if (path.contains('/favorites')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{
                  'id': 'u-alice',
                  'name': 'Alice Martin',
                  'email': 'alice@corp.com',
                },
              ]),
              200,
            );
          }
          if (path.contains('/buildings') && path.contains('/floors')) {
            return http.Response(
              jsonEncode(<Map<String, String>>[
                <String, String>{'id': 'fl-1', 'name': 'Étage 1'},
              ]),
              200,
            );
          }
          if (path.contains('/floors') && path.contains('/data')) {
            return http.Response(jsonEncode(_sampleFloorPlan()), 200);
          }
          if (path.contains('/workspaces/calendars')) {
            final Object? decoded = jsonDecode(req.body);
            final String? reqDate = decoded is Map<Object?, Object?>
                ? decoded['date']?.toString()
                : null;
            if (reqDate != null) {
              fetchedDates.add(reqDate);
            }
            if (reqDate == dayPlus10Iso || reqDate == dayPlus13Iso) {
              return http.Response(
                jsonEncode(<String, Object>{
                  'data': <Map<String, Object>>[
                    <String, Object>{
                      'workspaceId': 'ws-b02',
                      'status': 'Reserved',
                      'bookedTimeSlot': <String, Object>{
                        'eventId': 'evt-$reqDate',
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
          if (path.contains('/workspaces')) {
            return http.Response(jsonEncode(_sampleWorkspaces()), 200);
          }
          return http.Response('[]', 200);
        });

        final RoomzApiService api = RoomzApiService(
          client: client,
          storage: storage,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: TeamMapScreen(
              apiService: api,
              storageService: storage,
              initialSiteId: 'site-1',
              initialFloorId: 'fl-1',
              hideWeekends: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. All 14 dates (today .. today + 13) preloaded, including beyond current week
        for (int i = 0; i <= 13; i++) {
          final String iso = DateHelpers.formatIsoDate(addCalendarDays(today, i));
          expect(
            fetchedDates,
            contains(iso),
            reason: 'Expected TeamMapScreen to preload occupancy for $iso',
          );
        }

        final Map<String, DeskOccupant> occDay10 =
            await storage.getFloorOccupants('fl-1', dayPlus10Iso);
        final Map<String, DeskOccupant> occDay13 =
            await storage.getFloorOccupants('fl-1', dayPlus13Iso);
        expect(occDay10['ws-b02']?.occupantName, equals('Alice Martin'));
        expect(occDay13['ws-b02']?.occupantName, equals('Alice Martin'));

        // 2. plan_manage_favorites_button exposed in Plan AppBar and opens favorites manager
        final Finder manageFavBtn = find.byKey(
          const ValueKey<String>('plan_manage_favorites_button'),
        );
        expect(manageFavBtn, findsOneWidget);

        await tester.tap(manageFavBtn);
        await tester.pumpAndSettle();

        expect(find.text('Mes collègues favoris'), findsOneWidget);
        expect(find.text('Alice Martin'), findsWidgets);
      },
    );
  });
}
