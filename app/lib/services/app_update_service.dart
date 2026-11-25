import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../storage_service.dart';
import '../utils/abi_helper.dart';

/// Status returned by [AppUpdateService.checkForUpdates].
enum AppUpdateStatus {
  updateAvailable,
  upToDate,
  serverError,
  networkError,
}

/// Parsed metadata for an available GitHub release.
class AppUpdateInfo {
  final String latestVersion;
  final String releaseNotes;
  final String? apkUrl;
  final String? universalApkUrl;
  final String? matchedAbi;
  final String? zipUrl;
  final String? htmlUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    this.apkUrl,
    this.universalApkUrl,
    this.matchedAbi,
    this.zipUrl,
    this.htmlUrl,
  });
}

/// Result wrapper returned by [AppUpdateService.checkForUpdates].
class AppUpdateCheckResult {
  final AppUpdateStatus status;
  final AppUpdateInfo? updateInfo;

  const AppUpdateCheckResult({
    required this.status,
    this.updateInfo,
  });
}

/// Service checking GitHub releases for AutoRoomzio updates with strict timeouts.
class AppUpdateService {
  static final Uri latestReleaseUri = Uri.parse(
    'https://api.github.com/repos/Xris65/AutoRoomzio/releases/latest',
  );

  static const Duration requestTimeout = Duration(seconds: 15);

  final http.Client? client;
  final StorageService _storage;
  final Future<String> Function() _currentVersionProvider;
  final Future<String?> Function() _abiProvider;

  AppUpdateService({
    this.client,
    StorageService? storage,
    Future<String> Function()? currentVersionProvider,
    Future<String?> Function()? abiProvider,
  })  : _storage = storage ?? StorageService(),
        _currentVersionProvider =
            currentVersionProvider ?? _defaultVersionProvider,
        _abiProvider = abiProvider ?? getPrimaryAndroidAbi;

  static Future<String> _defaultVersionProvider() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Compares semantic versions (`latest` vs `current`), ignoring optional `v`
  /// prefixes and `+build` suffixes.
  static bool isNewerVersion(String latest, String current) {
    final List<int> l = _parseVersionParts(latest);
    final List<int> c = _parseVersionParts(current);
    for (int i = 0; i < 3; i++) {
      final int lv = i < l.length ? l[i] : 0;
      final int cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static List<int> _parseVersionParts(String raw) {
    final String cleaned =
        raw.trim().replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    return cleaned
        .split('.')
        .map<int>((String part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }

  /// Queries GitHub latest release API with a 15-second timeout.
  Future<AppUpdateCheckResult> checkForUpdates({
    bool respectIgnoredVersion = false,
  }) async {
    final http.Client httpClient = client ?? http.Client();
    final bool ownsClient = client == null;

    try {
      final http.Response response =
          await httpClient.get(latestReleaseUri).timeout(requestTimeout);

      if (response.statusCode != 200) {
        return const AppUpdateCheckResult(status: AppUpdateStatus.serverError);
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<Object?, Object?>) {
        return const AppUpdateCheckResult(status: AppUpdateStatus.serverError);
      }

      final String? rawTag = decoded['tag_name']?.toString();
      if (rawTag == null || rawTag.trim().isEmpty) {
        return const AppUpdateCheckResult(status: AppUpdateStatus.serverError);
      }

      final String latestVersion =
          rawTag.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final String currentVersion = await _currentVersionProvider();
      final String? ignoredVersion =
          respectIgnoredVersion ? await _storage.getIgnoredUpdateVersion() : null;

      if (latestVersion == currentVersion ||
          !isNewerVersion(latestVersion, currentVersion) ||
          (respectIgnoredVersion && latestVersion == ignoredVersion)) {
        return const AppUpdateCheckResult(status: AppUpdateStatus.upToDate);
      }

      final List<({String name, String url})> apkAssets =
          <({String name, String url})>[];
      String? zipUrl;
      final Object? rawAssets = decoded['assets'];
      if (rawAssets is List<Object?>) {
        for (final Object? asset in rawAssets) {
          if (asset is Map<Object?, Object?>) {
            final String name =
                (asset['name']?.toString() ?? '').toLowerCase();
            final String? downloadUrl =
                asset['browser_download_url']?.toString();
            if (name.endsWith('.apk') &&
                downloadUrl != null &&
                downloadUrl.isNotEmpty) {
              apkAssets.add((name: name, url: downloadUrl));
            }
            if (name.endsWith('.zip') && zipUrl == null) {
              zipUrl = downloadUrl;
            }
          }
        }
      }

      final String? universalApkUrl = _findUniversalApkUrl(apkAssets);
      final String? firstApkUrl =
          apkAssets.isNotEmpty ? apkAssets.first.url : null;

      String? matchedAbi;
      String? apkUrl;
      if (apkAssets.isNotEmpty) {
        final String? rawAbi = await _abiProvider();
        final String? abi =
            (rawAbi != null && rawAbi.trim().isNotEmpty) ? rawAbi.trim() : null;
        if (abi != null) {
          final String abiSuffix = '-${abi.toLowerCase()}.apk';
          for (final ({String name, String url}) asset in apkAssets) {
            if (asset.name.contains(abiSuffix)) {
              apkUrl = asset.url;
              matchedAbi = abi;
              break;
            }
          }
        }
        apkUrl ??= universalApkUrl ?? firstApkUrl;
      }

      final String releaseNotes = decoded['body']?.toString() ?? '';
      final String? htmlUrl = decoded['html_url']?.toString();

      return AppUpdateCheckResult(
        status: AppUpdateStatus.updateAvailable,
        updateInfo: AppUpdateInfo(
          latestVersion: latestVersion,
          releaseNotes: releaseNotes,
          apkUrl: apkUrl,
          universalApkUrl: universalApkUrl,
          matchedAbi: matchedAbi,
          zipUrl: zipUrl,
          htmlUrl: htmlUrl,
        ),
      );
    } on TimeoutException {
      return const AppUpdateCheckResult(status: AppUpdateStatus.networkError);
    } catch (_) {
      return const AppUpdateCheckResult(status: AppUpdateStatus.networkError);
    } finally {
      if (ownsClient) {
        httpClient.close();
      }
    }
  }

  static const List<String> _abiSpecificSuffixes = <String>[
    '-arm64-v8a.apk',
    '-armeabi-v7a.apk',
    '-x86_64.apk',
    '-x86.apk',
    '-riscv64.apk',
  ];

  static String? _findUniversalApkUrl(
    List<({String name, String url})> apkAssets,
  ) {
    for (final ({String name, String url}) asset in apkAssets) {
      if (asset.name.contains('-universal.apk')) {
        return asset.url;
      }
    }
    for (final ({String name, String url}) asset in apkAssets) {
      final bool isAbiSpecific = _abiSpecificSuffixes.any(
        (String suffix) => asset.name.endsWith(suffix),
      );
      if (!isAbiSpecific) {
        return asset.url;
      }
    }
    return null;
  }
}
