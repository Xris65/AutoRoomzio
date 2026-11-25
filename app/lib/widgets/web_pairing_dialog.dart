import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:workmanager/workmanager.dart';
import '../screens/login_screen.dart';
import '../storage_service.dart';
import '../token_crypto.dart';

/// Prompts the user for confirmation, invalidates the local session (and stops
/// Android background tasks), then displays [WebPairingDialog] with a secure
/// `#token=...` fragment URL before redirecting to [LoginScreen].
Future<void> showWebPairingDialog(
  BuildContext context, {
  required StorageService storage,
  String? siteId,
  String? floorId,
  String? workspaceId,
  String? workspaceName,
  VoidCallback? onLoggedOut,
}) async {
  final bool? confirm = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Attention'),
      content: const Text(
        'Le transfert de session vers le Web va déconnecter cette application. '
        'L\'automate en arrière-plan sera arrêté.\n\n'
        'Une fois le QR Code généré, la session actuelle sera détruite pour des raisons de sécurité. '
        'Voulez-vous continuer ?',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Annuler'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Transférer', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );

  if (confirm != true) return;

  final String? token = await storage.getRefreshToken();
  if (token == null || token.isEmpty) return;

  final String bId = siteId ?? await storage.getBuildingId() ?? '';
  final String fId = floorId ?? await storage.getFloorId() ?? '';
  final String wId = workspaceId ?? await storage.getWorkspaceId() ?? '';
  final String wNameRaw = workspaceName ?? await storage.getWorkspaceName() ?? '';

  await storage.clearTokens();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Workmanager().cancelAll();
    } catch (_) {}
  }

  final String url = WebPairingDialog.buildPairingUrl(
    refreshToken: token,
    buildingId: bId,
    floorId: fId,
    workspaceId: wId,
    workspaceName: wNameRaw,
  );

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext _) => WebPairingDialog(pairingUrl: url),
  );

  if (!context.mounted) return;
  if (onLoggedOut != null) {
    onLoggedOut();
    return;
  }

  await storage.clearTokens();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil<void>(
    MaterialPageRoute<void>(
      builder: (_) => const LoginScreen(ignoreUrlToken: true),
      settings: const RouteSettings(name: '/'),
    ),
    (Route<dynamic> route) => false,
  );
}

/// Shared modal dialog displaying a QR Code and copy/open actions for pairing
/// a Web session using an encrypted `#token=...` URI fragment.
class WebPairingDialog extends StatelessWidget {
  final String pairingUrl;

  const WebPairingDialog({
    super.key,
    required this.pairingUrl,
  });

  /// Builds the Web pairing URL placing sensitive parameters inside the URL
  /// fragment (`#token=...&b=...&f=...&w=...&wn=...`) so tokens are never sent
  /// over HTTP requests or logged by servers/proxies.
  static String buildPairingUrl({
    required String refreshToken,
    String buildingId = '',
    String floorId = '',
    String workspaceId = '',
    String workspaceName = '',
  }) {
    final String encrypted = TokenCryptoService.encryptToken(refreshToken);
    final String encodedToken = Uri.encodeComponent(encrypted);
    final String backupParam =
        '&b=${Uri.encodeComponent(buildingId)}'
        '&f=${Uri.encodeComponent(floorId)}'
        '&w=${Uri.encodeComponent(workspaceId)}'
        '&wn=${Uri.encodeComponent(workspaceName)}';

    final bool isLocalWeb = kIsWeb &&
        (Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1');
    final String baseUrl = (kIsWeb && !isLocalWeb)
        ? '${Uri.base.origin}${Uri.base.path}'
        : (kReleaseMode
            ? 'https://xris65.github.io/AutoRoomzio/'
            : 'https://xris65.github.io/AutoRoomzio/recette/');

    return '$baseUrl#token=$encodedToken$backupParam';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connecter un appareil Web'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Scannez ce QR Code avec l\'appareil photo de votre smartphone pour vous connecter automatiquement sur la version Web.\n\nVous pouvez aussi l\'ouvrir directement sur ce PC :',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attention : la session de cette application vient d\'être détruite. Une fois ce panneau fermé, vous serez redirigé vers l\'écran de connexion.',
                      style: TextStyle(color: Colors.orange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                key: const ValueKey<String>('web_pairing_qr'),
                data: pairingUrl,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ElevatedButton.icon(
                  key: const ValueKey<String>('web_pairing_open_btn'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Ouvrir le lien'),
                  onPressed: () {
                    launchUrl(
                      Uri.parse(pairingUrl),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const ValueKey<String>('web_pairing_copy_btn'),
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copier le lien',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: pairingUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Lien copié dans le presse-papiers'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ElevatedButton(
          key: const ValueKey<String>('web_pairing_close_btn'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Fermer et se déconnecter',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
