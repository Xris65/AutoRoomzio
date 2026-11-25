import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Squelette Shimmer architectural (5 pièces asymétriques sans chevauchement)
/// affiché pendant le chargement initial de la carte 2D.
class TeamMapSkeleton extends StatelessWidget {
  const TeamMapSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF424242) : const Color(0xFFF5F5F5);

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          const double margin = 16.0;
          const double gap = 14.0;

          if (w <= 0 || h <= 0) return const SizedBox.shrink();

          final double netW =
              (w - (2 * margin) - gap).clamp(0.0, double.infinity);
          final double wLeft = (netW * 0.52).roundToDouble();
          final double wRight = netW - wLeft;

          final double netH =
              (h - (2 * margin) - gap).clamp(0.0, double.infinity);
          final double h5 = (netH * 0.25).roundToDouble();
          final double upperH = netH - h5;

          final double netUpperHLeft =
              (upperH - gap).clamp(0.0, double.infinity);
          final double h1 = (netUpperHLeft * 0.45).roundToDouble();
          final double h3 = netUpperHLeft - h1;

          final double netUpperHRight =
              (upperH - gap).clamp(0.0, double.infinity);
          final double h2 = (netUpperHRight * 0.55).roundToDouble();
          final double h4 = netUpperHRight - h2;

          final double left1 = margin;
          final double top1 = margin;

          final double left2 = margin + wLeft + gap;
          final double top2 = margin;

          final double left3 = margin;
          final double top3 = margin + h1 + gap;

          final double left4 = margin + wLeft + gap;
          final double top4 = margin + h2 + gap;

          final double left5 = margin;
          final double top5 = margin + upperH + gap;
          final double w5 = (w - (2 * margin)).clamp(0.0, double.infinity);

          return ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned(
                  left: left1,
                  top: top1,
                  width: wLeft,
                  height: h1,
                  child: const _RoomSilhouette(
                    titleWidth: 70,
                    deskCount: 4,
                    deskWidth: 32,
                    deskHeight: 24,
                  ),
                ),
                Positioned(
                  left: left2,
                  top: top2,
                  width: wRight,
                  height: h2,
                  child: const _RoomSilhouette(
                    titleWidth: 55,
                    deskCount: 6,
                    deskWidth: 26,
                    deskHeight: 26,
                  ),
                ),
                Positioned(
                  left: left3,
                  top: top3,
                  width: wLeft,
                  height: h3,
                  child: const _RoomSilhouette(
                    titleWidth: 65,
                    deskCount: 4,
                    deskWidth: 32,
                    deskHeight: 26,
                  ),
                ),
                Positioned(
                  left: left4,
                  top: top4,
                  width: wRight,
                  height: h4,
                  child: const _RoomSilhouette(
                    titleWidth: 50,
                    deskCount: 4,
                    deskWidth: 28,
                    deskHeight: 28,
                  ),
                ),
                Positioned(
                  left: left5,
                  top: top5,
                  width: w5,
                  height: h5,
                  child: const _RoomSilhouette(
                    titleWidth: 90,
                    deskCount: 6,
                    deskWidth: 36,
                    deskHeight: 22,
                    isRow: true,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RoomSilhouette extends StatelessWidget {
  final double titleWidth;
  final int deskCount;
  final double deskWidth;
  final double deskHeight;
  final bool isRow;

  const _RoomSilhouette({
    required this.titleWidth,
    required this.deskCount,
    required this.deskWidth,
    required this.deskHeight,
    this.isRow = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: titleWidth,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: isRow
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List<Widget>.generate(
                        deskCount,
                        (int _) => Container(
                          width: deskWidth,
                          height: deskHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: List<Widget>.generate(
                        deskCount,
                        (int _) => Container(
                          width: deskWidth,
                          height: deskHeight,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
