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
    this.rooms = const <Rect>[],
    this.desks = const <Rect>[],
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

    final double mapW = widget.mapSize.width;
    final double mapH = widget.mapSize.height;
    final double viewW = widget.viewportSize.width;
    final double viewH = widget.viewportSize.height;

    final double scaleFactor = math.min(
      canvasSize.width / mapW,
      canvasSize.height / mapH,
    );
    if (scaleFactor <= 0) return;

    final double contentW = mapW * scaleFactor;
    final double contentH = mapH * scaleFactor;
    final double offsetX = (canvasSize.width - contentW) / 2.0;
    final double offsetY = (canvasSize.height - contentH) / 2.0;

    // Clamp local touch within floor bounds
    final double clampedX = localPos.dx.clamp(offsetX, offsetX + contentW);
    final double clampedY = localPos.dy.clamp(offsetY, offsetY + contentH);

    // Convert to scene coordinates
    final double targetSceneX = (clampedX - offsetX) / scaleFactor;
    final double targetSceneY = (clampedY - offsetY) / scaleFactor;

    // Current camera scale
    final Matrix4 currentMatrix = widget.transformationController.value;
    final double currentScale =
        currentMatrix.entry(0, 0) > 0 ? currentMatrix.entry(0, 0) : 1.0;

    // Reposition camera so (targetSceneX, targetSceneY) is at the center of the viewport
    final double newDx = (viewW / 2.0) - (targetSceneX * currentScale);
    final double newDy = (viewH / 2.0) - (targetSceneY * currentScale);

    final Matrix4 updatedMatrix = currentMatrix.clone();
    updatedMatrix.setEntry(0, 3, newDx);
    updatedMatrix.setEntry(1, 3, newDy);

    widget.transformationController.value = updatedMatrix;
    widget.onTargetSelected?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Color accent = widget.accentColor ?? theme.colorScheme.primary;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: widget.expansionAlignment,
          clipBehavior: Clip.none,
          children: <Widget>[
            ...previousChildren,
            ?currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
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
            color:
                theme.colorScheme.surface.withValues(alpha: isDark ? 0.90 : 0.94),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
              width: 1.5,
            ),
            boxShadow: <BoxShadow>[
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
          color:
              theme.colorScheme.surface.withValues(alpha: isDark ? 0.92 : 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 1.2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Header
            Padding(
              padding:
                  const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
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
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final Size canvasSize =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      return SizedBox(
                        key: const Key('mini_map_canvas'),
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (TapDownDetails details) =>
                              _handleTouch(details.localPosition, canvasSize),
                          onPanStart: (DragStartDetails details) =>
                              _handleTouch(details.localPosition, canvasSize),
                          onPanUpdate: (DragUpdateDetails details) =>
                              _handleTouch(details.localPosition, canvasSize),
                          child: CustomPaint(
                            size: canvasSize,
                            painter: _MiniMapPainter(
                              repaint: widget.transformationController,
                              transformationController:
                                  widget.transformationController,
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
/// Pre-allocates all [Paint] objects to avoid per-frame allocations during pan/zoom.
class _MiniMapPainter extends CustomPainter {
  final TransformationController transformationController;
  final Size viewportSize;
  final Size mapSize;
  final List<Rect> rooms;
  final List<Rect> desks;
  final Color accentColor;
  final bool isDark;

  final Paint _bgPaint;
  final Paint _floorFillPaint;
  final Paint _floorBorderPaint;
  final Paint _roomFillPaint;
  final Paint _roomBorderPaint;
  final Paint _deskPaint;
  final Paint _vpFillPaint;
  final Paint _vpBorderPaint;
  final Paint _centerDotPaint;

  static const Radius _canvasRadius = Radius.circular(6);
  static const Radius _floorRadius = Radius.circular(4);
  static const Radius _roomRadius = Radius.circular(2);

  _MiniMapPainter({
    required super.repaint,
    required this.transformationController,
    required this.viewportSize,
    required this.mapSize,
    required this.rooms,
    required this.desks,
    required this.accentColor,
    required this.isDark,
  })  : _bgPaint = Paint()
          ..color = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        _floorFillPaint = Paint()
          ..color = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        _floorBorderPaint = Paint()
          ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
        _roomFillPaint = Paint()
          ..color = isDark
              ? const Color(0xFF334155).withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.85),
        _roomBorderPaint = Paint()
          ..color = isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8,
        _deskPaint = Paint()
          ..color = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        _vpFillPaint = Paint()
          ..color = accentColor.withValues(alpha: isDark ? 0.25 : 0.20)
          ..style = PaintingStyle.fill,
        _vpBorderPaint = Paint()
          ..color = accentColor.withValues(alpha: 0.90)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
        _centerDotPaint = Paint()
          ..color = accentColor
          ..style = PaintingStyle.fill;

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

    final Rect canvasRect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.clipRRect(RRect.fromRectAndRadius(canvasRect, _canvasRadius));

    // 1. Canvas background
    canvas.drawRect(canvasRect, _bgPaint);

    final double scaleFactor = math.min(
      size.width / mapSize.width,
      size.height / mapSize.height,
    );
    if (scaleFactor <= 0) return;

    final double contentW = mapSize.width * scaleFactor;
    final double contentH = mapSize.height * scaleFactor;
    final double offsetX = (size.width - contentW) / 2.0;
    final double offsetY = (size.height - contentH) / 2.0;

    // 2. Floor perimeter boundary
    final Rect floorRect = Rect.fromLTWH(offsetX, offsetY, contentW, contentH);
    final RRect floorRRect = RRect.fromRectAndRadius(floorRect, _floorRadius);
    canvas.drawRRect(floorRRect, _floorFillPaint);
    canvas.drawRRect(floorRRect, _floorBorderPaint);

    // 3. Draw rooms
    for (final Rect room in rooms) {
      final double rLeft = offsetX + room.left * scaleFactor;
      final double rTop = offsetY + room.top * scaleFactor;
      final double rWidth = room.width * scaleFactor;
      final double rHeight = room.height * scaleFactor;

      if (rWidth > 1 && rHeight > 1) {
        final RRect rRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(rLeft, rTop, rWidth, rHeight),
          _roomRadius,
        );
        canvas.drawRRect(rRect, _roomFillPaint);
        canvas.drawRRect(rRect, _roomBorderPaint);
      }
    }

    // 4. Draw desks silhouette
    for (final Rect desk in desks) {
      final double dLeft = offsetX + desk.left * scaleFactor;
      final double dTop = offsetY + desk.top * scaleFactor;
      final double dWidth = math.max(1.0, desk.width * scaleFactor);
      final double dHeight = math.max(1.0, desk.height * scaleFactor);

      canvas.drawRect(
        Rect.fromLTWH(dLeft, dTop, dWidth, dHeight),
        _deskPaint,
      );
    }

    // 5. Draw Viewport Indicator
    final Matrix4 matrix = transformationController.value;
    final double scale = matrix.entry(0, 0) > 0 ? matrix.entry(0, 0) : 1.0;
    final double dx = matrix.entry(0, 3);
    final double dy = matrix.entry(1, 3);

    final double sceneVpLeft = -dx / scale;
    final double sceneVpTop = -dy / scale;
    final double sceneVpWidth = viewportSize.width / scale;
    final double sceneVpHeight = viewportSize.height / scale;

    final double vpCanvasLeft = offsetX + sceneVpLeft * scaleFactor;
    final double vpCanvasTop = offsetY + sceneVpTop * scaleFactor;
    final double vpCanvasWidth = sceneVpWidth * scaleFactor;
    final double vpCanvasHeight = sceneVpHeight * scaleFactor;

    final Rect vpRect = Rect.fromLTWH(
      vpCanvasLeft,
      vpCanvasTop,
      vpCanvasWidth,
      vpCanvasHeight,
    );

    canvas.drawRect(vpRect, _vpFillPaint);
    canvas.drawRect(vpRect, _vpBorderPaint);

    // Center focal point
    final Offset vpCenter = Offset(
      vpCanvasLeft + vpCanvasWidth / 2.0,
      vpCanvasTop + vpCanvasHeight / 2.0,
    );
    canvas.drawCircle(vpCenter, 2.0, _centerDotPaint);
  }

  static bool _rectsEqual(List<Rect> a, List<Rect> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter oldDelegate) {
    return oldDelegate.transformationController != transformationController ||
        oldDelegate.viewportSize != viewportSize ||
        oldDelegate.mapSize != mapSize ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.isDark != isDark ||
        !_rectsEqual(oldDelegate.rooms, rooms) ||
        !_rectsEqual(oldDelegate.desks, desks);
  }
}
