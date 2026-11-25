import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../storage_service.dart';

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
  final String? zipUrl;
  final String? htmlUrl;

  const AppUpdateInfo({
    required this.latestVersion,
    required this.releaseNotes,
    this.apkUrl,
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

  AppUpdateService({
    this.client,
    StorageService? storage,
    Future<String> Function()? currentVersionProvider,
  })  : _storage = storage ?? StorageService(),
        _currentVersionProvider =
            currentVersionProvider ?? _defaultVersionProvider;

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

      String? apkUrl;
      String? zipUrl;
      final Object? rawAssets = decoded['assets'];
      if (rawAssets is List<Object?>) {
        for (final Object? asset in rawAssets) {
          if (asset is Map<Object?, Object?>) {
            final String name =
                (asset['name']?.toString() ?? '').toLowerCase();
            final String? downloadUrl =
                asset['browser_download_url']?.toString();
            if (name.endsWith('.apk') && apkUrl == null) {
              apkUrl = downloadUrl;
            }
            if (name.endsWith('.zip') && zipUrl == null) {
              zipUrl = downloadUrl;
            }
          }
        }
      }

      final String releaseNotes = decoded['body']?.toString() ?? '';
      final String? htmlUrl = decoded['html_url']?.toString();

      return AppUpdateCheckResult(
        status: AppUpdateStatus.updateAvailable,
        updateInfo: AppUpdateInfo(
          latestVersion: latestVersion,
          releaseNotes: releaseNotes,
          apkUrl: apkUrl,
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
}
