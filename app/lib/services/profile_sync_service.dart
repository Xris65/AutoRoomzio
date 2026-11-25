import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import '../models/colleague.dart';
import '../storage_service.dart';
import '../token_crypto.dart';

/// Result returned by [ProfileSyncService.importBundle].
class ProfileImportResult {
  final bool success;
  final int restoredRulesCount;
  final int restoredFavoritesCount;
  final int restoredVacationsCount;
  final bool authTokenApplied;
  final String? errorMessage;

  const ProfileImportResult({
    required this.success,
    this.restoredRulesCount = 0,
    this.restoredFavoritesCount = 0,
    this.restoredVacationsCount = 0,
    this.authTokenApplied = false,
    this.errorMessage,
  });
}

/// Handles exporting and importing full AutoRoomzio user profiles
/// (workspace, automation rules, favorite colleagues, vacations, calendar dates,
/// UI & automation preferences, and optionally the OAuth refresh token) as
/// GZip-compressed, AES-256-GCM encrypted bundles.
class ProfileSyncService {
  static const String fileHeaderPrefix = 'ROOMZIO2:';
  static const int currentVersion = 2;

  /// Exports the complete profile stored in [storage] as a GZip-compressed,
  /// AES-256-GCM encrypted string.
  ///
  /// When [includeAuthToken] is `false` (default, `.roomzio` text export),
  /// the auth token is omitted and the result is prefixed with `'ROOMZIO2:'`.
  /// When [includeAuthToken] is `true` (Web pairing `#bundle=...`), the
  /// refresh token is included and the raw `'v2_...'` payload is returned.
  static Future<String> exportProfileCode(
    StorageService storage, {
    bool includeAuthToken = false,
    int? maxFavorites,
  }) async {
    final String? siteId = await storage.getSiteId();
    final String? floorId = await storage.getFloorId();
    final String? workspaceId = await storage.getWorkspaceId();
    final String? workspaceName = await storage.getWorkspaceName();
    final String? mapFloorId = await storage.getMapSelectedFloorId();

    final List<AutomationRule> rules = await storage.getAutomationRules();
    final List<Colleague> allFavorites = await storage.getFavoriteColleagues();
    final List<Colleague> favorites =
        (maxFavorites != null && maxFavorites >= 0 && allFavorites.length > maxFavorites)
            ? allFavorites.sublist(0, maxFavorites)
            : allFavorites;

    final List<Map<String, String>> vacations = await storage.getVacations();
    final List<String> requestedDates = await storage.getRequestedDates();
    final Map<String, String> requestedWorkspaces =
        await storage.getRequestedWorkspacesMap();
    final Map<String, String> requestedWorkspaceNames =
        await storage.getRequestedWorkspaceNamesMap();
    final List<String> ignoredDates = await storage.getIgnoredDates();

    final int themeModeIndex = await storage.getThemeModeIndex();
    final int themeColorIndex = await storage.getThemeColorIndex();
    final int fontFamilyIndex = await storage.getFontFamilyIndex();
    final double uiScale = await storage.getUiScale();
    final bool compactMode = await storage.getCompactMode();
    final bool hideWeekends = await storage.getHideWeekends();
    final bool skipPublicHolidays = await storage.getSkipPublicHolidays();
    final String holidayCountry = await storage.getHolidayCountryCode();
    final bool automationEnabled = await storage.getAutomationEnabled();
    final Map<String, int> automationTime = await storage.getAutomationTime();
    final bool notifySuccess = await storage.getNotifySuccess();
    final bool notifyFailure = await storage.getNotifyFailure();
    final bool showFavoriteWeekIndicators =
        await storage.getShowFavoriteWeekIndicators();
    final int initialTabIndex = await storage.getInitialTab();
    final bool showDelegatedReservations =
        await storage.getShowDelegatedBookings();
    final bool pullToRefreshEnabled = await storage.getPullToRefresh();

    final Map<String, Object?> payload = <String, Object?>{
      'v': currentVersion,
      if (siteId != null && siteId.isNotEmpty) 's': siteId,
      if (floorId != null && floorId.isNotEmpty) 'f': floorId,
      if (workspaceId != null && workspaceId.isNotEmpty) 'w': workspaceId,
      if (workspaceName != null && workspaceName.isNotEmpty) 'wn': workspaceName,
      if (mapFloorId != null && mapFloorId.isNotEmpty) 'mf': mapFloorId,
      'rules': rules.map((AutomationRule r) => r.toJson()).toList(),
      'favs': favorites.map((Colleague c) => c.toJson()).toList(),
      'vac': vacations,
      'reqD': requestedDates,
      'reqW': requestedWorkspaces,
      'reqWn': requestedWorkspaceNames,
      'ignD': ignoredDates,
      'prefs': <String, Object?>{
        'tm': themeModeIndex,
        'tc': themeColorIndex,
        'ff': fontFamilyIndex,
        'us': uiScale,
        'cm': compactMode,
        'hw': hideWeekends,
        'sph': skipPublicHolidays,
        'hc': holidayCountry,
        'ae': automationEnabled,
        'at': automationTime,
        'ns': notifySuccess,
        'nf': notifyFailure,
        'fwi': showFavoriteWeekIndicators,
        'it': initialTabIndex,
        'sdb': showDelegatedReservations,
        'ptr': pullToRefreshEnabled,
      },
    };

    if (includeAuthToken) {
      final String? refreshToken = await storage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        payload['rt'] = refreshToken;
      }
    }

    final List<int> jsonUtf8 = utf8.encode(jsonEncode(payload));
    final Uint8List gzipped = const GZipEncoder().encodeBytes(jsonUtf8);
    final String compressedBase64 =
        base64Url.encode(gzipped).replaceAll('=', '');
    final String encrypted =
        await TokenCryptoService.encryptToken(compressedBase64);

    return includeAuthToken ? encrypted : '$fileHeaderPrefix$encrypted';
  }

  /// Extracts the encrypted `v2_...` payload from a URL (`#bundle=...` or
  /// `?bundle=...`), a `ROOMZIO2:...` code, or a raw `v2_...` token.
  static String? _extractEncryptedPayload(String rawInput) {
    final String trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith(fileHeaderPrefix)) {
      final String afterPrefix =
          trimmed.substring(fileHeaderPrefix.length).trim();
      return afterPrefix.isEmpty ? null : afterPrefix;
    }

    if (trimmed.startsWith('bundle=')) {
      final Map<String, String> params = Uri.splitQueryString(trimmed);
      final String? bundle = params['bundle']?.trim();
      return (bundle != null && bundle.isNotEmpty) ? bundle : null;
    }

    if (trimmed.contains('://') ||
        trimmed.contains('#') ||
        trimmed.contains('?bundle=')) {
      final Uri? uri = Uri.tryParse(trimmed);
      if (uri != null) {
        if (uri.fragment.isNotEmpty) {
          var normalized = uri.fragment;
          if (normalized.startsWith('#')) {
            normalized = normalized.substring(1);
          }
          if (normalized.startsWith('/?')) {
            normalized = normalized.substring(2);
          } else if (normalized.startsWith('/') || normalized.startsWith('?')) {
            normalized = normalized.substring(1);
          }
          try {
            final Map<String, String> fragParams =
                Uri.splitQueryString(normalized);
            final String? fragBundle = fragParams['bundle']?.trim();
            if (fragBundle != null && fragBundle.isNotEmpty) {
              return fragBundle;
            }
          } catch (_) {}
        }
        final String? queryBundle = uri.queryParameters['bundle']?.trim();
        if (queryBundle != null && queryBundle.isNotEmpty) {
          return queryBundle;
        }
      }
    }

    return trimmed;
  }

  static List<String> _parseStringList(Object? raw) {
    if (raw is! List<Object?>) return <String>[];
    return raw
        .where((Object? e) => e != null)
        .map((Object? e) => e.toString())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  static Map<String, String> _parseStringMap(Object? raw) {
    if (raw is! Map<Object?, Object?>) return <String, String>{};
    final Map<String, String> result = <String, String>{};
    raw.forEach((Object? k, Object? v) {
      if (k != null && v != null) {
        result[k.toString()] = v.toString();
      }
    });
    return result;
  }

  /// Imports a profile bundle from [rawInput] (URL `#bundle=...` / `?bundle=...`,
  /// `ROOMZIO2:...` `.roomzio` export, or raw `v2_...` string) and restores it
  /// into [storage].
  ///
  /// Auth tokens (`rt`) are ONLY applied when [applyAuthToken] is `true`.
  /// When [applyAuthToken] is `false`, any existing refresh token in [storage]
  /// is preserved untouched.
  static Future<ProfileImportResult> importBundle(
    String rawInput,
    StorageService storage, {
    bool applyAuthToken = false,
  }) async {
    final String? encryptedPayload = _extractEncryptedPayload(rawInput);
    if (encryptedPayload == null) {
      return const ProfileImportResult(
        success: false,
        errorMessage: 'Code ou lien de profil vide.',
      );
    }

    final String? decryptedStr =
        await TokenCryptoService.decryptToken(encryptedPayload);
    if (decryptedStr == null || decryptedStr.isEmpty) {
      return const ProfileImportResult(
        success: false,
        errorMessage:
            'Impossible de déchiffrer le profil (code invalide ou corrompu).',
      );
    }

    final Map<String, Object?> map;
    try {
      final Uint8List compressedBytes =
          base64Url.decode(base64Url.normalize(decryptedStr));
      final Uint8List decompressedBytes =
          const GZipDecoder().decodeBytes(compressedBytes, verify: true);
      final String jsonStr =
          utf8.decode(decompressedBytes, allowMalformed: false);
      final Object? decoded = jsonDecode(jsonStr);
      if (decoded is! Map<Object?, Object?>) {
        return const ProfileImportResult(
          success: false,
          errorMessage: 'Structure JSON du profil invalide.',
        );
      }
      map = decoded.map<String, Object?>(
        (Object? k, Object? v) => MapEntry<String, Object?>(k.toString(), v),
      );
    } catch (_) {
      return const ProfileImportResult(
        success: false,
        errorMessage: 'Contenu du profil corrompu ou illisible.',
      );
    }

    final Object? versionRaw = map['v'];
    if (versionRaw is! num || versionRaw.toInt() != currentVersion) {
      return const ProfileImportResult(
        success: false,
        errorMessage: 'Version de profil non supportée.',
      );
    }

    storage.clearMemoryCache();

    bool authTokenApplied = false;
    if (applyAuthToken) {
      final Object? rtRaw = map['rt'];
      if (rtRaw is String && rtRaw.isNotEmpty) {
        await storage.saveRefreshToken(rtRaw);
        authTokenApplied = true;
      }
    }

    final Object? siteId = map['s'];
    if (siteId is String && siteId.isNotEmpty) {
      await storage.saveSiteId(siteId);
    }
    final Object? floorId = map['f'];
    if (floorId is String && floorId.isNotEmpty) {
      await storage.saveFloorId(floorId);
    }
    final Object? workspaceId = map['w'];
    if (workspaceId is String && workspaceId.isNotEmpty) {
      await storage.saveWorkspaceId(workspaceId);
    }
    final Object? workspaceName = map['wn'];
    if (workspaceName is String && workspaceName.isNotEmpty) {
      await storage.saveWorkspaceName(workspaceName);
    }
    final Object? mapFloorId = map['mf'];
    if (mapFloorId is String && mapFloorId.isNotEmpty) {
      await storage.saveMapSelectedFloorId(mapFloorId);
    }

    int restoredRulesCount = 0;
    final Object? rawRules = map['rules'];
    if (rawRules is List<Object?>) {
      final List<AutomationRule> parsedRules = rawRules
          .whereType<Map<Object?, Object?>>()
          .map<AutomationRule>(
            (Map<Object?, Object?> item) =>
                AutomationRule.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();
      await storage.saveAutomationRules(parsedRules);
      restoredRulesCount = parsedRules.length;
    }

    int restoredFavoritesCount = 0;
    final Object? rawFavs = map['favs'];
    if (rawFavs is List<Object?>) {
      final List<Colleague> parsedFavs = rawFavs
          .whereType<Map<Object?, Object?>>()
          .map<Colleague>(
            (Map<Object?, Object?> item) =>
                Colleague.fromJson(Map<String, dynamic>.from(item))
                    .copyWith(isFavorite: true),
          )
          .toList();
      await storage.saveFavoriteColleagues(parsedFavs);
      restoredFavoritesCount = parsedFavs.length;
    }

    int restoredVacationsCount = 0;
    final Object? rawVacations = map['vac'];
    if (rawVacations is List<Object?>) {
      final List<Map<String, String>> parsedVacations = rawVacations
          .whereType<Map<Object?, Object?>>()
          .map<Map<String, String>>(
            (Map<Object?, Object?> item) => item.map<String, String>(
              (Object? k, Object? v) =>
                  MapEntry<String, String>(k.toString(), v?.toString() ?? ''),
            ),
          )
          .toList();
      await storage.saveVacations(parsedVacations);
      restoredVacationsCount = parsedVacations.length;
    }

    if (map.containsKey('reqD')) {
      await storage.saveRequestedDates(_parseStringList(map['reqD']));
    }
    if (map.containsKey('reqW')) {
      await storage.saveRequestedWorkspacesMap(_parseStringMap(map['reqW']));
    }
    if (map.containsKey('reqWn')) {
      await storage
          .saveRequestedWorkspaceNamesMap(_parseStringMap(map['reqWn']));
    }
    if (map.containsKey('ignD')) {
      await storage.saveIgnoredDates(_parseStringList(map['ignD']));
    }

    final Object? rawPrefs = map['prefs'];
    if (rawPrefs is Map<Object?, Object?>) {
      final Object? tm = rawPrefs['tm'];
      if (tm is num) await storage.saveThemeModeIndex(tm.toInt());

      final Object? tc = rawPrefs['tc'];
      if (tc is num) await storage.saveThemeColorIndex(tc.toInt());

      final Object? ff = rawPrefs['ff'];
      if (ff is num) await storage.saveFontFamilyIndex(ff.toInt());

      final Object? us = rawPrefs['us'];
      if (us is num) await storage.saveUiScale(us.toDouble());

      final Object? cm = rawPrefs['cm'];
      if (cm is bool) await storage.saveCompactMode(cm);

      final Object? hw = rawPrefs['hw'];
      if (hw is bool) await storage.saveHideWeekends(hw);

      final Object? sph = rawPrefs['sph'];
      if (sph is bool) await storage.saveSkipPublicHolidays(sph);

      final Object? hc = rawPrefs['hc'];
      if (hc is String && hc.isNotEmpty) {
        await storage.saveHolidayCountryCode(hc);
      }

      final Object? ae = rawPrefs['ae'];
      if (ae is bool) await storage.saveAutomationEnabled(ae);

      final Object? at = rawPrefs['at'];
      if (at is Map<Object?, Object?>) {
        final Object? hour = at['hour'];
        final Object? minute = at['minute'];
        if (hour is num && minute is num) {
          await storage.saveAutomationTime(hour.toInt(), minute.toInt());
        }
      }

      final Object? ns = rawPrefs['ns'];
      if (ns is bool) await storage.saveNotifySuccess(ns);

      final Object? nf = rawPrefs['nf'];
      if (nf is bool) await storage.saveNotifyFailure(nf);

      final Object? fwi = rawPrefs['fwi'];
      if (fwi is bool) await storage.saveShowFavoriteWeekIndicators(fwi);

      final Object? it = rawPrefs['it'];
      if (it is num) await storage.saveInitialTab(it.toInt());

      final Object? sdb = rawPrefs['sdb'];
      if (sdb is bool) await storage.saveShowDelegatedBookings(sdb);

      final Object? ptr = rawPrefs['ptr'];
      if (ptr is bool) await storage.savePullToRefresh(ptr);
    }

    return ProfileImportResult(
      success: true,
      restoredRulesCount: restoredRulesCount,
      restoredFavoritesCount: restoredFavoritesCount,
      restoredVacationsCount: restoredVacationsCount,
      authTokenApplied: authTokenApplied,
    );
  }
}
