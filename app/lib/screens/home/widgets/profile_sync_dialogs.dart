import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/profile_sync_service.dart';
import '../../../storage_service.dart';

/// Displays an encrypted `.roomzio` configuration export modal without
/// disconnecting any existing device session.
Future<void> showExportProfileDialog(
  BuildContext context, {
  required StorageService storage,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => _ExportProfileDialog(storage: storage),
  );
}

/// Displays a modal allowing the user to paste and import a `.roomzio`
/// configuration code (`ROOMZIO2:...`) without altering their login token.
Future<void> showImportProfileDialog(
  BuildContext context, {
  required StorageService storage,
  required Future<void> Function(ProfileImportResult result) onImportSuccess,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext _) => _ImportProfileDialog(
      storage: storage,
      onImportSuccess: onImportSuccess,
    ),
  );
}

class _ExportProfileDialog extends StatefulWidget {
  final StorageService storage;

  const _ExportProfileDialog({required this.storage});

  @override
  State<_ExportProfileDialog> createState() => _ExportProfileDialogState();
}

class _ExportProfileDialogState extends State<_ExportProfileDialog> {
  String? _exportedCode;
  String? _errorMessage;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_generateExportCode());
  }

  Future<void> _generateExportCode() async {
    try {
      final String code = await ProfileSyncService.exportProfileCode(
        widget.storage,
        includeAuthToken: false,
      );
      if (mounted) {
        setState(() => _exportedCode = code);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              "Impossible de générer le code d'export pour le moment.",
        );
      }
    }
  }

  Future<void> _copyCode() async {
    final String? code = _exportedCode;
    if (code == null || code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) {
      setState(() => _copied = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AlertDialog(
      title: const Text('Exporter ma configuration (.roomzio)'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.security_rounded, color: scheme.primary, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Ce code chiffré transfère vos règles multi-bureaux, favoris, '
                        'congés, programmations et réglages sans déconnecter vos autres appareils.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: scheme.error),
                )
              else if (_exportedCode == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...<Widget>[
                Container(
                  constraints: const BoxConstraints(maxHeight: 160),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _exportedCode!,
                      key: const ValueKey<String>('exported_roomzio_code_text'),
                      style: const TextStyle(
                        fontFamily: 'FiraCode',
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
                if (_copied) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: Colors.green.shade600,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Code copié dans le presse-papiers !',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        if (_exportedCode != null)
          FilledButton.icon(
            key: const ValueKey<String>('copy_roomzio_code_btn'),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier le code'),
            onPressed: () => unawaited(_copyCode()),
          ),
      ],
    );
  }
}

class _ImportProfileDialog extends StatefulWidget {
  final StorageService storage;
  final Future<void> Function(ProfileImportResult result) onImportSuccess;

  const _ImportProfileDialog({
    required this.storage,
    required this.onImportSuccess,
  });

  @override
  State<_ImportProfileDialog> createState() => _ImportProfileDialogState();
}

class _ImportProfileDialogState extends State<_ImportProfileDialog> {
  late final TextEditingController _controller;
  bool _isImporting = false;
  String? _errorMessage;
  ProfileImportResult? _result;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitImport() async {
    if (_isImporting) return;
    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    final ProfileImportResult res = await ProfileSyncService.importBundle(
      _controller.text,
      widget.storage,
      applyAuthToken: false,
    );

    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _isImporting = false;
        _errorMessage = res.errorMessage ?? 'Code invalide ou corrompu.';
      });
      return;
    }

    await widget.onImportSuccess(res);
    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final ProfileImportResult? res = _result;

    if (res != null) {
      return AlertDialog(
        title: const Text('Configuration restaurée !'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.check_circle_rounded, color: Colors.green.shade600),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Votre profil .roomzio a été appliqué avec succès.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('• ${res.restoredRulesCount} règle(s) multi-bureaux'),
            const SizedBox(height: 4),
            Text('• ${res.restoredFavoritesCount} collègue(s) favori(s)'),
            const SizedBox(height: 4),
            Text('• ${res.restoredVacationsCount} période(s) de congés'),
          ],
        ),
        actions: <Widget>[
          FilledButton(
            key: const ValueKey<String>('close_import_roomzio_btn'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Importer une configuration (.roomzio)'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Collez votre code ROOMZIO2:... pour restaurer vos règles, favoris, '
                'congés et réglages sans modifier votre session active.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey<String>('import_roomzio_input'),
                controller: _controller,
                maxLines: 4,
                enabled: !_isImporting,
                decoration: const InputDecoration(
                  hintText: 'ROOMZIO2:v2_...',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: TextStyle(color: scheme.error, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const ValueKey<String>('confirm_import_roomzio_btn'),
          onPressed: _isImporting ? null : () => unawaited(_submitImport()),
          child: _isImporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Importer'),
        ),
      ],
    );
  }
}
