import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/services/profile_sync_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/token_crypto.dart';
import 'package:auto_roomzio/widgets/web_pairing_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WebPairingDialog URL builders', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
        'buildPairingUrl places the encrypted v2 token in the URL fragment, never the query',
        () async {
      final String url = await WebPairingDialog.buildPairingUrl(
        refreshToken: 'refresh-secret',
        buildingId: 'b1',
        floorId: 'f 2',
        workspaceId: 'w3',
        workspaceName: 'Open Space - 04',
      );

      final Uri uri = Uri.parse(url);
      expect(uri.query, isEmpty);
      expect(url, isNot(contains('?token=')));
      expect(uri.fragment, startsWith('token=v2_'));
      expect(url, isNot(contains('refresh-secret')));

      final Map<String, String> params = Uri.splitQueryString(uri.fragment);
      expect(
        await TokenCryptoService.decryptToken(params['token']!),
        'refresh-secret',
      );
      expect(params['b'], 'b1');
      expect(params['f'], 'f 2');
      expect(params['w'], 'w3');
      expect(params['wn'], 'Open Space - 04');
    });

    test(
        'buildFullProfilePairingUrl embeds compressed encrypted bundle in #bundle= fragment',
        () async {
      final StorageService source = StorageService();
      await source.saveRefreshToken('rt-full-bundle-123');
      await source.saveSiteId('site-42');
      await source.saveFloorId('floor-7');
      await source.saveWorkspaceId('ws-108');
      await source.saveWorkspaceName('Desk 108');
      await source.saveAutomationRules(<AutomationRule>[
        const AutomationRule(
          id: 'ws-108',
          siteId: 'site-42',
          floorId: 'floor-7',
          workspaceId: 'ws-108',
          workspaceName: 'Desk 108',
          days: <int>[1, 3, 5],
        ),
      ]);
      await source.saveFavoriteColleagues(<Colleague>[
        const Colleague(id: 'c1', name: 'Alice Martin', isFavorite: true),
        const Colleague(id: 'c2', name: 'Bob Dupont', isFavorite: true),
        const Colleague(id: 'c3', name: 'Claire Petit', isFavorite: true),
      ]);

      final String url =
          await WebPairingDialog.buildFullProfilePairingUrl(source);
      final Uri uri = Uri.parse(url);
      expect(uri.query, isEmpty);
      expect(uri.fragment, startsWith('bundle=v2_'));
      expect(url, isNot(contains('rt-full-bundle-123')));

      // Reset storage to simulate fresh Web target
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService target = StorageService();
      target.clearMemoryCache();

      final ProfileImportResult result = await ProfileSyncService.importBundle(
        url,
        target,
        applyAuthToken: true,
      );
      expect(result.success, isTrue);
      expect(result.authTokenApplied, isTrue);
      expect(result.restoredRulesCount, equals(1));
      expect(result.restoredFavoritesCount, equals(3));
      expect(await target.getRefreshToken(), equals('rt-full-bundle-123'));
      expect(await target.getWorkspaceId(), equals('ws-108'));
      expect((await target.getAutomationRules()).first.days, <int>[1, 3, 5]);

      // Compact QR version caps favorites when maxFavoritesForQr is provided
      final String compactUrl =
          await WebPairingDialog.buildFullProfilePairingUrl(
        source,
        maxFavoritesForQr: 2,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService compactTarget = StorageService();
      compactTarget.clearMemoryCache();
      final ProfileImportResult compactResult =
          await ProfileSyncService.importBundle(
        compactUrl,
        compactTarget,
        applyAuthToken: true,
      );
      expect(compactResult.success, isTrue);
      expect(compactResult.restoredFavoritesCount, equals(2));
    });
  });

  group('ProfileSyncService full round-trip & security', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test(
        'exportProfileCode (.roomzio mode) omits auth token and importBundle preserves existing refresh token',
        () async {
      final StorageService source = StorageService();
      await source.saveRefreshToken('source-secret-token-should-not-export');
      await source.saveSiteId('s1');
      await source.saveFloorId('f2');
      await source.saveWorkspaceId('w3');
      await source.saveWorkspaceName('Bureau Nord');
      await source.saveAutomationRules(<AutomationRule>[
        const AutomationRule(
          id: 'w3',
          siteId: 's1',
          floorId: 'f2',
          workspaceId: 'w3',
          workspaceName: 'Bureau Nord',
          days: <int>[2, 4],
        ),
      ]);
      await source.saveFavoriteColleagues(<Colleague>[
        const Colleague(
          id: 'col-1',
          name: 'Jean Test',
          email: 'jean@example.com',
          isFavorite: true,
        ),
      ]);
      await source.saveVacations(<Map<String, String>>[
        <String, String>{'start': '2026-08-01', 'end': '2026-08-15'},
      ]);
      await source.saveRequestedDates(<String>['2026-09-01']);
      await source.saveRequestedWorkspacesMap(<String, String>{
        '2026-09-01': 'w99',
      });
      await source.saveRequestedWorkspaceNamesMap(<String, String>{
        '2026-09-01': 'Bureau 99',
      });
      await source.saveIgnoredDates(<String>['2026-09-02']);
      await source.saveThemeModeIndex(2);
      await source.saveThemeColorIndex(3);
      await source.saveFontFamilyIndex(1);
      await source.saveUiScale(1.15);
      await source.saveCompactMode(true);
      await source.saveHideWeekends(false);
      await source.saveSkipPublicHolidays(false);
      await source.saveHolidayCountryCode('BE');
      await source.saveAutomationEnabled(true);
      await source.saveAutomationTime(7, 45);
      await source.saveNotifySuccess(false);
      await source.saveNotifyFailure(false);
      await source.saveShowFavoriteWeekIndicators(false);
      await source.saveInitialTab(2);
      await source.saveShowDelegatedBookings(false);
      await source.savePullToRefresh(false);

      final String roomzioCode = await ProfileSyncService.exportProfileCode(
        source,
        includeAuthToken: false,
      );
      expect(roomzioCode, startsWith('ROOMZIO2:'));
      expect(roomzioCode, isNot(contains('source-secret-token-should-not-export')));

      // Destination already has its own active auth session
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService dest = StorageService();
      dest.clearMemoryCache();
      await dest.saveRefreshToken('existing-dest-refresh-token');

      final ProfileImportResult result = await ProfileSyncService.importBundle(
        roomzioCode,
        dest,
        applyAuthToken: false,
      );

      expect(result.success, isTrue);
      expect(result.authTokenApplied, isFalse);
      expect(result.restoredRulesCount, equals(1));
      expect(result.restoredFavoritesCount, equals(1));
      expect(result.restoredVacationsCount, equals(1));
      expect(result.errorMessage, isNull);

      // Existing token MUST remain intact!
      expect(
        await dest.getRefreshToken(),
        equals('existing-dest-refresh-token'),
      );

      // Verify full configuration restoration
      expect(await dest.getSiteId(), equals('s1'));
      expect(await dest.getFloorId(), equals('f2'));
      expect(await dest.getWorkspaceId(), equals('w3'));
      expect(await dest.getWorkspaceName(), equals('Bureau Nord'));
      expect((await dest.getAutomationRules()).length, equals(1));
      expect((await dest.getFavoriteColleagues()).first.name, 'Jean Test');
      expect((await dest.getVacations()).first['start'], '2026-08-01');
      expect(await dest.getRequestedDates(), <String>['2026-09-01']);
      expect(
        await dest.getRequestedWorkspacesMap(),
        <String, String>{'2026-09-01': 'w99'},
      );
      expect(
        await dest.getRequestedWorkspaceNamesMap(),
        <String, String>{'2026-09-01': 'Bureau 99'},
      );
      expect(await dest.getIgnoredDates(), <String>['2026-09-02']);
      expect(await dest.getThemeModeIndex(), equals(2));
      expect(await dest.getThemeColorIndex(), equals(3));
      expect(await dest.getFontFamilyIndex(), equals(1));
      expect(await dest.getUiScale(), equals(1.15));
      expect(await dest.getCompactMode(), isTrue);
      expect(await dest.getHideWeekends(), isFalse);
      expect(await dest.getSkipPublicHolidays(), isFalse);
      expect(await dest.getHolidayCountryCode(), equals('BE'));
      expect(await dest.getAutomationEnabled(), isTrue);
      expect(
        await dest.getAutomationTime(),
        <String, int>{'hour': 7, 'minute': 45},
      );
      expect(await dest.getNotifySuccess(), isFalse);
      expect(await dest.getNotifyFailure(), isFalse);
      expect(await dest.getShowFavoriteWeekIndicators(), isFalse);
      expect(await dest.getInitialTab(), equals(2));
      expect(await dest.getShowDelegatedBookings(), isFalse);
      expect(await dest.getPullToRefresh(), isFalse);
    });

    test(
        'importBundle ignores rt field even if present when applyAuthToken is false',
        () async {
      final StorageService source = StorageService();
      await source.saveRefreshToken('token-in-bundle');
      final String bundleWithToken = await ProfileSyncService.exportProfileCode(
        source,
        includeAuthToken: true,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final StorageService dest = StorageService();
      dest.clearMemoryCache();
      await dest.saveRefreshToken('original-token');

      final ProfileImportResult result = await ProfileSyncService.importBundle(
        bundleWithToken,
        dest,
        applyAuthToken: false,
      );

      expect(result.success, isTrue);
      expect(result.authTokenApplied, isFalse);
      expect(await dest.getRefreshToken(), equals('original-token'));
    });

    test('importBundle rejects empty, corrupt, or tampered inputs gracefully',
        () async {
      final StorageService dest = StorageService();

      expect((await ProfileSyncService.importBundle('', dest)).success, isFalse);
      expect(
        (await ProfileSyncService.importBundle('ROOMZIO2:', dest)).success,
        isFalse,
      );
      expect(
        (await ProfileSyncService.importBundle('ROOMZIO2:v2_corrupt', dest))
            .success,
        isFalse,
      );

      final String plainEncrypted =
          await TokenCryptoService.encryptToken('not-gzip-not-json');
      expect(
        (await ProfileSyncService.importBundle(plainEncrypted, dest)).success,
        isFalse,
      );
    });
  });
}
