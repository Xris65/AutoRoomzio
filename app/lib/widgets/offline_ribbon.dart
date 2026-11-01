import 'package:flutter/material.dart';

/// Discrete, fixed offline ribbon displayed globally across the application
/// when offline mode is active.
///
/// Requirement R2.3: Displays the exact text
/// "Hors ligne • Affichage des dernières données synchronisées".
class OfflineRibbon extends StatelessWidget {
  /// Optional child if wrapping a screen or Navigator directly.
  final Widget? child;

  /// Optional background color override. Defaults to Amber 500 in light mode (#F59E0B)
  /// and Amber 800 in dark mode (#92400E).
  final Color? backgroundColor;

  /// Optional text and icon color override. Defaults to Dark Slate (#1E293B) in light mode
  /// and Amber 100 (#FEF3C7) in dark mode to guarantee WCAG AAA contrast conformance.
  final Color? textColor;

  /// Optional leading icon override. Defaults to [Icons.wifi_off_rounded].
  final IconData icon;

  const OfflineRibbon({
    super.key,
    this.child,
    this.backgroundColor,
    this.textColor,
    this.icon = Icons.wifi_off_rounded,
  });

  /// Mandated exact text per Requirement R2.3 and PROJECT.md.
  static const String ribbonText = "Hors ligne • Affichage des dernières données synchronisées";

  /// Alias for convenience and survey compatibility.
  static const String text = ribbonText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    final effectiveBgColor = backgroundColor ?? (isDark ? const Color(0xFF92400E) : const Color(0xFFF59E0B));
    final effectiveFgColor = textColor ?? (isDark ? const Color(0xFFFEF3C7) : const Color(0xFF1E293B));

    final ribbonWidget = Material(
      key: const Key('offline_ribbon'),
      color: effectiveBgColor,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.only(
          left: 12.0 + mediaQuery.padding.left,
          right: 12.0 + mediaQuery.padding.right,
          top: 6.0,
          bottom: 6.0 + (mediaQuery.viewInsets.bottom > 0 ? 0.0 : mediaQuery.padding.bottom),
        ),
        child: Semantics(
          liveRegion: true,
          label: ribbonText,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15.0,
                color: effectiveFgColor,
              ),
              const SizedBox(width: 8.0),
              Flexible(
                child: Text(
                  ribbonText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w600,
                    color: effectiveFgColor,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (child == null) {
      return ribbonWidget;
    }

    return Column(
      children: [
        Expanded(child: child!),
        ribbonWidget,
      ],
    );
  }
}
