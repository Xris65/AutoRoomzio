import 'package:flutter/material.dart';

/// Top-level navigation destinations in AutoRoomzio.
enum AppDestination { home, map, calendar, automation, stats, settings }

/// Metadata describing a visible navigation destination in [AdaptiveAppShell].
class AdaptiveNavItem {
  final AppDestination destination;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const AdaptiveNavItem({
    required this.destination,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

/// Responsive Material 3 application shell handling 3 breakpoints:
/// - Compact (`width < 600`): bottom [NavigationBar]
/// - Medium (`600 <= width < 1100`): [NavigationRail] + centered content
/// - Expanded (`width >= 1100`): [NavigationRail] (extended >= 1360) + optional
///   side-by-side Split-View with [splitMapPanel].
class AdaptiveAppShell extends StatelessWidget {
  final List<AdaptiveNavItem> destinations;
  final AppDestination selectedDestination;
  final ValueChanged<AppDestination> onDestinationSelected;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? splitMapPanel;
  final bool showSplitMap;
  final bool fullWidthBody;

  const AdaptiveAppShell({
    super.key,
    required this.destinations,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.body,
    this.appBar,
    this.splitMapPanel,
    this.showSplitMap = false,
    this.fullWidthBody = false,
  });

  int _resolveSelectedIndex() {
    if (destinations.isEmpty) return 0;
    final int idx = destinations.indexWhere(
      (AdaptiveNavItem item) => item.destination == selectedDestination,
    );
    return idx >= 0 ? idx : 0;
  }

  Widget _buildRail({
    required BuildContext context,
    required int selectedIndex,
    required bool extended,
  }) {
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints railConstraints) {
        final double requiredHeight = destinations.length * 72.0 + 16.0;
        final Widget rail = NavigationRail(
          selectedIndex: selectedIndex,
          extended: extended,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          onDestinationSelected: (int index) {
            if (index >= 0 && index < destinations.length) {
              onDestinationSelected(destinations[index].destination);
            }
          },
          destinations: destinations
              .map<NavigationRailDestination>(
                (AdaptiveNavItem item) => NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
              )
              .toList(),
        );
        if (railConstraints.maxHeight >= requiredHeight) {
          return rail;
        }
        return SingleChildScrollView(
          child: SizedBox(
            height: requiredHeight,
            child: rail,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final int selectedIndex = _resolveSelectedIndex();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;

        // 1. Compact (< 600px): Mobile portrait with Material 3 NavigationBar.
        if (width < 600) {
          final double labelFontSize = width < 420 ? 10.5 : 11.5;
          final ThemeData theme = Theme.of(context);
          final NavigationBarThemeData navBarTheme = NavigationBarThemeData(
            height: 68,
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
              (Set<WidgetState> states) {
                final bool selected = states.contains(WidgetState.selected);
                return TextStyle(
                  fontSize: labelFontSize,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  overflow: TextOverflow.ellipsis,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                );
              },
            ),
          );

          return Scaffold(
            appBar: appBar,
            body: body,
            bottomNavigationBar: NavigationBarTheme(
              data: navBarTheme,
              child: NavigationBar(
                selectedIndex: selectedIndex,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: (int index) {
                  if (index >= 0 && index < destinations.length) {
                    onDestinationSelected(destinations[index].destination);
                  }
                },
                destinations: destinations
                    .map<NavigationDestination>(
                      (AdaptiveNavItem item) => NavigationDestination(
                        icon: Icon(item.icon),
                        selectedIcon: Icon(item.selectedIcon),
                        label: item.label,
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }

        // 2. Medium (600 <= width < 1100): Tablet / half-window desktop.
        if (width < 1100) {
          return Scaffold(
            appBar: appBar,
            body: Row(
              children: <Widget>[
                _buildRail(
                  context: context,
                  selectedIndex: selectedIndex,
                  extended: false,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: fullWidthBody
                      ? body
                      : Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: body,
                          ),
                        ),
                ),
              ],
            ),
          );
        }

        // 3. Expanded (width >= 1100): Desktop / Web Wasm with optional Split-View.
        final bool isExtended = width >= 1360;
        final bool splitActive = showSplitMap && splitMapPanel != null;

        return Scaffold(
          appBar: appBar,
          body: Row(
            children: <Widget>[
              _buildRail(
                context: context,
                selectedIndex: selectedIndex,
                extended: isExtended,
              ),
              const VerticalDivider(width: 1, thickness: 1),
              if (splitActive) ...<Widget>[
                SizedBox(
                  width: 440,
                  child: body,
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(child: splitMapPanel!),
              ] else if (fullWidthBody)
                Expanded(child: body)
              else
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: body,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
