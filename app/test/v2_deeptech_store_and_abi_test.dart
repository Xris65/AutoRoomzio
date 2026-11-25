import 'dart:convert';
import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/services/app_update_service.dart';
import 'package:auto_roomzio/services/profile_sync_service.dart';
import 'package:auto_roomzio/services/reservation_store.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/token_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    StorageService().clearMemoryCache();
    fontNotifier.value = 0;
  });

  tearDown(() {
    StorageService().clearMemoryCache();
    fontNotifier.value = 0;
  });

  group('1. ReservationStore Migration & Instant Recalculation', () {
    test(
        'migrates booked_dates, booked_elsewhere_map and all_time_booked_dates into reservations_v2 idempotently',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'workspace_id': 'ws-home',
        'workspace_name': 'Bureau Principal',
        'booked_dates': <String>['2026-11-26', '2026-11-27'],
        'booked_elsewhere_map': jsonEncode(<String, String>{
          '2026-11-28': 'Salle Annexe',
        }),
        'all_time_booked_dates': <String>[
          '2026-11-20',
          '2026-11-26', // Duplicate across keys; booked_dates takes priority
        ],
      });

      final ReservationStore store = ReservationStore(
        nowProvider: () => DateTime(2026, 11, 25),
      );

      final Map<String, ReservationEntry> firstLoad = await store.loadAll(
        defaultWorkspaceId: 'ws-home',
        defaultWorkspaceName: 'Bureau Principal',
      );

      expect(firstLoad.keys, unorderedEquals(<String>[
        '2026-11-20',
        '2026-11-26',
        '2026-11-27',
        '2026-11-28',
      ]));
      expect(firstLoad['2026-11-26']?.workspaceId, equals('ws-home'));
      expect(
        firstLoad['2026-11-26']?.workspaceName,
        equals('Bureau Principal'),
      );
      expect(firstLoad['2026-11-28']?.workspaceId, isEmpty);
      expect(firstLoad['2026-11-28']?.workspaceName, equals('Salle Annexe'));
      expect(firstLoad['2026-11-20']?.workspaceId, equals('ws-home'));

      // Canonical key written and legacy keys cleaned up
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ReservationStore.storageKey), isNotNull);
      expect(prefs.getStringList('booked_dates'), isNull);
      expect(prefs.getString('booked_elsewhere_map'), isNull);
      expect(prefs.getStringList('all_time_booked_dates'), isNull);

      // Idempotent reload from cache and from a fresh store instance
      final Map<String, ReservationEntry> cachedReload = await store.loadAll(
        defaultWorkspaceId: 'ws-home',
        defaultWorkspaceName: 'Bureau Principal',
      );
      expect(cachedReload, equals(firstLoad));

      final ReservationStore freshStore = ReservationStore(
        nowProvider: () => DateTime(2026, 11, 25),
      );
      final Map<String, ReservationEntry> freshReload =
          await freshStore.loadAll(
        defaultWorkspaceId: 'ws-home',
        defaultWorkspaceName: 'Bureau Principal',
      );
      expect(freshReload, equals(firstLoad));
    });

    test(
        'recalculates hereDates and elsewhereMap immediately when defaultWorkspaceId changes',
        () async {
      final ReservationStore store = ReservationStore(
        nowProvider: () => DateTime(2026, 11, 25),
      );

      await store.upsert(
        const ReservationEntry(
          dateIso: '2026-11-26',
          workspaceId: 'ws-alpha',
          workspaceName: 'Poste Alpha',
        ),
      );
      await store.upsert(
        const ReservationEntry(
          dateIso: '2026-11-27',
          workspaceId: 'ws-beta',
          workspaceName: 'Poste Beta',
        ),
      );
      await store.upsert(
        const ReservationEntry(
          dateIso: '2026-11-28',
          workspaceId: 'ws-alpha',
          workspaceName: 'Poste Alpha',
        ),
      );

      // View when default workspace is ws-alpha
      expect(
        await store.hereDates('ws-alpha'),
        equals(<String>{'2026-11-26', '2026-11-28'}),
      );
      expect(
        await store.elsewhereMap('ws-alpha'),
        equals(<String, String>{'2026-11-27': 'Poste Beta'}),
      );

      // Switch default workspace to ws-beta -> instant partition recalculation
      expect(
        await store.hereDates('ws-beta'),
        equals(<String>{'2026-11-27'}),
      );
      expect(
        await store.elsewhereMap('ws-beta'),
        equals(<String, String>{
          '2026-11-26': 'Poste Alpha',
          '2026-11-28': 'Poste Alpha',
        }),
      );

      // Switch default workspace to ws-gamma -> all reservations appear elsewhere
      final ({Set<String> here, Map<String, String> elsewhere}) gammaView =
          await store.partition('ws-gamma');
      expect(gammaView.here, isEmpty);
      expect(
        gammaView.elsewhere,
        equals(<String, String>{
          '2026-11-26': 'Poste Alpha',
          '2026-11-27': 'Poste Beta',
          '2026-11-28': 'Poste Alpha',
        }),
      );
    });
  });

  group('2. AppUpdateService Multi-ABI Selection & Fallback', () {
    MockClient createReleaseClient() {
      return MockClient((http.Request request) async {
        expect(request.url, equals(AppUpdateService.latestReleaseUri));
        final String body = jsonEncode(<String, Object?>{
          'tag_name': 'v2.1.0',
          'body': 'Multi-ABI OTA release',
          'html_url':
              'https://github.com/Xris65/AutoRoomzio/releases/tag/v2.1.0',
          'assets': <Map<String, String>>[
            <String, String>{
              'name': 'AutoRoomzio-v2.1.0-arm64-v8a.apk',
              'browser_download_url':
                  'https://example.com/AutoRoomzio-v2.1.0-arm64-v8a.apk',
            },
            <String, String>{
              'name': 'AutoRoomzio-v2.1.0-armeabi-v7a.apk',
              'browser_download_url':
                  'https://example.com/AutoRoomzio-v2.1.0-armeabi-v7a.apk',
            },
            <String, String>{
              'name': 'AutoRoomzio-v2.1.0-universal.apk',
              'browser_download_url':
                  'https://example.com/AutoRoomzio-v2.1.0-universal.apk',
            },
            <String, String>{
              'name': 'AutoRoomzio-v2.1.0-windows.zip',
              'browser_download_url':
                  'https://example.com/AutoRoomzio-v2.1.0-windows.zip',
            },
          ],
        });
        return http.Response(body, 200);
      });
    }

    test('selects arm64-v8a APK when abiProvider returns arm64-v8a', () async {
      final AppUpdateService service = AppUpdateService(
        client: createReleaseClient(),
        currentVersionProvider: () async => '2.0.0',
        abiProvider: () async => 'arm64-v8a',
      );

      final AppUpdateCheckResult result = await service.checkForUpdates();
      expect(result.status, equals(AppUpdateStatus.updateAvailable));
      expect(result.updateInfo?.matchedAbi, equals('arm64-v8a'));
      expect(
        result.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-arm64-v8a.apk'),
      );
      expect(
        result.updateInfo?.universalApkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-universal.apk'),
      );
    });

    test('selects armeabi-v7a APK when abiProvider returns armeabi-v7a',
        () async {
      final AppUpdateService service = AppUpdateService(
        client: createReleaseClient(),
        currentVersionProvider: () async => '2.0.0',
        abiProvider: () async => 'armeabi-v7a',
      );

      final AppUpdateCheckResult result = await service.checkForUpdates();
      expect(result.status, equals(AppUpdateStatus.updateAvailable));
      expect(result.updateInfo?.matchedAbi, equals('armeabi-v7a'));
      expect(
        result.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-armeabi-v7a.apk'),
      );
      expect(
        result.updateInfo?.universalApkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-universal.apk'),
      );
    });

    test('falls back to universal APK when abiProvider returns null', () async {
      final AppUpdateService service = AppUpdateService(
        client: createReleaseClient(),
        currentVersionProvider: () async => '2.0.0',
        abiProvider: () async => null,
      );

      final AppUpdateCheckResult result = await service.checkForUpdates();
      expect(result.status, equals(AppUpdateStatus.updateAvailable));
      expect(result.updateInfo?.matchedAbi, isNull);
      expect(
        result.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-universal.apk'),
      );
    });

    test('falls back to universal APK when abiProvider returns unknown ABI',
        () async {
      final AppUpdateService service = AppUpdateService(
        client: createReleaseClient(),
        currentVersionProvider: () async => '2.0.0',
        abiProvider: () async => 'mips64',
      );

      final AppUpdateCheckResult result = await service.checkForUpdates();
      expect(result.status, equals(AppUpdateStatus.updateAvailable));
      expect(result.updateInfo?.matchedAbi, isNull);
      expect(
        result.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.1.0-universal.apk'),
      );
    });

    test(
        'orders -all-universal.apk first alphabetically for v1.7.0 OTA while preserving v2.0.0+ ABI selection',
        () async {
      final List<String> assetNames = <String>[
        'AutoRoomzio-v2.0.0-x86_64.apk',
        'AutoRoomzio-v2.0.0-arm64-v8a.apk',
        'AutoRoomzio-v2.0.0-armeabi-v7a.apk',
        'AutoRoomzio-v2.0.0-all-universal.apk',
      ]..sort();

      expect(
        assetNames,
        equals(<String>[
          'AutoRoomzio-v2.0.0-all-universal.apk',
          'AutoRoomzio-v2.0.0-arm64-v8a.apk',
          'AutoRoomzio-v2.0.0-armeabi-v7a.apk',
          'AutoRoomzio-v2.0.0-x86_64.apk',
        ]),
      );
      expect(
        assetNames.firstWhere((String name) => name.endsWith('.apk')),
        equals('AutoRoomzio-v2.0.0-all-universal.apk'),
      );

      final MockClient githubSortedClient =
          MockClient((http.Request request) async {
        expect(request.url, equals(AppUpdateService.latestReleaseUri));
        final String body = jsonEncode(<String, Object?>{
          'tag_name': 'v2.0.0',
          'body': 'v2.0.0 multi-ABI release',
          'html_url':
              'https://github.com/Xris65/AutoRoomzio/releases/tag/v2.0.0',
          'assets': assetNames
              .map(
                (String name) => <String, String>{
                  'name': name,
                  'browser_download_url': 'https://example.com/$name',
                },
              )
              .toList(),
        });
        return http.Response(body, 200);
      });

      final AppUpdateService arm64Service = AppUpdateService(
        client: githubSortedClient,
        currentVersionProvider: () async => '1.9.0',
        abiProvider: () async => 'arm64-v8a',
      );
      final AppUpdateCheckResult arm64Result =
          await arm64Service.checkForUpdates();
      expect(arm64Result.status, equals(AppUpdateStatus.updateAvailable));
      expect(arm64Result.updateInfo?.matchedAbi, equals('arm64-v8a'));
      expect(
        arm64Result.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.0.0-arm64-v8a.apk'),
      );
      expect(
        arm64Result.updateInfo?.universalApkUrl,
        equals('https://example.com/AutoRoomzio-v2.0.0-all-universal.apk'),
      );

      final AppUpdateService nullAbiService = AppUpdateService(
        client: githubSortedClient,
        currentVersionProvider: () async => '1.9.0',
        abiProvider: () async => null,
      );
      final AppUpdateCheckResult nullAbiResult =
          await nullAbiService.checkForUpdates();
      expect(nullAbiResult.status, equals(AppUpdateStatus.updateAvailable));
      expect(nullAbiResult.updateInfo?.matchedAbi, isNull);
      expect(
        nullAbiResult.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.0.0-all-universal.apk'),
      );

      final AppUpdateService unknownAbiService = AppUpdateService(
        client: githubSortedClient,
        currentVersionProvider: () async => '1.9.0',
        abiProvider: () async => 'mips64',
      );
      final AppUpdateCheckResult unknownAbiResult =
          await unknownAbiService.checkForUpdates();
      expect(unknownAbiResult.status, equals(AppUpdateStatus.updateAvailable));
      expect(unknownAbiResult.updateInfo?.matchedAbi, isNull);
      expect(
        unknownAbiResult.updateInfo?.apkUrl,
        equals('https://example.com/AutoRoomzio-v2.0.0-all-universal.apk'),
      );
    });
  });

  group('3. TokenCryptoService, ProfileSyncService & Offline Fonts Theme', () {
    test(
        'TokenCryptoService and ProfileSyncService round-trip compressed encrypted profile coherently',
        () async {
      final StorageService source = StorageService();
      await source.saveRefreshToken('rt-coherence-check');
      await source.saveWorkspaceId('ws-42');
      await source.saveWorkspaceName('Desk 42');
      await source.saveFontFamilyIndex(2); // FiraCode

      final String bundleWithToken = await ProfileSyncService.exportProfileCode(
        source,
        includeAuthToken: true,
      );
      expect(bundleWithToken, startsWith('v2_'));

      // Underlying payload decrypts via TokenCryptoService to URL-safe GZip Base64
      final String? decryptedCompressed =
          await TokenCryptoService.decryptToken(bundleWithToken);
      expect(decryptedCompressed, isNotNull);
      expect(decryptedCompressed, isNotEmpty);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService target = StorageService();
      target.clearMemoryCache();

      final ProfileImportResult imported =
          await ProfileSyncService.importBundle(
        bundleWithToken,
        target,
        applyAuthToken: true,
      );
      expect(imported.success, isTrue);
      expect(imported.authTokenApplied, isTrue);
      expect(await target.getRefreshToken(), equals('rt-coherence-check'));
      expect(await target.getWorkspaceId(), equals('ws-42'));
      expect(await target.getFontFamilyIndex(), equals(2));
    });

    testWidgets(
        'MyApp theme applies bundled local fonts Roboto, Poppins and FiraCode',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'refresh_token': 'mock_refresh_token',
        'workspace_name': 'Desk A-01',
        'automation_enabled': false,
        'font_family_index': 0,
      });

      await tester.pumpWidget(const MyApp());
      await tester.pump();

      MaterialApp app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, equals(Duration.zero));
      expect(app.theme?.textTheme.bodyMedium?.fontFamily, equals('Roboto'));
      expect(
        app.theme?.primaryTextTheme.bodyMedium?.fontFamily,
        equals('Roboto'),
      );
      expect(app.darkTheme?.textTheme.bodyMedium?.fontFamily, equals('Roboto'));
      expect(
        DefaultTextStyle.of(tester.element(find.byType(HomeScreen)))
            .style
            .fontFamily,
        equals('Roboto'),
      );

      fontNotifier.value = 1;
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.textTheme.bodyMedium?.fontFamily, equals('Poppins'));
      expect(
        app.theme?.primaryTextTheme.bodyMedium?.fontFamily,
        equals('Poppins'),
      );
      expect(
        app.darkTheme?.textTheme.bodyMedium?.fontFamily,
        equals('Poppins'),
      );
      expect(
        DefaultTextStyle.of(tester.element(find.byType(HomeScreen)))
            .style
            .fontFamily,
        equals('Poppins'),
      );

      fontNotifier.value = 2;
      await tester.pump();
      app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme?.textTheme.bodyMedium?.fontFamily, equals('FiraCode'));
      expect(
        app.theme?.primaryTextTheme.bodyMedium?.fontFamily,
        equals('FiraCode'),
      );
      expect(
        app.darkTheme?.textTheme.bodyMedium?.fontFamily,
        equals('FiraCode'),
      );
      expect(
        DefaultTextStyle.of(tester.element(find.byType(HomeScreen)))
            .style
            .fontFamily,
        equals('FiraCode'),
      );

      fontNotifier.value = 0;
      await tester.pump();
      expect(
        DefaultTextStyle.of(tester.element(find.byType(HomeScreen)))
            .style
            .fontFamily,
        equals('Roboto'),
      );
    });
  });
}
