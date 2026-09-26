import 'package:flutter/material.dart';
import '../api_service.dart';

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
  bool _initialized = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.features.isEmpty) return const Center(child: Text("Plan non disponible"));

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var feature in widget.features) {
      final geom = feature['geometry'];
      if (geom == null) continue;
      final type = geom['type'];
      final coords = geom['coordinates'] as List?;
      if (coords == null) continue;
      
      void processPoint(List p) {
        if (p.length < 2) return;
        final x = (p[0] as num).toDouble();
        final y = (p[1] as num).toDouble();
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }

      if (type == 'Point') {
        processPoint(coords);
      } else {
        for (var point in coords) {
          if (point is List) processPoint(point);
        }
      }
    }

    if (minX == double.infinity) return const Center(child: Text("Erreur de plan"));

    final padding = 40.0;
    final mapWidth = maxX - minX + (padding * 2);
    final mapHeight = maxY - minY + (padding * 2);

    final wsMap = {for (var w in widget.workspaces) w['id']: w};
    final allWsMap = {for (var w in widget.allWorkspaces) w['id']: w};

    if (!_initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mapWidth > 0 && mapHeight > 0) {
          final screenSize = MediaQuery.of(context).size;
          final viewW = screenSize.width;
          final viewH = widget.containerHeight ?? screenSize.height * 0.55;

          final scaleX = viewW / mapWidth;
          final scaleY = viewH / mapHeight;
          double scale = (scaleX < scaleY ? scaleX : scaleY) * 0.90;
          
          if (scale < 0.001) scale = 0.001;
          if (scale > 5.0) scale = 5.0;

          final dx = (viewW - (mapWidth * scale)) / 2;
          final dy = (viewH - (mapHeight * scale)) / 2;
          
          final matrix = Matrix4.identity();
          matrix.setTranslationRaw(dx, dy, 0.0);
          matrix.scale(scale, scale, 1.0);
          
          _controller.value = matrix;
        }
        _initialized = true;
      });
    }

    return InteractiveViewer(
      transformationController: _controller,
      constrained: false,
      boundaryMargin: EdgeInsets.all(mapWidth > mapHeight ? mapWidth : mapHeight),
      minScale: 0.001,
      maxScale: 5.0,
      child: Container(
        width: mapWidth,
        height: mapHeight,
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        child: Builder(
          builder: (context) {
            final Map<String, _RoomBounds> roomBounds = {};
            final List<Widget> featureWidgets = [];

            for (var feature in widget.features) {
              final props = feature['properties'] ?? {};
              final wsId = props['workspaceId']?.toString();
              final isDesk = props['workspaceType'] == 'Desk';
              final workspace = wsMap[wsId];
              
              final isBookable = workspace != null;
              final isSelected = widget.selectedWorkspaceId != null && widget.selectedWorkspaceId == wsId;

              final geom = feature['geometry'];
              if (geom == null) continue;
              final type = geom['type'];
              final coords = geom['coordinates'] as List?;
              if (coords == null || coords.isEmpty) continue;

              double fMinX = double.infinity, fMinY = double.infinity;
              double fMaxX = double.negativeInfinity, fMaxY = double.negativeInfinity;
              
              void processFeaturePoint(List p) {
                if (p.length < 2) return;
                final x = (p[0] as num).toDouble();
                final y = (p[1] as num).toDouble();
                if (x < fMinX) fMinX = x;
                if (y < fMinY) fMinY = y;
                if (x > fMaxX) fMaxX = x;
                if (y > fMaxY) fMaxY = y;
              }

              if (type == 'Point') {
                processFeaturePoint(coords);
              } else {
                for (var point in coords) {
                  if (point is List) processFeaturePoint(point);
                }
              }
              if (fMinX == double.infinity) continue;

              final left = fMinX - minX + padding;
              final top = fMinY - minY + padding;
              final width = fMaxX - fMinX;
              final height = fMaxY - fMinY;

              String label = "";
              String? roomName;
              
              final propName = props['name']?.toString() ?? props['title']?.toString() ?? props['label']?.toString() ?? props['workspaceName']?.toString() ?? props['text']?.toString() ?? props['description']?.toString();

              if (workspace != null) {
                 final name = workspace['name']?.toString() ?? propName ?? "";
                 final parts = name.split('-');
                 label = parts.isNotEmpty && parts.last.isNotEmpty ? parts.last : name;
                 
                 final lastDash = name.lastIndexOf('-');
                 if (lastDash > 0 && lastDash < name.length - 1) {
                   final suffix = name.substring(lastDash + 1);
                   if (suffix.length <= 4 && !suffix.contains(' ')) {
                     roomName = name.substring(0, lastDash);
                   } else {
                     roomName = name;
                   }
                 } else {
                   roomName = name;
                 }
                 
                 if (roomName.isNotEmpty) {
                   roomBounds.putIfAbsent(roomName, () => _RoomBounds())
                       .addRect(left, top, width, height);
                 }
              } else if (!isDesk) {
                 final roomWs = wsId != null ? allWsMap[wsId] : null;
                 label = roomWs?['name']?.toString() ?? propName ?? "";
              }

              if (width == 0 && height == 0) {
                 if (label.isEmpty) continue;
                 featureWidgets.add(
                   Positioned(
                     left: left - 50,
                     top: top - 10,
                     width: 100,
                     child: Text(
                       label,
                       textAlign: TextAlign.center,
                       style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold),
                     ),
                   )
                 );
                 continue;
              }

              Color bgColor;
              if (isSelected) {
                bgColor = Theme.of(context).colorScheme.primary;
              } else if (isBookable) {
                bgColor = Theme.of(context).colorScheme.primaryContainer;
              } else {
                bgColor = Colors.grey.shade300;
              }

              Color textColor = isSelected 
                ? Theme.of(context).colorScheme.onPrimary 
                : (isBookable ? Theme.of(context).colorScheme.onPrimaryContainer : Colors.grey.shade600);

              featureWidgets.add(
                Positioned(
                  left: left,
                  top: top,
                  width: width,
                  height: height,
                  child: GestureDetector(
                    onTap: () {
                      if (isBookable) {
                        widget.onSelected(workspace!);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
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
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final List<Widget> roomWidgets = [];
            roomBounds.forEach((name, bounds) {
              if (bounds.minX != double.infinity) {
                final rLeft = bounds.minX - 16.0;
                final rTop = bounds.minY - 24.0;
                final rWidth = bounds.maxX - bounds.minX + 32.0;
                final rHeight = bounds.maxY - bounds.minY + 40.0;

                roomWidgets.add(
                  Positioned(
                    left: rLeft,
                    top: rTop,
                    width: rWidth,
                    height: rHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400, width: 2),
                        borderRadius: BorderRadius.circular(8),
                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                      ),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2.0, left: 4.0, right: 4.0),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              name,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
            });

            return Stack(
              children: [
                ...roomWidgets,
                ...featureWidgets,
              ],
            );
          },
        ),
      ),
    );
  }
}
