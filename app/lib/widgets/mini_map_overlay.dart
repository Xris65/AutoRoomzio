import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Overlay widget that renders a compact, semi-transparent mini-map (radar)
/// representing the overall floor layout and the currently visible viewport.
///
/// Features:
/// - Draws rooms and desks silhouette scaled down to fit the mini-map canvas.
/// - Highlights the current camera viewport synchronized with [transformationController].
/// - Tap or drag on the mini-map to instantly pan/center the camera on that zone.
/// - Can be collapsed into a discrete radar floating button and expanded at will.
class MiniMapOverlay extends StatefulWidget {
  final TransformationController transformationController;
  final Size viewportSize;
  final Size mapSize;
  final List<Rect> rooms;
  final List<Rect> desks;
  final bool initiallyExpanded;
  final double miniMapWidth;
  final double miniMapHeight;
  final ValueChanged<bool>? onExpansionChanged;
  final Color? accentColor;
  final VoidCallback? onTargetSelected;
  final Alignment expansionAlignment;

  const MiniMapOverlay({
    super.key,
    required this.transformationController,
    required this.viewportSize,
    required this.mapSize,
    this.rooms = const [],
    this.desks = const [],
    this.initiallyExpanded = false,
    this.miniMapWidth = 148.0,
    this.miniMapHeight = 104.0,
    this.onExpansionChanged,
    this.accentColor,
    this.onTargetSelected,
    this.expansionAlignment = Alignment.bottomLeft,
  });

  @override
  State<MiniMapOverlay> createState() => _MiniMapOverlayState();
}

class _MiniMapOverlayState extends State<MiniMapOverlay> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    widget.onExpansionChanged?.call(_isExpanded);
  }

  void _handleTouch(Offset localPos, Size canvasSize) {
    if (widget.mapSize.width <= 0 ||
        widget.mapSize.height <= 0 ||
        widget.viewportSize.width <= 0 ||
        widget.viewportSize.height <= 0 ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return;
    }

    final mapW = widget.mapSize.width;
    final mapH = widget.mapSize.height;
    final viewW = widget.viewportSize.width;
    final viewH = widget.viewportSize.height;

    final scaleFactor = math.min(
      canvasSize.width / mapW,
      canvasSize.height / mapH,
    );
    if (scaleFactor <= 0) return;

    final contentW = mapW * scaleFactor;
    final contentH = mapH * scaleFactor;
    final offsetX = (canvasSize.width - contentW) / 2.0;
    final offsetY = (canvasSize.height - contentH) / 2.0;

    // Clamp local touch within floor bounds
    final clampedX = localPos.dx.clamp(offsetX, offsetX + contentW);
    final clampedY = localPos.dy.clamp(offsetY, offsetY + contentH);

    // Convert to scene coordinates
    final targetSceneX = (clampedX - offsetX) / scaleFactor;
    final targetSceneY = (clampedY - offsetY) / scaleFactor;

    // Current camera scale
    final currentMatrix = widget.transformationController.value;
    final currentScale = currentMatrix.entry(0, 0) > 0 ? currentMatrix.entry(0, 0) : 1.0;

    // Reposition camera so (targetSceneX, targetSceneY) is at the center of the viewport
    final newDx = (viewW / 2.0) - (targetSceneX * currentScale);
    final newDy = (viewH / 2.0) - (targetSceneY * currentScale);

    final updatedMatrix = currentMatrix.clone();
    updatedMatrix.setEntry(0, 3, newDx);
    updatedMatrix.setEntry(1, 3, newDy);

    widget.transformationController.value = updatedMatrix;
    widget.onTargetSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = widget.accentColor ?? theme.colorScheme.primary;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: widget.expansionAlignment,
          clipBehavior: Clip.none,
          children: [
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.82, end: 1.0).animate(animation),
            alignment: widget.expansionAlignment,
            child: child,
          ),
        );
      },
      child: _isExpanded
          ? _buildExpandedPanel(context, theme, isDark, accent)
          : _buildCollapsedButton(context, theme, isDark, accent),
    );
  }

  Widget _buildCollapsedButton(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accent,
  ) {
    return Material(
      key: const Key('mini_map_toggle_button'),
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleExpanded,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.90 : 0.94),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Tooltip(
            message: 'Radar / Mini-map',
            preferBelow: false,
            child: Icon(
              Icons.radar,
              size: 20,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    Color accent,
  ) {
    return TapRegion(
      key: const Key('mini_map_expanded_region'),
      groupId: 'mini_map_region',
      onTapOutside: (_) {
        if (_isExpanded) {
          setState(() {
            _isExpanded = false;
          });
          widget.onExpansionChanged?.call(false);
        }
      },
      child: Container(
        key: const Key('mini_map_panel'),
        width: widget.miniMapWidth,
        height: widget.miniMapHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.96),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar, size: 13, color: accent),
                    const SizedBox(width: 4),
                    Text(
                      'Radar',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: accent,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  key: const Key('mini_map_collapse_button'),
                  onTap: _toggleExpanded,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(
                      Icons.close,
                      size: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Canvas
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return SizedBox(
                      key: const Key('mini_map_canvas'),
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            _handleTouch(details.localPosition, canvasSize),
                        onPanStart: (details) =>
                            _handleTouch(details.localPosition, canvasSize),
                        onPanUpdate: (details) =>
                            _handleTouch(details.localPosition, canvasSize),
                        child: CustomPaint(
                          size: canvasSize,
                          painter: _MiniMapPainter(
                            repaint: widget.transformationController,
                            transformationController: widget.transformationController,
                            viewportSize: widget.viewportSize,
                            mapSize: widget.mapSize,
                            rooms: widget.rooms,
                            desks: widget.desks,
                            accentColor: accent,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

/// Custom painter for drawing the mini-map rooms, desks, and camera viewport rectangle.
class _MiniMapPainter extends CustomPainter {
  final TransformationController transformationController;
  final Size viewportSize;
  final Size mapSize;
  final List<Rect> rooms;
  final List<Rect> desks;
  final Color accentColor;
  final bool isDark;

  _MiniMapPainter({
    required super.repaint,
    required this.transformationController,
    required this.viewportSize,
    required this.mapSize,
    required this.rooms,
    required this.desks,
    required this.accentColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (mapSize.width <= 0 ||
        mapSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    final canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(canvasRect, const Radius.circular(6)));

    // 1. Canvas background
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    canvas.drawRect(canvasRect, bgPaint);

    final scaleFactor = math.min(
      size.width / mapSize.width,
      size.height / mapSize.height,
    );
    if (scaleFactor <= 0) return;

    final contentW = mapSize.width * scaleFactor;
    final contentH = mapSize.height * scaleFactor;
    final offsetX = (size.width - contentW) / 2.0;
    final offsetY = (size.height - contentH) / 2.0;

    // 2. Floor perimeter boundary
    final floorRect = Rect.fromLTWH(offsetX, offsetY, contentW, contentH);
    final floorFillPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final floorBorderPaint = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final floorRRect = RRect.fromRectAndRadius(floorRect, const Radius.circular(4));
    canvas.drawRRect(floorRRect, floorFillPaint);
    canvas.drawRRect(floorRRect, floorBorderPaint);

    // 3. Draw rooms
    final roomFillPaint = Paint()
      ..color = isDark
          ? const Color(0xFF334155).withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.85);
    final roomBorderPaint = Paint()
      ..color = isDark
          ? const Color(0xFF475569)
          : const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    for (final room in rooms) {
      final rLeft = offsetX + room.left * scaleFactor;
      final rTop = offsetY + room.top * scaleFactor;
      final rWidth = room.width * scaleFactor;
      final rHeight = room.height * scaleFactor;

      if (rWidth > 1 && rHeight > 1) {
        final rRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(rLeft, rTop, rWidth, rHeight),
          const Radius.circular(2),
        );
        canvas.drawRRect(rRect, roomFillPaint);
        canvas.drawRRect(rRect, roomBorderPaint);
      }
    }

    // 4. Draw desks silhouette
    final deskPaint = Paint()
      ..color = isDark
          ? const Color(0xFF64748B)
          : const Color(0xFF94A3B8);

    for (final desk in desks) {
      final dLeft = offsetX + desk.left * scaleFactor;
      final dTop = offsetY + desk.top * scaleFactor;
      final dWidth = math.max(1.0, desk.width * scaleFactor);
      final dHeight = math.max(1.0, desk.height * scaleFactor);

      canvas.drawRect(Rect.fromLTWH(dLeft, dTop, dWidth, dHeight), deskPaint);
    }

    // 5. Draw Viewport Indicator
    final matrix = transformationController.value;
    final scale = matrix.entry(0, 0) > 0 ? matrix.entry(0, 0) : 1.0;
    final dx = matrix.entry(0, 3);
    final dy = matrix.entry(1, 3);

    // Visible scene coordinates
    final sceneVpLeft = -dx / scale;
    final sceneVpTop = -dy / scale;
    final sceneVpWidth = viewportSize.width / scale;
    final sceneVpHeight = viewportSize.height / scale;

    // Viewport mapped to mini-map coordinates
    final vpCanvasLeft = offsetX + sceneVpLeft * scaleFactor;
    final vpCanvasTop = offsetY + sceneVpTop * scaleFactor;
    final vpCanvasWidth = sceneVpWidth * scaleFactor;
    final vpCanvasHeight = sceneVpHeight * scaleFactor;

    final vpRect = Rect.fromLTWH(vpCanvasLeft, vpCanvasTop, vpCanvasWidth, vpCanvasHeight);

    // Viewport fill
    final vpFillPaint = Paint()
      ..color = accentColor.withValues(alpha: isDark ? 0.25 : 0.20)
      ..style = PaintingStyle.fill;
    canvas.drawRect(vpRect, vpFillPaint);

    // Viewport border
    final vpBorderPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(vpRect, vpBorderPaint);

    // Center focal point
    final vpCenter = Offset(
      vpCanvasLeft + vpCanvasWidth / 2.0,
      vpCanvasTop + vpCanvasHeight / 2.0,
    );
    final centerDotPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(vpCenter, 2.0, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.transformationController != transformationController ||
        oldDelegate.viewportSize != viewportSize ||
        oldDelegate.mapSize != mapSize ||
        oldDelegate.rooms != rooms ||
        oldDelegate.desks != desks ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark;
  }
}
