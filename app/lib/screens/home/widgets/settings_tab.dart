import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../holiday_service.dart';
import '../../../main.dart';
import '../../../notification_service.dart';

/// Settings tab displaying theme, navigation, dashboard, calendar,
/// notification, and about/update controls without instantiating Futures in `build()`.
class SettingsTab extends StatelessWidget {
  final int initialTab;
  final ValueChanged<int> onInitialTabChanged;
  final bool showAutomation;
  final ValueChanged<bool> onShowAutomationChanged;
  final bool showStats;
  final ValueChanged<bool> onShowStatsChanged;
  final bool pullToRefreshEnabled;
  final ValueChanged<bool> onPullToRefreshChanged;
  final bool showFavoriteWeekIndicators;
  final ValueChanged<bool> onShowFavoriteWeekIndicatorsChanged;
  final int projectionsCount;
  final ValueChanged<int> onProjectionsCountChanged;
  final bool hideWeekends;
  final ValueChanged<bool> onHideWeekendsChanged;
  final bool skipPublicHolidays;
  final ValueChanged<bool> onSkipPublicHolidaysChanged;
  final String holidayCountryCode;
  final ValueChanged<String> onHolidayCountryCodeChanged;
  final bool compactMode;
  final ValueChanged<bool> onCompactModeChanged;
  final bool notifySuccess;
  final ValueChanged<bool> onNotifySuccessChanged;
  final bool notifyFailure;
  final ValueChanged<bool> onNotifyFailureChanged;
  final String appVersion;
  final Future<void> Function() onCheckForUpdates;
  final ValueChanged<int> onSaveThemeModeIndex;
  final ValueChanged<int> onSaveThemeColorIndex;
  final ValueChanged<int> onSaveFontFamilyIndex;
  final ValueChanged<double> onSaveUiScale;
  final VoidCallback? onExportProfile;
  final VoidCallback? onImportProfile;

  const SettingsTab({
    super.key,
    required this.initialTab,
    required this.onInitialTabChanged,
    required this.showAutomation,
    required this.onShowAutomationChanged,
    required this.showStats,
    required this.onShowStatsChanged,
    required this.pullToRefreshEnabled,
    required this.onPullToRefreshChanged,
    required this.showFavoriteWeekIndicators,
    required this.onShowFavoriteWeekIndicatorsChanged,
    required this.projectionsCount,
    required this.onProjectionsCountChanged,
    required this.hideWeekends,
    required this.onHideWeekendsChanged,
    required this.skipPublicHolidays,
    required this.onSkipPublicHolidaysChanged,
    required this.holidayCountryCode,
    required this.onHolidayCountryCodeChanged,
    required this.compactMode,
    required this.onCompactModeChanged,
    required this.notifySuccess,
    required this.onNotifySuccessChanged,
    required this.notifyFailure,
    required this.onNotifyFailureChanged,
    required this.appVersion,
    required this.onCheckForUpdates,
    required this.onSaveThemeModeIndex,
    required this.onSaveThemeColorIndex,
    required this.onSaveFontFamilyIndex,
    required this.onSaveUiScale,
    this.onExportProfile,
    this.onImportProfile,
  });

  Widget _buildStyledDropdown<T>(
    BuildContext context, {
    required T value,
    required void Function(T?) onChanged,
    required List<DropdownMenuItem<T>> items,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down_rounded, size: 24),
          focusColor: Colors.transparent,
          dropdownColor: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          onChanged: onChanged,
          items: items,
        ),
      ),
    );
  }

  Future<void> _handleTestNotification(BuildContext context) async {
    final NotificationService notifService = NotificationService();
    final bool isMobile = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (isMobile) {
      final bool granted = await notifService.requestPermissionIfNeeded();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Permission de notification refusée. Activez les notifications dans les paramètres du système.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }
    await notifService.showNotification(
      title: 'AutoRoomzio - Test',
      body:
          'Ceci est une notification de test ! Si tu vois ça, tout fonctionne. 🎉',
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<DropdownMenuItem<int>> initialTabItems =
        <DropdownMenuItem<int>>[
      const DropdownMenuItem<int>(
        value: 0,
        child: Text('Accueil (par défaut)'),
      ),
      const DropdownMenuItem<int>(value: 5, child: Text('Plan')),
      const DropdownMenuItem<int>(value: 1, child: Text('Calendrier')),
      if (!kIsWeb && showAutomation)
        const DropdownMenuItem<int>(value: 2, child: Text('Automate')),
    ];
    final int safeInitialTab = initialTabItems.any(
      (DropdownMenuItem<int> item) => item.value == initialTab,
    )
        ? initialTab
        : 0;

    return ListView(
      key: const PageStorageKey<String>('settings_scroll'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Apparence & Personnalisation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (
                  BuildContext ctx,
                  ThemeMode currentMode,
                  Widget? _,
                ) {
                  final bool isDark = currentMode == ThemeMode.dark ||
                      (currentMode == ThemeMode.system &&
                          MediaQuery.of(ctx).platformBrightness ==
                              Brightness.dark);
                  return SwitchListTile(
                    title: const Text('Mode sombre'),
                    secondary: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                    ),
                    value: isDark,
                    onChanged: (bool val) {
                      themeNotifier.value =
                          val ? ThemeMode.dark : ThemeMode.light;
                      onSaveThemeModeIndex(val ? 2 : 1);
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Couleur du thème'),
                leading: const Icon(Icons.color_lens_rounded),
                trailing: ValueListenableBuilder<int>(
                  valueListenable: themeColorNotifier,
                  builder: (BuildContext ctx, int currentColor, Widget? _) {
                    return _buildStyledDropdown<int>(
                      ctx,
                      value: currentColor,
                      onChanged: (int? val) {
                        if (val != null) {
                          themeColorNotifier.value = val;
                          onSaveThemeColorIndex(val);
                        }
                      },
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(
                          value: 0,
                          child: Text('Bleu (par défaut)'),
                        ),
                        DropdownMenuItem<int>(value: 1, child: Text('Vert')),
                        DropdownMenuItem<int>(value: 2, child: Text('Violet')),
                        DropdownMenuItem<int>(value: 3, child: Text('Orange')),
                        DropdownMenuItem<int>(value: 4, child: Text('Rouge')),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<int>(
                valueListenable: fontNotifier,
                builder: (BuildContext ctx, int currentFont, Widget? _) {
                  return ListTile(
                    title: const Text("Police d'écriture"),
                    leading: const Icon(Icons.font_download_rounded),
                    trailing: _buildStyledDropdown<int>(
                      ctx,
                      value: currentFont,
                      onChanged: (int? val) {
                        if (val != null) {
                          fontNotifier.value = val;
                          onSaveFontFamilyIndex(val);
                        }
                      },
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem<int>(
                          value: 0,
                          child: Text('Classique'),
                        ),
                        DropdownMenuItem<int>(
                          value: 1,
                          child: Text('Moderne (Poppins)'),
                        ),
                        DropdownMenuItem<int>(
                          value: 2,
                          child: Text('Code (Fira)'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ValueListenableBuilder<double>(
                valueListenable: uiScaleNotifier,
                builder: (BuildContext ctx, double currentScale, Widget? _) {
                  double selectedValue = 1.0;
                  if ((currentScale - 0.85).abs() < 0.01) {
                    selectedValue = 0.85;
                  } else if ((currentScale - 1.15).abs() < 0.01) {
                    selectedValue = 1.15;
                  }
                  return ListTile(
                    title: const Text("Taille de l'interface"),
                    leading: const Icon(Icons.format_size_rounded),
                    trailing: _buildStyledDropdown<double>(
                      ctx,
                      value: selectedValue,
                      onChanged: (double? val) {
                        if (val != null) {
                          uiScaleNotifier.value = val;
                          onSaveUiScale(val);
                        }
                      },
                      items: const <DropdownMenuItem<double>>[
                        DropdownMenuItem<double>(
                          value: 0.85,
                          child: Text('Réduite (85%)'),
                        ),
                        DropdownMenuItem<double>(
                          value: 1.0,
                          child: Text('Normale (100%)'),
                        ),
                        DropdownMenuItem<double>(
                          value: 1.15,
                          child: Text('Agrandie (115%)'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Interface & Navigation',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              ListTile(
                title: const Text('Page de démarrage'),
                subtitle: const Text(
                  "Onglet affiché à l'ouverture",
                  style: TextStyle(fontSize: 12),
                ),
                leading: const Icon(Icons.home_rounded),
                trailing: _buildStyledDropdown<int>(
                  context,
                  value: safeInitialTab,
                  onChanged: (int? val) {
                    if (val != null) {
                      onInitialTabChanged(val);
                    }
                  },
                  items: initialTabItems,
                ),
              ),
              if (!kIsWeb) ...<Widget>[
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text("Afficher l'onglet Automatisation"),
                  secondary: const Icon(Icons.auto_awesome),
                  value: showAutomation,
                  onChanged: onShowAutomationChanged,
                ),
              ],
              const Divider(height: 1),
              SwitchListTile(
                title: const Text("Afficher l'onglet Statistiques"),
                secondary: const Icon(Icons.insights_rounded),
                value: showStats,
                onChanged: onShowStatsChanged,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Tirer pour rafraîchir'),
                subtitle: const Text(
                  'Actualiser en glissant vers le bas (Accueil, Calendrier)',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.refresh_rounded),
                value: pullToRefreshEnabled,
                onChanged: onPullToRefreshChanged,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('toggle_favorite_week_indicators'),
                title: const Text('Présence des favoris sur la semaine'),
                subtitle: const Text(
                  'Afficher les compteurs ⭐ par jour sur la barre de la semaine',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.star_outline_rounded),
                value: showFavoriteWeekIndicators,
                onChanged: onShowFavoriteWeekIndicatorsChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          "Paramètres de l'Accueil",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              ListTile(
                title: const Text('Prévisions à afficher'),
                subtitle: const Text(
                  'Nombre de jours de réservations futures affichés',
                  style: TextStyle(fontSize: 12),
                ),
                leading: const Icon(Icons.format_list_numbered),
                trailing: _buildStyledDropdown<int>(
                  context,
                  value: projectionsCount,
                  onChanged: (int? val) {
                    if (val != null) {
                      onProjectionsCountChanged(val);
                    }
                  },
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem<int>(value: 2, child: Text('2 jours')),
                    DropdownMenuItem<int>(
                      value: 4,
                      child: Text('4 jours (par défaut)'),
                    ),
                    DropdownMenuItem<int>(value: 7, child: Text('7 jours')),
                    DropdownMenuItem<int>(
                      value: 13,
                      child: Text('13 jours (Max)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Paramètres du Calendrier',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SwitchListTile(
                title: const Text('Désactiver le week-end'),
                subtitle: const Text(
                  'Grise le samedi/dimanche, bloque les réservations',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.weekend_rounded),
                value: hideWeekends,
                onChanged: onHideWeekendsChanged,
              ),
              const Divider(height: 1),
              SwitchListTile(
                key: const ValueKey<String>('toggle_skip_public_holidays'),
                title: const Text('Jours fériés'),
                subtitle: const Text(
                  'Affiche les jours fériés sur le calendrier et suspend les réservations automatiques',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  Icons.celebration_rounded,
                  color:
                      skipPublicHolidays ? Colors.amber.shade700 : Colors.grey,
                ),
                value: skipPublicHolidays,
                onChanged: onSkipPublicHolidaysChanged,
              ),
              if (skipPublicHolidays)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Calendrier des jours fériés',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        key: const ValueKey<String>('holiday_country_selector'),
                        spacing: 8,
                        runSpacing: 6,
                        children: HolidayService.supportedCountries.entries
                            .map<Widget>((MapEntry<String, String> entry) {
                          final bool isSelected =
                              holidayCountryCode == entry.key;
                          return ChoiceChip(
                            label: Text(entry.value),
                            selected: isSelected,
                            onSelected: (bool selected) {
                              if (!selected) return;
                              onHolidayCountryCodeChanged(entry.key);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Affichage compact'),
                subtitle: const Text(
                  "Réduit les marges pour voir plus d'informations",
                  style: TextStyle(fontSize: 12),
                ),
                secondary: const Icon(Icons.view_compact_rounded),
                value: compactMode,
                onChanged: onCompactModeChanged,
              ),
            ],
          ),
        ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(height: 24),
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.lightBlue,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  title: const Text('Réservations réussies'),
                  subtitle: const Text(
                    "Être notifié quand l'automatisation réserve",
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: const Icon(
                    Icons.notifications_active,
                    color: Colors.green,
                  ),
                  value: notifySuccess,
                  onChanged: onNotifySuccessChanged,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Échecs de réservation'),
                  subtitle: const Text(
                    "Être notifié en cas d'erreur (ex: plus de place)",
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: const Icon(Icons.error_outline, color: Colors.red),
                  value: notifyFailure,
                  onChanged: onNotifyFailureChanged,
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text(
                    'Tester les notifications',
                    style: TextStyle(color: Colors.blue),
                  ),
                  subtitle: const Text(
                    'Envoyer une notification de test',
                    style: TextStyle(fontSize: 12),
                  ),
                  leading: const Icon(Icons.send_rounded, color: Colors.blue),
                  onTap: () => _handleTestNotification(context),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Sauvegarde & Synchronisation (.roomzio)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              ListTile(
                key: const ValueKey<String>('export_roomzio_tile'),
                leading: const Icon(
                  Icons.upload_file_rounded,
                  color: Colors.lightBlue,
                ),
                title: const Text('Exporter ma configuration (.roomzio)'),
                subtitle: const Text(
                  'Générer un code chiffré sans déconnecter vos autres appareils',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onExportProfile,
              ),
              const Divider(height: 1),
              ListTile(
                key: const ValueKey<String>('import_roomzio_tile'),
                leading: const Icon(
                  Icons.download_for_offline_rounded,
                  color: Colors.green,
                ),
                title: const Text('Importer une configuration (.roomzio)'),
                subtitle: const Text(
                  'Restaurer règles, favoris, congés et réglages depuis un code',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: onImportProfile,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'À propos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.lightBlue,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                trailing: Text(appVersion),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code Source'),
                subtitle: const Text(
                  'Voir le projet sur GitHub',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () {
                  final Uri url =
                      Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  unawaited(
                    launchUrl(url, mode: LaunchMode.externalApplication),
                  );
                },
              ),
              if (!kIsWeb) ...<Widget>[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.system_update_rounded,
                    color: Colors.green,
                  ),
                  title: const Text(
                    'Rechercher des mises à jour',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Vérifier si une nouvelle version est disponible',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: Colors.green,
                  ),
                  onTap: onCheckForUpdates,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
