import 'package:flutter/material.dart';

class _RoomBounds {
  double minX = double.infinity;
  double minY = double.infinity;
  double maxX = double.negativeInfinity;
  double maxY = double.negativeInfinity;
  void addRect(double left, double top, double width, double height) {
    if (left < minX) minX = left;
    if (top < minY) minY = top;
    if (left + width > maxX) maxX = left + width;
    if (top + height > maxY) maxY = top + height;
  }
}

class WorkspaceMapViewer extends StatefulWidget {
  final List<Map<String, dynamic>> features;
  final List<Map<String, dynamic>> workspaces;
  final List<Map<String, dynamic>> allWorkspaces;
  final String? selectedWorkspaceId;
  final double? containerHeight;
  final Function(Map<String, dynamic> workspace) onSelected;

  const WorkspaceMapViewer({
    super.key,
    required this.features,
    required this.workspaces,
    this.allWorkspaces = const [],
    this.selectedWorkspaceId,
    this.containerHeight,
    required this.onSelected,
  });

  @override
  State<WorkspaceMapViewer> createState() => _WorkspaceMapViewerState();
}

class _WorkspaceMapViewerState extends State<WorkspaceMapViewer> {
  final TransformationController _controller = TransformationController();
  // Track the last viewport size we initialized for — reinit if size changes
  Size? _lastViewportSize;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Recursively extracts all [x, y] leaf coordinate pairs from a GeoJSON
  /// coordinates array, regardless of nesting depth (Point/LineString/Polygon/
  /// MultiPolygon etc.).
  void _extractBounds(List coords, void Function(double x, double y) cb) {
    if (coords.isEmpty) return;
    if (coords[0] is num) {
      if (coords.length >= 2) {
        cb((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
      }
    } else {
      for (final item in coords) {
        if (item is List) _extractBounds(item, cb);
      }
    }
  }

  void _initTransform(double viewW, double viewH, double mapW, double mapH, Rect? targetRect) {
    if (mapW <= 0 || mapH <= 0 || viewW <= 0 || viewH <= 0) return;
    
    final scaleX = viewW / mapW;
    final scaleY = viewH / mapH;
    final fitScale = (scaleX < scaleY ? scaleX : scaleY) * 0.92;
    
    double scale;
    double dx, dy;
    
    if (targetRect != null) {
      // Focus on the selected workspace: zoom in relative to the fitScale, but not too much.
      // E.g., 2.5x the normal view
      scale = fitScale * 2.5;
      
      // But don't zoom in so much that the desk fills the entire screen
      final maxTargetScale = viewW / (targetRect.width * 2); 
      if (scale > maxTargetScale && maxTargetScale > fitScale) {
          scale = maxTargetScale;
      }
      
      scale = scale.clamp(0.001, 100.0);
      
      final targetCx = targetRect.left + targetRect.width / 2;
      final targetCy = targetRect.top + targetRect.height / 2;
      dx = (viewW / 2) - (targetCx * scale);
      dy = (viewH / 2) - (targetCy * scale);
    } else {
      // Fit map to screen by default
      scale = fitScale;
      
      // Enforce a minimum scale just in case the map is ridiculously wide
      // but only up to 2x the fitScale
      final minReadableScale = fitScale * 2.0; 
      if (scale < minReadableScale) scale = minReadableScale;
      scale = scale.clamp(0.001, 100.0);
      
      dx = (viewW - mapW * scale) / 2;
      dy = (viewH - mapH * scale) / 2;
    }

    final m = Matrix4.identity();
    m.setTranslationRaw(dx, dy, 0.0);
    m.setEntry(0, 0, scale);
    m.setEntry(1, 1, scale);
    m.setEntry(2, 2, scale);
    _controller.value = m;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) {
      return const Center(child: Text('Plan non disponible'));
    }

    // ── 1. Compute bounding box of all GeoJSON features ──────────────────────
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    
    double totalDeskWidth = 0.0;
    int deskCount = 0;
    Rect? selectedRect;

    for (final feature in widget.features) {
      final props = feature['properties'] ?? {};
      final coords = feature['geometry']?['coordinates'] as List?;
      if (coords == null) continue;
      
      double fMinX = double.infinity, fMinY = double.infinity;
      double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
      
      _extractBounds(coords, (x, y) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        
        if (x < fMinX) fMinX = x;
        if (y < fMinY) fMinY = y;
        if (x > fMaxX) fMaxX = x;
        if (y > fMaxY) fMaxY = y;
      });
      
      if (fMinX == double.infinity) continue;
      
      final isDesk = props['workspaceType'] == 'Desk';
      final width = fMaxX - fMinX;
      if (isDesk && width > 0) {
        totalDeskWidth += width;
        deskCount++;
      }
      
      final wsId = (props['workspaceId']?.toString() ?? props['roomId']?.toString() ?? props['id']?.toString())?.toLowerCase();
      if (widget.selectedWorkspaceId != null && wsId == widget.selectedWorkspaceId?.toLowerCase()) {
        selectedRect = Rect.fromLTRB(fMinX, fMinY, fMaxX, fMaxY);
      }
    }

    if (minX == double.infinity) {
      return const Center(child: Text('Erreur de plan'));
    }

    const padding = 40.0;
    final mapWidth = maxX - minX + padding * 2;
    final mapHeight = maxY - minY + padding * 2;
    
    if (selectedRect != null) {
      // Offset selectedRect by global minX/minY and padding so it matches the canvas coordinates
      selectedRect = Rect.fromLTRB(
        selectedRect.left - minX + padding, 
        selectedRect.top - minY + padding, 
        selectedRect.right - minX + padding, 
        selectedRect.bottom - minY + padding
      );
    }

    final wsMap = {
      for (var w in widget.workspaces) w['id']?.toString().toLowerCase(): w
    };
    final allWsMap = {
      for (var w in widget.allWorkspaces) w['id']?.toString().toLowerCase(): w
    };

    // ── 2. LayoutBuilder knows the REAL available size synchronously ─────────
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewW = constraints.maxWidth;
        final viewH = constraints.maxHeight.isInfinite
            ? (widget.containerHeight ?? 400.0)
            : constraints.maxHeight;

        final viewportSize = Size(viewW, viewH);
        if (_lastViewportSize != viewportSize) {
          _lastViewportSize = viewportSize;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _initTransform(viewW, viewH, mapWidth, mapHeight, selectedRect);
          });
        }

        // ── 3. Build the feature widgets ─────────────────────────────────────
        final Map<String, _RoomBounds> roomBounds = {};
        final List<Widget> featureWidgets = [];

        for (final feature in widget.features) {
          final props = feature['properties'] ?? {};
          final wsId = (props['workspaceId']?.toString() ??
                  props['roomId']?.toString() ??
                  props['id']?.toString())
              ?.toLowerCase();
          final isDesk = props['workspaceType'] == 'Desk';
          final workspace = wsMap[wsId];
          final isBookable = workspace != null;
          final isSelected = widget.selectedWorkspaceId != null &&
              widget.selectedWorkspaceId?.toLowerCase() == wsId;

          final coords = feature['geometry']?['coordinates'] as List?;
          if (coords == null || coords.isEmpty) continue;

          double fMinX = double.infinity, fMinY = double.infinity;
          double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
          _extractBounds(coords, (x, y) {
            if (x < fMinX) fMinX = x;
            if (y < fMinY) fMinY = y;
            if (x > fMaxX) fMaxX = x;
            if (y > fMaxY) fMaxY = y;
          });
          if (fMinX == double.infinity) continue;

          final left = fMinX - minX + padding;
          final top = fMinY - minY + padding;
          final width = fMaxX - fMinX;
          final height = fMaxY - fMinY;

          // Label
          String label = '';
          String? roomName;
          final propName = props['name']?.toString() ??
              props['title']?.toString() ??
              props['label']?.toString() ??
              props['workspaceName']?.toString() ??
              props['text']?.toString() ??
              props['description']?.toString();

          if (workspace != null) {
            final name = workspace['name']?.toString() ?? propName ?? '';
            final parts = name.split('-');
            label = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;
            final lastDash = name.lastIndexOf('-');
            if (lastDash > 0 && lastDash < name.length - 1) {
              final suffix = name.substring(lastDash + 1);
              roomName = (suffix.length <= 4 && !suffix.contains(' '))
                  ? name.substring(0, lastDash)
                  : name;
            } else {
              roomName = name;
            }
            if (roomName.isNotEmpty) {
              roomBounds
                  .putIfAbsent(roomName, () => _RoomBounds())
                  .addRect(left, top, width, height);
            }
          } else if (!isDesk) {
            final roomWs = wsId != null ? allWsMap[wsId] : null;
            label = roomWs?['name']?.toString() ??
                propName ??
                (wsId != null ? 'Err: $wsId' : '');
          }

          // Point features (no area) → just a label
          if (width == 0 && height == 0) {
            if (label.isEmpty) continue;
            featureWidgets.add(Positioned(
              left: left - 50,
              top: top - 10,
              width: 100,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ));
            continue;
          }

          final bgColor = isSelected
              ? Theme.of(context).colorScheme.primary
              : isBookable
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHigh;

          final textColor = isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : isBookable
                  ? Theme.of(context).colorScheme.onPrimaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant;

          featureWidgets.add(Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: GestureDetector(
              onTap: () {
                if (isBookable) widget.onSelected(workspace);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                alignment: Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 10,
                        color: textColor,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
        }

        // ── 4. Room group outlines ────────────────────────────────────────────
        final List<Widget> roomWidgets = [];
        roomBounds.forEach((name, bounds) {
          if (bounds.minX == double.infinity) return;
          roomWidgets.add(Positioned(
            left: bounds.minX - 16,
            top: bounds.minY - 24,
            width: bounds.maxX - bounds.minX + 32,
            height: bounds.maxY - bounds.minY + 40,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Theme.of(context)
                    .colorScheme
                    .surface
                    .withValues(alpha: 0.6),
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: 2, left: 4, right: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      name,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ));
        });

        // ── 5. InteractiveViewer wrapping the positioned stack ────────────────
        return InteractiveViewer(
          transformationController: _controller,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: 0.01,
          maxScale: 50.0,
          child: SizedBox(
            width: mapWidth,
            height: mapHeight,
            child: ColoredBox(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              child: Stack(
                children: [...roomWidgets, ...featureWidgets],
              ),
            ),
          ),
        );
      },
    );
  }
}
