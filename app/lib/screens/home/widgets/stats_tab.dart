import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../utils/date_helpers.dart';

/// Statistics tab showing upcoming bookings, favorite desk loyalty ratio,
/// automated vs manual booking counts, and configured weekly rhythm.
class StatsTab extends StatelessWidget {
  final Map<String, int> statsMap;
  final Set<String> bookedDates;
  final Map<String, String> bookedElsewhereMap;
  final List<int> selectedDays;
  final String? workspaceName;

  const StatsTab({
    super.key,
    required this.statsMap,
    required this.bookedDates,
    required this.bookedElsewhereMap,
    required this.selectedDays,
    required this.workspaceName,
  });

  void _showStatInfo(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return Container(
          margin: const EdgeInsets.all(16).copyWith(bottom: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(sheetContext).colorScheme.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: color.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 56),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                description,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Theme.of(sheetContext)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text(
                    "J'ai compris",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: tooltip != null
          ? () => _showStatInfo(context, title, tooltip, icon, color)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.8),
              ),
            ),
            if (subtitle != null) ...<Widget>[
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int manualCount = statsMap['manual'] ?? 0;
    final int autoCount = statsMap['auto'] ?? 0;

    final String todayStr = DateHelpers.formatIsoDate(DateTime.now());
    final Set<String> upcomingHere =
        bookedDates.where((String d) => d.compareTo(todayStr) >= 0).toSet();
    final Set<String> upcomingElsewhere = bookedElsewhereMap.keys
        .where((String d) => d.compareTo(todayStr) >= 0)
        .toSet();
    final int totalUpcoming = upcomingHere.length + upcomingElsewhere.length;

    final int favLoyaltyRatio = totalUpcoming > 0
        ? ((upcomingHere.length / totalUpcoming) * 100).round()
        : 100;

    final List<int> sortedDays = List<int>.from(selectedDays)..sort();
    final String rhythmDaysStr = sortedDays
        .map<String>((int d) => DateHelpers.frenchWeekdaysMap[d] ?? '')
        .where((String s) => s.isNotEmpty)
        .join(', ');
    final String rhythmValue = selectedDays.isEmpty
        ? 'Non configuré'
        : '${selectedDays.length} jour${selectedDays.length > 1 ? 's' : ''} / sem.';
    final String rhythmSubtitle = selectedDays.isEmpty
        ? (kIsWeb
            ? 'Non configuré'
            : "Définissez vos jours dans l'onglet Automate")
        : rhythmDaysStr;

    final List<Widget> statCards = <Widget>[
      _buildStatCard(
        context,
        title: 'Réservations à venir',
        value: '$totalUpcoming',
        subtitle: totalUpcoming > 0
            ? '${upcomingHere.length} sur bureau favori'
            : 'Aucune réservation',
        icon: Icons.event_available_rounded,
        color: Colors.blue,
        tooltip:
            "Nombre total de réservations confirmées à venir (aujourd'hui et 14 prochains jours) issues de MyRoomz.",
      ),
      _buildStatCard(
        context,
        title: 'Taux Bureau Favori',
        value: totalUpcoming > 0 ? '$favLoyaltyRatio%' : '-',
        subtitle: totalUpcoming > 0
            ? '${upcomingHere.length} sur $totalUpcoming à venir'
            : 'Aucune réservation',
        icon: Icons.star_rounded,
        color: Colors.green,
        tooltip:
            'Pourcentage de vos réservations à venir effectuées sur votre bureau habituel${workspaceName != null ? ' ($workspaceName)' : ''}.',
      ),
      if (!kIsWeb) ...<Widget>[
        _buildStatCard(
          context,
          title: 'Automatisées',
          value: '$autoCount',
          subtitle:
              autoCount > 0 ? '$autoCount via automate' : 'Par AutoRoomzio',
          icon: Icons.auto_awesome,
          color: Theme.of(context).colorScheme.primary,
          tooltip:
              "Nombre total de réservations créées automatiquement par l'automate en tâche de fond sur cet appareil.",
        ),
        _buildStatCard(
          context,
          title: 'Manuelles',
          value: '$manualCount',
          subtitle:
              manualCount > 0 ? '$manualCount en un clic' : 'En un clic',
          icon: Icons.touch_app_rounded,
          color: Colors.orange,
          tooltip:
              "Nombre total de réservations créées manuellement en un clic depuis l'application sur cet appareil.",
        ),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Text(
          'Vos Statistiques',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "L'impact de l'automatisation sur votre quotidien",
          style: TextStyle(
            fontSize: 14,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Cliquez sur une carte pour plus de détails',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext ctx, BoxConstraints constraints) {
            final bool isNarrow = constraints.maxWidth < 520;
            final SliverGridDelegate gridDelegate = isNarrow
                ? const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 0.86,
                  )
                : const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.05,
                  );

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: gridDelegate,
              itemCount: statCards.length,
              itemBuilder: (BuildContext _, int index) => statCards[index],
            );
          },
        ),
        if (!kIsWeb || selectedDays.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _buildStatCard(
            context,
            title: 'Rythme de Présence Paramétré',
            value: rhythmValue,
            subtitle: rhythmSubtitle,
            icon: Icons.schedule_rounded,
            color: Colors.indigo,
            tooltip:
                "Rythme de présence configuré dans l'application pour la réservation automatique de votre bureau.",
          ),
        ],
      ],
    );
  }
}
