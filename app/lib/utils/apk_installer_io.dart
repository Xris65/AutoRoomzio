import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'error_sanitizer.dart';

/// Result of downloading and launching an APK installation.
class ApkInstallResult {
  final bool success;
  final bool permissionDenied;
  final bool cancelled;
  final String? errorMessage;

  const ApkInstallResult({
    required this.success,
    this.permissionDenied = false,
    this.cancelled = false,
    this.errorMessage,
  });
}

/// Native `dart:io` implementation for downloading an APK to temporary storage,
/// verifying Android install-package permission, and opening it via [OpenFilex].
class ApkInstaller {
  http.Client? _httpClient;
  StreamSubscription<List<int>>? _subscription;
  IOSink? _sink;
  Completer<ApkInstallResult>? _activeCompleter;
  bool _isCancelled = false;

  ApkInstaller({http.Client? client}) : _httpClient = client ?? http.Client();

  Future<void> closeResources() async {
    await _subscription?.cancel();
    _subscription = null;

    await _sink?.close();
    _sink = null;

    _httpClient?.close();
    _httpClient = null;
  }

  Future<void> cancel() async {
    _isCancelled = true;
    await closeResources();
    final Completer<ApkInstallResult>? completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(
        const ApkInstallResult(success: false, cancelled: true),
      );
    }
  }

  Future<ApkInstallResult> downloadAndInstall(
    String url, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
  }) async {
    _isCancelled = false;
    final http.Client client = _httpClient ?? http.Client();
    _httpClient = client;

    try {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        await closeResources();
        return const ApkInstallResult(
          success: false,
          errorMessage: 'URL de téléchargement invalide.',
        );
      }

      final http.Request request = http.Request('GET', uri);
      final http.StreamedResponse response =
          await client.send(request).timeout(const Duration(seconds: 20));

      if (_isCancelled) {
        await closeResources();
        return const ApkInstallResult(success: false, cancelled: true);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await closeResources();
        return ApkInstallResult(
          success: false,
          errorMessage:
              'Erreur serveur lors du téléchargement (${response.statusCode}).',
        );
      }

      final int contentLength = response.contentLength ?? 0;
      int receivedBytes = 0;

      final Directory tempDir = await getTemporaryDirectory();
      if (_isCancelled) {
        await closeResources();
        return const ApkInstallResult(success: false, cancelled: true);
      }

      final File file = File('${tempDir.path}/AutoRoomzio_update.apk');
      _sink = file.openWrite();

      final Completer<ApkInstallResult> completer = Completer<ApkInstallResult>();
      _activeCompleter = completer;

      _subscription = response.stream
          .timeout(const Duration(seconds: 20))
          .listen(
        (List<int> chunk) {
          if (_isCancelled) return;
          receivedBytes += chunk.length;
          _sink?.add(chunk);
          onProgress(receivedBytes, contentLength);
        },
        onDone: () async {
          await closeResources();
          if (completer.isCompleted) return;
          if (_isCancelled) {
            completer.complete(
              const ApkInstallResult(success: false, cancelled: true),
            );
            return;
          }

          final ApkInstallResult installResult =
              await _verifyPermissionAndOpenApk(file.path);
          if (!completer.isCompleted) {
            completer.complete(installResult);
          }
        },
        onError: (Object error) async {
          await closeResources();
          if (completer.isCompleted) return;
          if (_isCancelled) {
            completer.complete(
              const ApkInstallResult(success: false, cancelled: true),
            );
            return;
          }
          completer.complete(
            ApkInstallResult(
              success: false,
              errorMessage: error is TimeoutException
                  ? 'Délai de téléchargement dépassé.'
                  : ErrorSanitizer.sanitize(
                      error,
                      fallback: 'Erreur lors du téléchargement de la mise à jour.',
                    ),
            ),
          );
        },
        cancelOnError: true,
      );

      return await completer.future;
    } on TimeoutException {
      await closeResources();
      if (_isCancelled) {
        return const ApkInstallResult(success: false, cancelled: true);
      }
      return const ApkInstallResult(
        success: false,
        errorMessage: 'Délai de connexion dépassé lors du téléchargement.',
      );
    } catch (e) {
      await closeResources();
      if (_isCancelled) {
        return const ApkInstallResult(success: false, cancelled: true);
      }
      return ApkInstallResult(
        success: false,
        errorMessage: ErrorSanitizer.sanitize(
          e,
          fallback: 'Erreur lors du téléchargement de la mise à jour.',
        ),
      );
    } finally {
      _activeCompleter = null;
    }
  }

  Future<ApkInstallResult> _verifyPermissionAndOpenApk(String filePath) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        PermissionStatus status =
            await Permission.requestInstallPackages.status;
        if (!status.isGranted) {
          status = await Permission.requestInstallPackages.request();
        }
        if (!status.isGranted) {
          return const ApkInstallResult(
            success: false,
            permissionDenied: true,
            errorMessage:
                'Permission d\'installer des applications inconnues refusée.',
          );
        }
      } on MissingPluginException {
        // Native permission plugin unavailable in headless unit tests.
      } catch (e) {
        return ApkInstallResult(
          success: false,
          errorMessage: ErrorSanitizer.sanitize(
            e,
            fallback: 'Impossible de vérifier la permission d\'installation.',
          ),
        );
      }
    }

    try {
      final OpenResult result = await OpenFilex.open(filePath);
      if (result.type != ResultType.done) {
        return ApkInstallResult(
          success: false,
          errorMessage: result.message.isNotEmpty
              ? 'Impossible de lancer l\'installation : ${result.message}'
              : 'Impossible de lancer l\'installation de l\'APK.',
        );
      }
      return const ApkInstallResult(success: true);
    } on MissingPluginException {
      return const ApkInstallResult(
        success: false,
        errorMessage: 'Impossible de lancer l\'installateur APK.',
      );
    } catch (e) {
      return ApkInstallResult(
        success: false,
        errorMessage: ErrorSanitizer.sanitize(
          e,
          fallback: 'Impossible d\'ouvrir le fichier APK.',
        ),
      );
    }
  }
}
