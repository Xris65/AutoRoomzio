import 'package:http/http.dart' as http;

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

/// Web/Wasm-safe stub for APK download and installation so `dart:io` and
/// `package:open_filex/open_filex.dart` are never imported by `dart2js` or
/// `dart2wasm`.
class ApkInstaller {
  ApkInstaller({http.Client? client});

  Future<void> closeResources() async {}

  Future<void> cancel() async {}

  Future<ApkInstallResult> downloadAndInstall(
    String url, {
    required void Function(int receivedBytes, int totalBytes) onProgress,
  }) async {
    return const ApkInstallResult(
      success: false,
      errorMessage:
          'L\'installation d\'APK n\'est pas prise en charge sur cette plateforme.',
    );
  }
}
