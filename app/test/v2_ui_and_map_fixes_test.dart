import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/screens/team_map/models/team_map_models.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/widgets/update_download_dialog.dart';
import 'package:auto_roomzio/widgets/workspace_map/desk_marker_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfflineStateManager.instance.reset();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('1. Favorite Gold Highlight Anti-False-Positive & Removal IDs', () {
    test(
      'computeEffectiveFavoriteWorkspaceIds does not highlight a non-favorite seated on a favorite historical desk',
      () {
        const Colleague aliceFav = Colleague(
          id: 'usr-alice',
          name: 'Alice Martin',
          email: 'alice@corp.com',
          isFavorite: true,
          deskName: 'ws-1',
        );

        final Map<String, DeskOccupant> occupants = <String, DeskOccupant>{
          'ws-1': const DeskOccupant(
            workspaceId: 'ws-1',
            occupantId: 'usr-stranger',
            occupantName: 'Jean Inconnu',
            occupantEmail: 'jean@corp.com',
          ),
        };

        final Set<String> effective =
            TeamMapHelpers.computeEffectiveFavoriteWorkspaceIds(
          favorites: const <Colleague>[aliceFav],
          occupants: occupants,
          allWorkspaces: const <Map<String, dynamic>>[
            <String, dynamic>{'id': 'ws-1', 'name': 'B01-01', 'isBookable': true},
          ],
          favoriteIds: const <String>{'usr-alice', 'alice@corp.com'},
          favoriteEmailsNormalized: const <String>{'alice@corp.com'},
          favoriteNamesNormalized: const <String>{'alice martin'},
        );

        expect(effective, isEmpty);
        expect(
          TeamMapHelpers.isOccupantFavorite(
            occupants['ws-1']!,
            favoriteIds: const <String>{'usr-alice', 'alice@corp.com'},
            favoriteEmailsNormalized: const <String>{'alice@corp.com'},
            favoriteNamesNormalized: const <String>{'alice martin'},
            fallbackWorkspaceIds: effective,
          ),
          isFalse,
        );
      },
    );

    testWidgets(
      'Stranger seated on favorite historical desk is NOT gold on TeamMapScreen, and removing favorite uses recorded fav.id/favoriteId',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final StorageService storage = StorageService();
        await storage.saveRefreshToken('mock-refresh');
        await storage.saveSiteId('site-1');
        await storage.saveFloorId('fl-1');
        await storage.saveFavoriteColleagues(const <Colleague>[
          Colleague(
            id: 'usr-alice',
            favoriteId: 'fav-srv-99',
            name: 'Alice Martin',
            email: 'alice@corp.com',
            isFavorite: true,
            deskName: 'ws-1',
          ),
        ]);

        final List<String> deletedFavoriteIds = <String>[];
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
          if (req.method == 'DELETE' && path.contains('/favorites/')) {
            deletedFavoriteIds.add(path.split('/favorites/').last);
            return http.Response('', 200);
          }
          if (path.contains('/favorites')) {
            return http.Response(jsonEncode(<Object>[]), 200);
          }
          if (path.contains('/floors') && path.contains('/data')) {
            return http.Response(
              jsonEncode(<String, Object>{
                'features': <Map<String, Object>>[
                  <String, Object>{
                    'type': 'Feature',
                    'properties': <String, Object>{
                      'workspaceId': 'ws-1',
                      'workspaceType': 'Desk',
                      'name': 'B01-01',
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
                      'workspaceId': 'ws-2',
                      'workspaceType': 'Desk',
                      'name': 'B01-02',
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
              }),
              200,
            );
          }
          if (path.contains('/workspaces/calendars')) {
            return http.Response(
              jsonEncode(<String, Object>{
                'data': <Map<String, Object>>[
                  <String, Object>{
                    'workspaceId': 'ws-1',
                    'status': 'Reserved',
                    'bookedTimeSlot': <String, Object>{
                      'user': <String, String>{
                        'id': 'usr-stranger',
                        'name': 'Bob Inconnu',
                        'email': 'bob@corp.com',
                      },
                    },
                  },
                  <String, Object>{
                    'workspaceId': 'ws-2',
                    'status': 'Reserved',
                    'bookedTimeSlot': <String, Object>{
                      // Occupant has no occupantId in payload, matched by email/name
                      'user': <String, String>{
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
          if (path.contains('/workspaces')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{
                  'id': 'ws-1',
                  'name': 'B01-01',
                  'isBookable': true,
                },
                <String, Object>{
                  'id': 'ws-2',
                  'name': 'B01-02',
                  'isBookable': true,
                },
              ]),
              200,
            );
          }
          if (path.contains('/buildings') && path.contains('/floors')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{'id': 'fl-1', 'name': 'Étage 1'},
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        final RoomzApiService api = RoomzApiService(client: client, storage: storage);
        await tester.pumpWidget(
          MaterialApp(
            home: TeamMapScreen(
              apiService: api,
              storageService: storage,
              initialDate: DateTime(2026, 11, 25),
              initialSiteId: 'site-1',
              initialFloorId: 'fl-1',
            ),
          ),
        );
        await tester.pumpAndSettle();

        final List<DeskMarkerWidget> markers =
            tester.widgetList<DeskMarkerWidget>(find.byType(DeskMarkerWidget)).toList();
        final DeskMarkerWidget strangerMarker = markers.firstWhere(
          (DeskMarkerWidget m) => m.occupant?.occupantName == 'Bob Inconnu',
        );
        final DeskMarkerWidget aliceMarker = markers.firstWhere(
          (DeskMarkerWidget m) => m.occupant?.occupantName == 'Alice Martin',
        );

        // Stranger seated on Alice's historical desk ws-1 must NOT be Gold
        expect(strangerMarker.isFavorite, isFalse);
        // Alice seated on ws-2 IS Gold
        expect(aliceMarker.isFavorite, isTrue);

        // Tap Alice's desk and remove her from favorites -> uses recorded favoriteId/fav.id
        await tester.tap(find.text('MARTIN A.'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Retirer des favoris'));
        await tester.pumpAndSettle();

        expect(deletedFavoriteIds, equals(<String>['fav-srv-99']));
        expect(await storage.getFavoriteColleagues(), isEmpty);
      },
    );
  });

  group('2. HomeScreen Workspace Change Preservation & initial_tab Safety', () {
    testWidgets(
      'HomeScreen preserves requested_dates and ignored_dates after _changeWorkspace',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        const String requestedDate = '2026-12-20';
        const String ignoredDate = '2026-12-21';

        SharedPreferences.setMockInitialValues(<String, Object>{
          'refresh_token': 'mock-refresh',
          'site_id': 'site-1',
          'floor_id': 'fl-1',
          'workspace_id': 'ws-old',
          'workspace_name': 'Ancien Bureau',
          'requested_dates': <String>[requestedDate],
          'ignored_dates': <String>[ignoredDate],
          'initial_tab': 0,
        });

        final StorageService storage = StorageService();
        await storage.saveCachedSites(<Map<String, dynamic>>[
          <String, dynamic>{'id': 'site-1', 'name': 'Site Principal'},
        ]);
        await storage.saveCachedFloors('site-1', <Map<String, dynamic>>[
          <String, dynamic>{'id': 'fl-1', 'name': 'Étage 1'},
        ]);
        await storage.saveFloorWorkspaces('fl-1', <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'ws-new',
            'name': 'Salle A-09',
            'isBookable': true,
            'isReservable': true,
          },
        ]);
        await storage.saveFloorPlanData('fl-1', <String, Object>{
          'features': <Map<String, Object>>[
            <String, Object>{
              'type': 'Feature',
              'properties': <String, Object>{
                'workspaceId': 'ws-new',
                'workspaceType': 'Desk',
                'name': 'Salle A-09',
              },
              'geometry': <String, Object>{
                'type': 'Polygon',
                'coordinates': <List<List<double>>>[
                  <List<double>>[
                    <double>[10.0, 10.0],
                    <double>[50.0, 10.0],
                    <double>[50.0, 50.0],
                    <double>[10.0, 50.0],
                    <double>[10.0, 10.0],
                  ],
                ],
              },
            },
          ],
        });

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
          if (path.contains('/users/current/bookings')) {
            return http.Response(
              jsonEncode(<String, Object>{'bookings': <Object>[]}),
              200,
            );
          }
          if (path.contains('/workspaces/calendars')) {
            return http.Response(
              jsonEncode(<String, Object>{'data': <Object>[]}),
              200,
            );
          }
          if (path.endsWith('/data')) {
            return http.Response(
              jsonEncode(<String, Object>{
                'features': <Map<String, Object>>[
                  <String, Object>{
                    'type': 'Feature',
                    'properties': <String, Object>{
                      'workspaceId': 'ws-new',
                      'workspaceType': 'Desk',
                      'name': 'Salle A-09',
                    },
                    'geometry': <String, Object>{
                      'type': 'Polygon',
                      'coordinates': <List<List<double>>>[
                        <List<double>>[
                          <double>[10.0, 10.0],
                          <double>[50.0, 10.0],
                          <double>[50.0, 50.0],
                          <double>[10.0, 50.0],
                          <double>[10.0, 10.0],
                        ],
                      ],
                    },
                  },
                ],
              }),
              200,
            );
          }
          if (path.contains('/workspaces/all')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{
                  'id': 'ws-new',
                  'name': 'Salle A-09',
                  'isBookable': true,
                  'isReservable': true,
                },
              ]),
              200,
            );
          }
          if (path.contains('/buildings') && path.contains('/floors')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{'id': 'fl-1', 'name': 'Étage 1'},
              ]),
              200,
            );
          }
          if (path.contains('/buildings')) {
            return http.Response(
              jsonEncode(<Map<String, Object>>[
                <String, Object>{'id': 'site-1', 'name': 'Site Principal'},
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        await http.runWithClient(() async {
          final RoomzApiService api =
              RoomzApiService(client: client, storage: storage);
          await tester.pumpWidget(
            MaterialApp(
              home: HomeScreen(apiService: api, storageService: storage),
            ),
          );
          await tester.pumpAndSettle();

          // Open workspace selector via HomeScreen card
          await tester.tap(find.text('Ancien Bureau'));
          await tester.pumpAndSettle();

          // Select desk on SetupScreen map
          expect(find.text('09'), findsOneWidget);
          await tester.tap(find.text('09'));
          await tester.pumpAndSettle();

          // Back on HomeScreen with updated workspace
          expect(find.text('Salle A-09'), findsWidgets);
          expect(await storage.getWorkspaceId(), equals('ws-new'));

          // requested_dates and ignored_dates must be strictly preserved
          expect(await storage.getRequestedDates(), contains(requestedDate));
          expect(await storage.getIgnoredDates(), contains(ignoredDate));
        }, () => client);
      },
    );

    testWidgets(
      'HomeScreen does not crash when initial_tab == 2 and showAutomation == false',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        SharedPreferences.setMockInitialValues(<String, Object>{
          'refresh_token': 'mock-refresh',
          'workspace_id': 'ws-1',
          'workspace_name': 'Bureau A-01',
          'floor_id': 'fl-1',
          'initial_tab': 2,
          'show_automation_card': false,
          'show_stats_card': false,
        });

        final MockClient client = MockClient((http.Request req) async {
          if (req.url.path.contains('/connect/token')) {
            return http.Response(
              jsonEncode(<String, String>{
                'access_token': 'mock-access',
                'refresh_token': 'mock-refresh',
              }),
              200,
            );
          }
          if (req.url.path.contains('/users/current/bookings')) {
            return http.Response(
              jsonEncode(<String, Object>{'bookings': <Object>[]}),
              200,
            );
          }
          if (req.url.path.contains('/workspaces/calendars')) {
            return http.Response(
              jsonEncode(<String, Object>{'data': <Object>[]}),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        final StorageService storage = StorageService();
        final RoomzApiService api =
            RoomzApiService(client: client, storage: storage);

        await tester.pumpWidget(
          MaterialApp(
            home: HomeScreen(apiService: api, storageService: storage),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Bureau A-01'), findsWidgets);
        expect(find.text('Automate'), findsNothing);
      },
    );
  });

  group('3. UpdateDownloadDialog Cancel During Stalled Download', () {
    testWidgets(
      'Tapping Annuler aborts a stalled download stream cleanly and closes dialog without leaked timers',
      (WidgetTester tester) async {
        const MethodChannel pathProviderChannel =
            MethodChannel('plugins.flutter.io/path_provider');
        final Directory tempDir = Directory.systemTemp.createTempSync(
          'autoroomzio_ota_test_',
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          pathProviderChannel,
          (MethodCall methodCall) async {
            if (methodCall.method == 'getTemporaryDirectory') {
              return tempDir.path;
            }
            return null;
          },
        );
        addTearDown(() async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(pathProviderChannel, null);
          await tester.runAsync(() async {
            if (tempDir.existsSync()) {
              tempDir.deleteSync(recursive: true);
            }
          });
        });

        final StreamController<List<int>> streamController =
            StreamController<List<int>>();
        addTearDown(() async {
          if (!streamController.isClosed) {
            await streamController.close();
          }
        });

        final MockClient stalledClient = MockClient.streaming(
          (http.BaseRequest request, http.ByteStream bodyStream) async {
            // Emit one small chunk then stall indefinitely waiting for more bytes
            streamController.add(List<int>.filled(1024 * 256, 65));
            return http.StreamedResponse(
              streamController.stream,
              200,
              contentLength: 1024 * 1024 * 10,
            );
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (BuildContext context) => ElevatedButton(
                  onPressed: () {
                    unawaited(
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext _) => UpdateDownloadDialog(
                          url: 'https://github.com/Xris65/AutoRoomzio/releases/download/v2.0.0/app.apk',
                          httpClient: stalledClient,
                        ),
                      ),
                    );
                  },
                  child: const Text('Start Update'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Start Update'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();

        expect(find.byType(UpdateDownloadDialog), findsOneWidget);
        expect(find.text('Téléchargement'), findsOneWidget);

        // Tap Annuler while stream is stalled
        final Finder cancelBtnFinder = find.byKey(
          const ValueKey<String>('cancel_update_download_button'),
        );
        expect(cancelBtnFinder, findsOneWidget);
        await tester.tap(cancelBtnFinder);
        await tester.pump();
        for (int i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          if (find.byType(UpdateDownloadDialog).evaluate().isEmpty) break;
        }
        await tester.pumpAndSettle();

        expect(find.byType(UpdateDownloadDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
