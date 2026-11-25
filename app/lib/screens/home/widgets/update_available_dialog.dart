import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/app_update_service.dart';
import '../../../widgets/update_download_dialog.dart';

/// Displays the release update dialog with clickable Markdown release notes
/// and platform-specific installation handling (Android APK / Windows ZIP).
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required AppUpdateInfo info,
  required Future<void> Function(String version) onIgnoreVersion,
}) async {
  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Mise à jour disponible 🎉'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Une nouvelle version (v${info.latestVersion}) est prête !',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.maxFinite,
              child: MarkdownBody(
                data: info.releaseNotes.isNotEmpty
                    ? info.releaseNotes
                    : 'Une nouvelle version de AutoRoomzio est disponible.',
                onTapLink: (String text, String? href, String title) {
                  if (href != null && href.isNotEmpty) {
                    final Uri? uri = Uri.tryParse(href);
                    if (uri != null) {
                      unawaited(
                        launchUrl(uri, mode: LaunchMode.externalApplication),
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text("Voulez-vous l'installer maintenant ?"),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () {
            unawaited(onIgnoreVersion(info.latestVersion));
            Navigator.pop(dialogContext);
          },
          child: Text(
            'Ignorer cette version',
            style: TextStyle(color: Colors.red.shade400),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
              final String? target = info.zipUrl ?? info.htmlUrl;
              if (target != null) {
                final Uri? uri = Uri.tryParse(target);
                if (uri != null) {
                  unawaited(
                    launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                }
              }
            } else if (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.android) {
              if (info.apkUrl != null) {
                if (!context.mounted) return;
                unawaited(
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (BuildContext _) =>
                        UpdateDownloadDialog(url: info.apkUrl!),
                  ),
                );
              } else if (info.htmlUrl != null) {
                final Uri? uri = Uri.tryParse(info.htmlUrl!);
                if (uri != null) {
                  unawaited(
                    launchUrl(uri, mode: LaunchMode.externalApplication),
                  );
                }
              }
            } else if (info.htmlUrl != null) {
              final Uri? uri = Uri.tryParse(info.htmlUrl!);
              if (uri != null) {
                unawaited(
                  launchUrl(uri, mode: LaunchMode.externalApplication),
                );
              }
            }
          },
          child: const Text('Installer'),
        ),
      ],
    ),
  );
}
