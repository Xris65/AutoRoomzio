import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/apk_installer.dart';

/// Modal progress dialog that downloads an APK update with a 20-second timeout,
/// user-initiated cancellation, and explicit Android install error feedback.
class UpdateDownloadDialog extends StatefulWidget {
  final String url;
  final http.Client? httpClient;

  const UpdateDownloadDialog({
    super.key,
    required this.url,
    this.httpClient,
  });

  @override
  State<UpdateDownloadDialog> createState() => _UpdateDownloadDialogState();
}

class _UpdateDownloadDialogState extends State<UpdateDownloadDialog> {
  late final ApkInstaller _installer;
  double _progress = 0.0;
  String _downloaded = '0.0 MB';
  String _total = '0.0 MB';
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _installer = ApkInstaller(client: widget.httpClient);
    unawaited(_startDownload());
  }

  @override
  void dispose() {
    unawaited(_installer.cancel());
    super.dispose();
  }

  Future<void> _closeResources() async {
    await _installer.cancel();
  }

  Future<void> _handleCancelPressed() async {
    if (_isCancelling) return;
    setState(() => _isCancelling = true);
    await _closeResources();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _startDownload() async {
    final ApkInstallResult result = await _installer.downloadAndInstall(
      widget.url,
      onProgress: (int receivedBytes, int totalBytes) {
        if (!mounted || _isCancelling) return;
        setState(() {
          if (totalBytes > 0) {
            _progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            _total = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          }
          _downloaded =
              '${(receivedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
        });
      },
    );

    if (!mounted || _isCancelling) return;

    final ScaffoldMessengerState? messenger =
        ScaffoldMessenger.maybeOf(context);
    Navigator.of(context).pop();

    if (!result.success && !result.cancelled) {
      final String message = result.errorMessage ??
          'Impossible de télécharger ou d\'installer la mise à jour.';
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Téléchargement'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            backgroundColor: Colors.grey.withValues(alpha: 0.2),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                '$_downloaded / $_total',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${(_progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const ValueKey<String>('cancel_update_download_button'),
          onPressed: _isCancelling ? null : _handleCancelPressed,
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}
